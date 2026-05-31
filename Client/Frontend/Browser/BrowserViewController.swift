/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Combine
import Defaults
import Foundation
import MobileCoreServices
import Photos
import SDWebImage
import Shared
import SnapKit
import Storage
import SwiftUI
import SwiftyJSON
import UIKit
import WalletConnectSwift
import WebKit
import XCGLogger

private let ActionSheetTitleMaxLength = 120

protocol ModalPresenter {
    func showModal<Content: View>(
        style: OverlayStyle,
        headerButton: OverlayHeaderButton?,
        content: @escaping () -> Content,
        onDismiss: (() -> Void)?)
    func presentFullScreenModal(content: AnyView, completion: (() -> Void)?)
    func dismissCurrentOverlay()
}

class BrowserViewController: UIViewController, ModalPresenter {
    private(set) var searchQueryModel = SearchQueryModel()
    private(set) var locationModel = LocationViewModel()

    private var shouldPresentDBPrompt = false
    var shouldLogDBPrompt = false

    lazy var readerModeModel: ReaderModeModel = {
        let model = ReaderModeModel(
            setReadingMode: { [self] enabled in
                DispatchQueue.main.async {
                    if enabled {
                        enableReaderMode()
                    } else {
                        disableReaderMode()
                    }
                }
            }, tabManager: tabManager)
        model.delegate = self
        return model
    }()
    private(set) lazy var web3Model: Web3Model = {
        return Web3Model(server: self.server, presenter: self, tabManager: self.tabManager)
    }()

    private(set) lazy var suggestionModel: SuggestionModel = {
        return SuggestionModel(bvc: self, profile: self.profile, queryModel: self.searchQueryModel)
    }()

    private(set) lazy var zeroQueryModel: ZeroQueryModel = {
        let model = ZeroQueryModel(
            bvc: self,
            profile: profile,
            shareURLHandler: { url, view in
                let helper = ShareExtensionHelper(url: url, tab: nil)
                let controller = helper.createActivityViewController({ (_, _) in })
                if UIDevice.current.userInterfaceIdiom != .pad {
                    controller.modalPresentationStyle = .formSheet
                } else {
                    controller.popoverPresentationController?.sourceView = view
                    controller.popoverPresentationController?.permittedArrowDirections = .up
                }

                self.present(controller, animated: true, completion: nil)
            })
        model.delegate = self
        return model
    }()

    let chromeModel = TabChromeModel()
    let incognitoModel = IncognitoModel(isIncognito: false)

    lazy var gridModel: GridModel = {
        GridModel(tabManager: tabManager, tabGroupManager: tabGroupManager)
    }()
    lazy var browserModel: BrowserModel = {
        BrowserModel(
            gridModel: gridModel, tabManager: tabManager, chromeModel: chromeModel,
            incognitoModel: incognitoModel)
    }()

    lazy var toolbarModel: SwitcherToolbarModel = {
        SwitcherToolbarModel(
            tabManager: tabManager,
            openLazyTab: { self.openLazyTab(openedFrom: .tabTray) },
            createNewSpace: {
                self.showModal(style: .withTitle) {
                    CreateSpaceOverlayContent()
                        .environmentObject(self.gridModel.spaceCardModel)
                }
            },
            onNeevaMenuAction: self.perform(neevaMenuAction:))
    }()

    lazy var browserHost: BrowserHost = {
        BrowserHost(bvc: self)
    }()

    lazy var overlayManager: OverlayManager = {
        OverlayManager()
    }()

    private(set) lazy var simulateForwardModel: SimulatedSwipeModel = {
        SimulatedSwipeModel(
            tabManager: tabManager, chromeModel: chromeModel, swipeDirection: .forward)
    }()

    private(set) lazy var simulateBackModel: SimulatedSwipeModel = {
        SimulatedSwipeModel(tabManager: tabManager, chromeModel: chromeModel, swipeDirection: .back)
    }()

    private(set) lazy var tabContainerModel: TabContainerModel = {
        return TabContainerModel(bvc: self)
    }()

    private(set) lazy var trackingStatsViewModel: TrackingStatsViewModel = {
        return TrackingStatsViewModel(tabManager: tabManager)
    }()

    var findInPageModel: FindInPageModel?
    var overlayWindowManager: WindowManager?
    var introViewModel: IntroViewModel?

    private(set) var readerModeCache: ReaderModeCache
    private(set) var screenshotHelper: ScreenshotHelper!

    // popover rotation handling
    var displayedPopoverController: UIViewController?
    var updateDisplayedPopoverProperties: (() -> Void)?

    let profile: Profile
    let tabManager: TabManager
    let tabGroupManager: TabGroupManager
    var server: Server? = nil

    // Backdrop used for displaying greyed background for private tabs
    private(set) var webViewContainerBackdrop: UIView!
    fileprivate var keyboardState: KeyboardState?

    // Tracking navigation items to record history types.
    // TODO: weak references?
    private var ignoredNavigation = Set<WKNavigation>()
    private var typedNavigation = [WKNavigation: VisitType]()

    // Keep track of allowed `URLRequest`s from `webView(_:decidePolicyFor:decisionHandler:)` so
    // that we can obtain the originating `URLRequest` when a `URLResponse` is received. This will
    // allow us to re-trigger the `URLRequest` if the user requests a file to be downloaded.
    var pendingRequests = [String: URLRequest]()

    // This is set when the user taps "Download Link" from the context menu. We then force a
    // download of the next request through the `WKNavigationDelegate` that matches this web view.
    weak var pendingDownloadWebView: WKWebView?

    let downloadQueue = DownloadQueue()

    private(set) var feedbackImage: UIImage?

    static var createNewTabOnStartForTesting: Bool = false

    /// Update the screenshot sent along with feedback. Called before opening the Neeva Menu.
    func updateFeedbackImage() {
        UIGraphicsBeginImageContextWithOptions(view.window!.bounds.size, true, 0)
        defer { UIGraphicsEndImageContext() }

        if !view.window!.drawHierarchy(in: view.window!.bounds, afterScreenUpdates: false) {
            // ???
            print("failed to draw hierarchy")
        }
        feedbackImage = UIGraphicsGetImageFromCurrentImageContext()
    }

    private var subscriptions: Set<AnyCancellable> = []

    init(profile: Profile, scene: UIScene) {
        self.profile = profile
        self.tabManager = TabManager(profile: profile, scene: scene, incognitoModel: incognitoModel)
        self.tabGroupManager = TabGroupManager(tabManager: tabManager)
        self.readerModeCache = DiskReaderModeCache.sharedInstance
        super.init(nibName: nil, bundle: nil)

        chromeModel.topBarDelegate = self
        chromeModel.toolbarDelegate = self
        if FeatureFlag[.enableCryptoWallet] {
            self.configureWalletServer()
        }
        didInit()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var prefersStatusBarHidden: Bool {
        return false
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }

    override func viewWillTransition(
        to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)

        dismissVisibleMenus()

        // The popover view controller is presented with `present`
        // this hide method calls `dismiss`. When it is called inside
        // cooridnator.animate, it breaks the UI after rotation.
        if !chromeModel.inlineToolbar {
            hideOverlayPopoverViewController()
        }

        coordinator.animate { [self] context in
            browserModel.scrollingControlModel.updateMinimumZoom()

            if let popover = displayedPopoverController {
                updateDisplayedPopoverProperties?()
                present(popover, animated: true, completion: nil)
            }

            if chromeModel.inlineToolbar {
                hideOverlaySheetViewController()
            }
        } completion: { [self] _ in
            browserModel.scrollingControlModel.setMinimumZoom()
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    fileprivate func didInit() {
        screenshotHelper = ScreenshotHelper(controller: self)
        tabManager.addDelegate(self)
        tabManager.addNavigationDelegate(self)
        downloadQueue.delegate = self
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .default
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        self.updateViewConstraints()
    }

    func shouldShowFooterForTraitCollection(_ previousTraitCollection: UITraitCollection) -> Bool {
        return previousTraitCollection.verticalSizeClass != .compact
            && previousTraitCollection.horizontalSizeClass != .regular
    }

    func updateToolbarStateForTraitCollection(
        _ newCollection: UITraitCollection,
        withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator? = nil
    ) {
        let showToolbar = shouldShowFooterForTraitCollection(newCollection)
        chromeModel.inlineToolbar = !showToolbar

        if let tab = tabManager.selectedTab,
            let webView = tab.webView
        {
            updateURLBarDisplayURL(tab)
            chromeModel.canGoBack = webView.canGoBack
            chromeModel.canGoForward = webView.canGoForward
        }
    }

    override func willTransition(
        to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.willTransition(to: newCollection, with: coordinator)

        // During split screen launching on iPad, this callback gets fired before viewDidLoad gets a chance to
        // set things up. Make sure to only update the toolbar state if the view is ready for it.
        if isViewLoaded {
            updateToolbarStateForTraitCollection(
                newCollection, withTransitionCoordinator: coordinator)
        }

        displayedPopoverController?.dismiss(animated: true, completion: nil)

        if tabContainerModel.currentContentUI != .previewHome {
            coordinator.animate { [self] context in
                browserModel.scrollingControlModel.showToolbars(animated: false)
            }
        }
    }

    func dismissVisibleMenus() {
        displayedPopoverController?.dismiss(animated: true)
    }

    @objc func appDidEnterBackgroundNotification() {
        displayedPopoverController?.dismiss(animated: false) {
            self.updateDisplayedPopoverProperties = nil
            self.displayedPopoverController = nil
        }
    }

    @objc func tappedTopArea() {
        browserModel.scrollingControlModel.showToolbars(animated: true)
    }

    @objc func appWillResignActiveNotification() {
        // Dismiss any popovers that might be visible
        displayedPopoverController?.dismiss(animated: false) {
            self.updateDisplayedPopoverProperties = nil
            self.displayedPopoverController = nil
        }

        // If we are displying a private tab, hide any elements in the tab that we wouldn't want shown
        // when the app is in the app switcher
        guard incognitoModel.isIncognito else {
            return
        }

        view.bringSubviewToFront(webViewContainerBackdrop)
        webViewContainerBackdrop.alpha = 1
        presentedViewController?.popoverPresentationController?.containerView?.alpha = 0
        presentedViewController?.view.alpha = 0
    }

    @objc func appDidBecomeActiveNotification() {
        // Re-show any components that might have been hidden because they were being displayed
        // as part of a private mode tab
        UIView.animate(
            withDuration: 0.2, delay: 0, options: UIView.AnimationOptions(),
            animations: {
                self.presentedViewController?.popoverPresentationController?.containerView?.alpha =
                    1
                self.presentedViewController?.view.alpha = 1
                self.view.backgroundColor = UIColor.clear
            },
            completion: { _ in
                self.webViewContainerBackdrop.alpha = 0
                self.view.sendSubviewToBack(self.webViewContainerBackdrop)
            })

        // Re-show toolbar which might have been hidden during scrolling (prior to app moving into the background)
        if tabContainerModel.currentContentUI != .previewHome {
            browserModel.scrollingControlModel.showToolbars(animated: false)
        }

        if NeevaUserInfo.shared.isUserLoggedIn {
            DispatchQueue.main.async {
                SpaceStore.shared.refresh()

                self.chromeModel.appActiveRefreshSubscription = SpaceStore.shared.$state.sink {
                    state in
                    if case .ready = state, let url = self.tabManager.selectedTab?.url {
                        self.chromeModel.urlInSpace = SpaceStore.shared.urlInASpace(url)
                        self.chromeModel.appActiveRefreshSubscription?.cancel()
                    }
                }
            }
        }

        if FeatureFlag[.enableSuggestedSpaces] {
            DispatchQueue.main.async {
                SpaceStore.suggested.refresh()
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillResignActiveNotification),
            name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActiveNotification),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackgroundNotification),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        KeyboardHelper.defaultHelper.addDelegate(self)

        // In case if the background is accidentally shown
        view.backgroundColor = .DefaultBackground

        webViewContainerBackdrop = UIView()
        webViewContainerBackdrop.backgroundColor = UIColor.Photon.Ink90
        webViewContainerBackdrop.alpha = 0
        view.addSubview(webViewContainerBackdrop)

        browserHost.willMove(toParent: self)
        view.addSubview(browserHost.view)
        addChild(browserHost)

        self.updateToolbarStateForTraitCollection(self.traitCollection)

        setupConstraints()

        // Setup UIDropInteraction to handle dragging and dropping
        // links into the view from other apps.
        let dropInteraction = UIDropInteraction(delegate: self)
        view.addInteraction(dropInteraction)

        setNeedsStatusBarAppearanceUpdate()

        for tab in tabManager.tabs {
            // Update the `background-color` of any blank webviews.
            (tab.webView as? TabWebView)?.applyTheme()
        }
        tabManager.selectedTab?.applyTheme()

        guard
            let contentScript = self.tabManager.selectedTab?.getContentScript(
                name: ReaderMode.name())
        else { return }
        appyThemeForPreferences(contentScript: contentScript)
    }

    fileprivate func setupConstraints() {
        browserHost.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        webViewContainerBackdrop.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    func loadQueuedTabs(receivedURLs: [URL]? = nil) {
        // Chain off of a trivial deferred in order to run on the background queue.
        succeed().upon { res in
            self.dequeueQueuedTabs(receivedURLs: receivedURLs ?? [])
        }
    }

    fileprivate func dequeueQueuedTabs(receivedURLs: [URL]) {
        assert(!Thread.current.isMainThread, "This must be called in the background.")
        self.profile.queue.getQueuedTabs() >>== { cursor in

            // This assumes that the DB returns rows in some kind of sane order.
            // It does in practice, so WFM.
            if cursor.count > 0 {

                // Filter out any tabs received by a push notification to prevent dupes.
                let urls = cursor.compactMap { $0?.url.asURL }.filter { !receivedURLs.contains($0) }
                if !urls.isEmpty {
                    DispatchQueue.main.async {
                        self.tabManager.addTabsForURLs(urls, zombie: false)
                    }
                }

                // Clear *after* making an attempt to open. We're making a bet that
                // it's better to run the risk of perhaps opening twice on a crash,
                // rather than losing data.
                self.profile.queue.clearQueuedTabs()
            }

            // Then, open any received URLs from push notifications.
            if !receivedURLs.isEmpty {
                DispatchQueue.main.async {
                    self.tabManager.addTabsForURLs(receivedURLs, zombie: false)
                }
            }
        }
    }

    // Because crashedLastLaunch is sticky, it does not get reset, we need to remember its
    // value so that we do not keep asking the user to restore their tabs.
    private var displayedRestoreTabsAlert = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // On iPhone, if we are about to show the On-Boarding, blank out the tab so that it does
        // not flash before we present. This change of alpha also participates in the animation when
        // the intro view is dismissed.
        if UIDevice.current.userInterfaceIdiom == .phone {
            self.view.alpha = Defaults[.introSeen] ? 1.0 : 0.0
        }

        // config log environment variable
        ClientLogger.shared.env = EnvironmentHelper.shared.env

        let _ = tabManager.restoreTabs()

        // Handle the case of an existing user upgrading to a version of the app
        // that supports preview mode. They will have tabs already, so we don't
        // want to show them the preview home experience.
        // TODO: This is flawed as an existing user may have closed their tabs.
        if !tabManager.tabs.isEmpty {
            Defaults[.didFirstNavigation] = true
        }

        DispatchQueue.main.async {
            if Self.createNewTabOnStartForTesting {
                self.tabManager.select(self.tabManager.addTab())
            } else if !Defaults[.didFirstNavigation] {
                self.showPreviewHome()
            } else if self.tabManager.normalTabs.isEmpty {
                // No tabs from a prior session — open a blank tab so the user
                // lands in a usable browser rather than an empty tab tray.
                self.tabManager.select(self.tabManager.addTab())
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        presentIntroViewController()

        screenshotHelper.viewIsVisible = true
        screenshotHelper.takePendingScreenshots(tabManager.tabs)
        overlayWindowManager = WindowManager(parentWindow: view.window!)

        super.viewDidAppear(animated)

        showQueuedAlertIfAvailable()
    }

    fileprivate func showQueuedAlertIfAvailable() {
        if let queuedAlertInfo = tabManager.selectedTab?.dequeueJavascriptAlertPrompt() {
            let alertController = queuedAlertInfo.alertController()
            alertController.delegate = self
            present(alertController, animated: true, completion: nil)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        screenshotHelper.viewIsVisible = false
        super.viewWillDisappear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }

    public func showZeroQuery(
        openedFrom: ZeroQueryOpenedLocation? = nil,
        isLazyTab: Bool = false
    ) {
        // makes sure zeroQuery isn't already open
        guard zeroQueryModel.openedFrom == nil else { return }

        if browserModel.showGrid {
            hideCardGrid(withAnimation: false)
        }

        if isLazyTab {
            chromeModel.triggerOverlay()
        }

        searchQueryModel.value = ""

        self.tabContainerModel.updateContent(
            .showZeroQuery(
                isIncognito: incognitoModel.isIncognito,
                isLazyTab: isLazyTab,
                openedFrom))
    }

    public func closeLazyTab() {
        // Have to be a lazy tab to close a lazy tab
        guard self.zeroQueryModel.isLazyTab else {
            print("Tried to close lazy tab that wasn't a lazy tab")
            hideZeroQuery()
            return
        }

        DispatchQueue.main.async {
            switch self.zeroQueryModel.openedFrom {
            case .tabTray:
                if Defaults[.didFirstNavigation] {
                    self.showTabTray()
                }
            case .createdTab:
                self.tabManager.close(self.tabManager.selectedTab!)
            default:
                break
            }

            self.hideZeroQuery()
        }
    }

    public func hideZeroQuery() {
        chromeModel.setEditingLocation(to: false)

        DispatchQueue.main.async { [self] in
            tabContainerModel.updateContent(.hideZeroQuery)
            zeroQueryModel.reset(bvc: self)

            if tabContainerModel.currentContentUI == .previewHome {
                browserModel.scrollingControlModel.showToolbars(animated: true)
            }
        }
    }

    public func showPreviewHome() {
        tabContainerModel.updateContent(.showPreviewHome)
        browserModel.scrollingControlModel.showToolbars(animated: false)
    }

    fileprivate func updateInZeroQuery(_ url: URL?) {
        if !chromeModel.isEditingLocation {
            guard let url = url else {
                hideZeroQuery()
                return
            }

            if !url.absoluteString.hasPrefix(
                "\(InternalURL.baseUrl)/\(SessionRestoreHandler.path)")
            {
                hideZeroQuery()
            }
        }
    }

    private func hideOverlaySheetViewController() {
        if case .sheet = overlayManager.currentOverlay {
            overlayManager.hideCurrentOverlay()
        }
    }

    private func hideOverlayPopoverViewController() {
        if case .popover = overlayManager.currentOverlay {
            overlayManager.hideCurrentOverlay()
        }
    }

    func presentFullScreenModal(content: AnyView, completion: (() -> Void)? = nil) {
        overlayManager.presentFullScreenModal(content: content, completion: completion)
    }

    func dismissCurrentOverlay() {
        overlayManager.hideCurrentOverlay()
    }

    /// Present Content as sheet if on iPhone and in Portrait; otherwise, present as popover
    ///  - Tag: showModal
    func showModal<Content: View>(
        style: OverlayStyle,
        headerButton: OverlayHeaderButton? = nil,
        @ViewBuilder content: @escaping () -> Content,
        onDismiss: (() -> Void)? = nil
    ) {
        showModal(
            style: style,
            headerButton: headerButton,
            headerContent: { EmptyView() },
            content: content,
            onDismiss: onDismiss
        )
    }

    func showModal<Content: View, HeaderContent: View>(
        style: OverlayStyle,
        headerButton: OverlayHeaderButton? = nil,
        @ViewBuilder headerContent: @escaping () -> HeaderContent,
        @ViewBuilder content: @escaping () -> Content,
        onDismiss: (() -> Void)? = nil
    ) {
        if !chromeModel.inlineToolbar {
            showAsModalOverlaySheet(
                style: style,
                content: content,
                onDismiss: onDismiss,
                headerButton: headerButton,
                headerContent: headerContent
            )
        } else {
            showAsModalOverlayPopover(
                style: style, content: content, onDismiss: onDismiss, headerButton: headerButton)
        }
    }

    func showAsModalOverlaySheet<Content: View>(
        style: OverlayStyle,
        @ViewBuilder content: @escaping () -> Content,
        onDismiss: (() -> Void)? = nil,
        headerButton: OverlayHeaderButton? = nil
    ) {
        showAsModalOverlaySheet(
            style: style,
            content: content,
            onDismiss: onDismiss,
            headerButton: nil,
            headerContent: { EmptyView() }
        )
    }

    func showAsModalOverlaySheet<Content: View, HeaderContent: View>(
        style: OverlayStyle,
        @ViewBuilder content: @escaping () -> Content,
        onDismiss: (() -> Void)? = nil,
        headerButton: OverlayHeaderButton? = nil,
        @ViewBuilder headerContent: @escaping () -> HeaderContent
    ) {
        let overlayView = OverlaySheetRootView(
            style: style,
            content: { AnyView(erasing: content()) },
            onDismiss: {
                self.overlayManager.hideCurrentOverlay()
                onDismiss?()
            },
            onOpenURL: { url in
                self.overlayManager.hideCurrentOverlay()
                self.openURLInNewTabPreservingIncognitoState(url)
            },
            headerButton: headerButton,
            headerContent: { AnyView(erasing: headerContent()) }
        )

        overlayManager.show(overlay: .sheet(overlayView))
    }

    func showAsModalOverlayPopover<Content: View>(
        style: OverlayStyle,
        @ViewBuilder content: @escaping () -> Content,
        onDismiss: (() -> Void)? = nil,
        headerButton: OverlayHeaderButton? = nil
    ) {
        let popoverView = PopoverRootView(
            style: style, content: { AnyView(erasing: content()) },
            onDismiss: {
                self.overlayManager.hideCurrentOverlay()
                onDismiss?()
            },
            onOpenURL: { url in
                self.overlayManager.hideCurrentOverlay()
                self.openURLInNewTabPreservingIncognitoState(url)
            }, headerButton: headerButton)

        overlayManager.show(overlay: .popover(popoverView))
    }

    func finishEditingAndSubmit(
        _ url: URL,
        visitType: VisitType,
        forTab tab: Tab?,
        with suggestedQuery: String? = nil
    ) {
        if BrowserViewController.isCommandKeyPressed && tabManager.getTabCountForCurrentType() > 0 {
            openURLInBackground(url)
            return
        }

        if zeroQueryModel.targetTab == .existingOrNewTab {
            hideZeroQuery()
            tabManager.createOrSwitchToTab(
                for: url,
                query: searchQueryModel.value,
                suggestedQuery: suggestedQuery,
                visitType: visitType
            )
        } else if zeroQueryModel.isLazyTab || zeroQueryModel.targetTab == .newTab {
            hideZeroQuery()
            openURLInNewTab(
                url,
                isPrivate: zeroQueryModel.isIncognito,
                query: searchQueryModel.value,
                visitType: visitType
            )
        } else if let tab = tab {
            if zeroQueryModel.openedFrom == .backButton {
                // Once user changes current URL from the back button, the forward history list needs
                // to be overriden. Going back, and THEN loading the request accomplishes that.
                DispatchQueue.main.async {
                    tab.webView?.goBack()
                    guard let nav = tab.loadRequest(URLRequest(url: url)) else {
                        return
                    }
                    self.recordNavigationInTab(tab, navigation: nav, visitType: visitType)
                }
            } else if let nav = tab.loadRequest(URLRequest(url: url)) {
                tab.queryForNavigation.currentQuery = .init(
                    typed: searchQueryModel.value, suggested: suggestedQuery)
                recordNavigationInTab(tab, navigation: nav, visitType: visitType)
            }
        }

        locationModel.url = url
        chromeModel.setEditingLocation(to: false)
        chromeModel.urlInSpace = SpaceStore.shared.urlInASpace(url)
    }

    override func accessibilityPerformEscape() -> Bool {
        if chromeModel.isEditingLocation {
            closeLazyTab()
            return true
        } else if let selectedTab = tabManager.selectedTab, selectedTab.canGoBack {
            selectedTab.goBack()
            return true
        }

        return false
    }

    func updateUIForReaderHomeStateForTab(_ tab: Tab) {
        updateURLBarDisplayURL(tab)

        browserModel.scrollingControlModel.showToolbars(animated: false)

        if let url = tab.url {
            updateInZeroQuery(url as URL)
        }
    }

    /// Updates the URL bar text and button states.
    /// Call this whenever the page URL changes.
    fileprivate func updateURLBarDisplayURL(_ tab: Tab) {
        locationModel.url = tab.url?.displayURL
        chromeModel.isPage = tab.url?.displayURL?.isWebPage() ?? false
        chromeModel.urlInSpace = tab.url == nil ? false : SpaceStore.shared.urlInASpace(tab.url!)
    }

    // MARK: Opening New Tabs
    func switchToTabForURLOrOpen(_ url: URL, isPrivate: Bool = false) {
        popToBVC()
        if let tab = tabManager.getTabFor(url) {
            tabManager.selectTab(tab)
        } else {
            openURLInNewTab(url, isPrivate: isPrivate)
        }
    }

    func switchToTabForWidgetURLOrOpen(_ url: URL, uuid: String, isPrivate: Bool = false) {
        popToBVC()
        if let tab = tabManager.getTabForUUID(uuid: uuid) {
            tabManager.selectTab(tab)
        } else {
            openURLInNewTab(url, isPrivate: isPrivate)
        }
    }

    func openURLInNewTab(
        _ url: URL?, isPrivate: Bool = false, query: String? = nil, visitType: VisitType? = nil
    ) {
        if let selectedTab = tabManager.selectedTab {
            screenshotHelper.takeScreenshot(selectedTab)
        }

        let request: URLRequest?
        if let url = url {
            request = URLRequest(url: url)
        } else {
            request = nil
        }

        DispatchQueue.main.async {
            self.tabManager.selectTab(
                self.tabManager.addTab(
                    request,
                    isPrivate: isPrivate,
                    query: query,
                    visitType: visitType
                )
            )

            if self.shouldPresentDBPrompt {
                self.presentDBPromptView()
            }

            self.hideCardGrid(withAnimation: false)
        }
    }

    func openURLInNewTabPreservingIncognitoState(_ url: URL) {
        self.openURLInNewTab(url, isPrivate: incognitoModel.isIncognito)
    }

    func openURLInBackground(_ url: URL, isPrivate: Bool? = nil) {
        let isIncognito = isPrivate == nil ? incognitoModel.isIncognito : isPrivate!

        let tab = self.tabManager.addTab(
            URLRequest(url: url), afterTab: tabManager.selectedTab, isPrivate: isIncognito
        )

        var toastLabelText: LocalizedStringKey

        if isIncognito {
            toastLabelText = "New Incognito Tab opened"
        } else {
            toastLabelText = "New Tab opened"
        }

        if let toastManager = self.getSceneDelegate()?.toastViewManager {
            toastManager.makeToast(
                text: toastLabelText,
                buttonText: "Switch",
                buttonAction: {
                    self.tabManager.selectTab(tab)
                }
            ).enqueue(manager: toastManager)
        }
    }

    func openBlankNewTab(isPrivate: Bool = false) {
        popToBVC()

        let newTab = tabManager.addTab(isPrivate: isPrivate)
        tabManager.select(newTab)
    }

    func openLazyTab(
        openedFrom: ZeroQueryOpenedLocation = .openTab(nil), switchToIncognitoMode: Bool? = nil
    ) {
        if let switchToIncognitoMode = switchToIncognitoMode {
            tabManager.setIncognitoMode(to: switchToIncognitoMode)
        }

        browserModel.scrollingControlModel.showToolbars(animated: true)

        showZeroQuery(openedFrom: openedFrom, isLazyTab: true)
    }

    func openSearchNewTab(isPrivate: Bool = false, _ text: String) {
        popToBVC()
        if let searchURL = SearchEngine.current.searchURLForQuery(text) {
            openURLInNewTab(searchURL, isPrivate: isPrivate)
        } else {
            // We still don't have a valid URL, so something is broken. Give up.
            print("Error handling URL entry: \"\(text)\".")
            assertionFailure("Couldn't generate search URL: \(text)")
        }
    }

    fileprivate func popToBVC() {
        if browserModel.showGrid {
            browserModel.hideWithNoAnimation()
        }

        if let introViewModel = introViewModel {
            introViewModel.dismiss {
                self.introViewModel = nil
            }
        }

        if let presentedViewController = presentedViewController {
            presentedViewController.dismiss(animated: true, completion: nil)
        } else if chromeModel.isEditingLocation {
            chromeModel.setEditingLocation(to: false)
        }

        overlayManager.hideCurrentOverlay()
    }

    func presentActivityViewController(
        _ url: URL, tab: Tab? = nil, sourceView: UIView?, sourceRect: CGRect,
        arrowDirection: UIPopoverArrowDirection
    ) {
        let helper = ShareExtensionHelper(url: url, tab: tab)

        var appActivities = [UIActivity]()

        let deferredSites = self.profile.history.isPinnedTopSite(tab?.url?.absoluteString ?? "")

        let isPinned = deferredSites.value.successValue ?? false

        if FeatureFlag[.pinToTopSites] {
            var topSitesActivity: PinToTopSitesActivity
            if isPinned == false {
                topSitesActivity = PinToTopSitesActivity(isPinned: isPinned) { [weak tab] in
                    guard let url = tab?.url?.displayURL,
                        let sql = self.profile.history as? SQLiteHistory
                    else { return }

                    sql.getSites(forURLs: [url.absoluteString]).bind { val -> Success in
                        guard let site = val.successValue?.asArray().first?.flatMap({ $0 }) else {
                            return succeed()
                        }
                        return self.profile.history.addPinnedTopSite(site)
                    }.uponQueue(.main) { result in
                        if result.isSuccess {
                            if let toastManager = self.getSceneDelegate()?.toastViewManager {
                                toastManager.makeToast(text: "Pinned To Top Sites").enqueue(
                                    manager: toastManager)
                            }
                        }
                    }
                }
            } else {
                topSitesActivity = PinToTopSitesActivity(isPinned: isPinned) { [weak tab] in
                    guard let url = tab?.url?.displayURL,
                        let sql = self.profile.history as? SQLiteHistory
                    else { return }

                    sql.getSites(forURLs: [url.absoluteString]).bind { val -> Success in
                        guard let site = val.successValue?.asArray().first?.flatMap({ $0 }) else {
                            return succeed()
                        }

                        return self.profile.history.removeFromPinnedTopSites(site)
                    }.uponQueue(.main) { result in
                        if result.isSuccess {
                            if let toastManager = self.getSceneDelegate()?.toastViewManager {
                                toastManager.makeToast(text: "Removed From Top Sites").enqueue(
                                    manager: toastManager)
                            }
                        }
                    }
                }
            }
            appActivities.append(topSitesActivity)
        }

        let controller = helper.createActivityViewController(appActivities: appActivities) {
            [weak self] completed, _ in
            guard let self = self else { return }

            // After dismissing, check to see if there were any prompts we queued up
            self.showQueuedAlertIfAvailable()

            // Usually the popover delegate would handle nil'ing out the references we have to it
            // on the BVC when displaying as a popover but the delegate method doesn't seem to be
            // invoked on iOS 10. See Bug 1297768 for additional details.
            self.displayedPopoverController = nil
            self.updateDisplayedPopoverProperties = nil
        }

        if let popoverPresentationController = controller.popoverPresentationController {
            popoverPresentationController.sourceView = sourceView
            popoverPresentationController.sourceRect = sourceRect
            popoverPresentationController.permittedArrowDirections = arrowDirection
            popoverPresentationController.delegate = self
        }

        present(controller, animated: true, completion: nil)
    }

    func postLocationChangeNotificationForTab(
        _ tab: Tab, navigation: WKNavigation? = nil, visitType: VisitType? = nil
    ) {
        let notificationCenter = NotificationCenter.default
        var info = [AnyHashable: Any]()
        info["url"] = tab.url?.displayURL
        info["title"] = tab.title ?? ""
        if let visitType = visitType?.rawValue
            ?? self.getVisitTypeForTab(tab, navigation: navigation)?.rawValue
        {
            info["visitType"] = visitType
        }
        info["isPrivate"] = incognitoModel.isIncognito
        notificationCenter.post(name: .OnLocationChange, object: self, userInfo: info)
    }

    /// Enum to represent the WebView observation or delegate that triggered calling `navigateInTab`
    enum WebViewUpdateStatus {
        case title
        case url
        case finishedNavigation
    }

    func navigateInTab(
        tab: Tab, to navigation: WKNavigation? = nil, webViewStatus: WebViewUpdateStatus
    ) {
        guard let webView = tab.webView else {
            print("Cannot navigate in tab without a webView")
            return
        }

        Defaults[.didFirstNavigation] = true

        if let url = webView.url {
            if tab === tabManager.selectedTab {
                chromeModel.isPage = tab.url?.displayURL?.isWebPage() ?? false
            }

            if !InternalURL.isValid(url: url) || url.isReaderModeURL, !url.isFileURL {
                postLocationChangeNotificationForTab(tab, navigation: navigation)

                webView.evaluateJavascriptInDefaultContentWorld(
                    "\(ReaderModeNamespace).checkReadability()")
            }

            TabEvent.post(.didChangeURL(url), for: tab)
        }

        // Represents WebView observation or delegate update that called this function
        switch webViewStatus {
        case .title, .url, .finishedNavigation:
            // Workaround for issue #1562. It's not safe to insert a WebView into a View hierarchy
            // directly from a property change event. There could be a lot of WebKit code on the
            // stack at this point.
            DispatchQueue.main.async {
                if tab !== self.tabManager.selectedTab, let webView = tab.webView {
                    // To Screenshot a tab that is hidden we must add the webView,
                    // then wait enough time for the webview to render.
                    self.view.insertSubview(webView, at: 0)

                    // This is kind of a hacky fix for Bug 1476637 to prevent webpages from focusing
                    // the touch-screen keyboard from the background even though they shouldn't be
                    // able to.
                    webView.resignFirstResponder()

                    // We need a better way of identifying when webviews are finished rendering
                    // There are cases in which the page will still show a loading animation or
                    // nothing when the screenshot is being taken, depending on internet connection
                    // Issue created: https://github.com/mozilla-mobile/firefox-ios/issues/7003
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.screenshotHelper.takeScreenshot(tab)
                        if webView.superview == self.view {
                            webView.removeFromSuperview()
                        }
                    }
                }
            }
        }
    }

    func showTabTray() {
        guard !browserModel.showGrid else { return }

        // log show tap tray
        ClientLogger.shared.logCounter(
            .ShowTabTray, attributes: EnvironmentHelper.shared.getAttributes())

        updateFindInPageVisibility(visible: false)

        if zeroQueryModel.isLazyTab {
            browserModel.showWithNoAnimation()
        } else {
            browserModel.show()
        }

        if let tab = tabManager.selectedTab {
            screenshotHelper.takeScreenshot(tab)
        }
    }

    func hideCardGrid(withAnimation: Bool) {
        if withAnimation {
            browserModel.hideWithAnimation()
        } else {
            browserModel.hideWithNoAnimation()
        }
    }

    func shareURL(url: URL, view: UIView) {
        let helper = ShareExtensionHelper(url: url, tab: nil)
        let controller = helper.createActivityViewController({ (_, _) in })
        if UIDevice.current.userInterfaceIdiom != .pad {
            controller.modalPresentationStyle = .formSheet
        } else {
            controller.popoverPresentationController?.sourceView = view
            controller.popoverPresentationController?.permittedArrowDirections = .up
        }

        self.present(controller, animated: true, completion: nil)
    }
}

// MARK: URL Bar Delegate support code
extension BrowserViewController {
    func urlBarDidEnterOverlayMode() {
        if browserModel.showGrid || tabManager.selectedTab == nil {
            openLazyTab(openedFrom: .tabTray)
        } else {
            showZeroQuery(openedFrom: .openTab(tabManager.selectedTab))
        }
    }

    func urlBarDidLeaveOverlayMode() {
        updateInZeroQuery(tabManager.selectedTab?.url as URL?)
    }
}

/// History visit management.
/// TODO: this should be expanded to track various visit types; see Bug 1166084.
extension BrowserViewController {
    func ignoreNavigationInTab(_ tab: Tab, navigation: WKNavigation) {
        self.ignoredNavigation.insert(navigation)
    }

    func recordNavigationInTab(_ tab: Tab, navigation: WKNavigation, visitType: VisitType) {
        self.typedNavigation[navigation] = visitType
    }

    /// Untrack and do the right thing.
    func getVisitTypeForTab(_ tab: Tab, navigation: WKNavigation?) -> VisitType? {
        guard let navigation = navigation else {
            // See https://github.com/WebKit/webkit/blob/master/Source/WebKit2/UIProcess/Cocoa/NavigationState.mm#L390
            return VisitType.link
        }

        if let _ = self.ignoredNavigation.remove(navigation) {
            return nil
        }

        return self.typedNavigation.removeValue(forKey: navigation) ?? VisitType.link
    }
}

extension BrowserViewController: TabDelegate {

    private func subscribe(to webView: WKWebView, for tab: Tab) {
        let updateGestureHandler = {
            if let helper = tab.getContentScript(name: ContextMenuHelper.name())
                as? ContextMenuHelper
            {
                // This is zero-cost if already installed. It needs to be checked frequently (hence every event here triggers this function), as when a new tab is created it requires multiple attempts to setup the handler correctly.
                helper.replaceGestureHandlerIfNeeded()
            }
        }

        let tabManager = tabManager

        // Observers that live as long as the tab. They are all cancelled in Tab/close(),
        // so it is safe to use a strong reference to self.

        let estimatedProgressPub = webView.publisher(for: \.estimatedProgress, options: .new)
        let isLoadingPub = webView.publisher(for: \.isLoading, options: .new)
        estimatedProgressPub.combineLatest(isLoadingPub)
            .forEach(updateGestureHandler)
            .filter { _ in tab === tabManager.selectedTab }
            .sink { [self] (estimatedProgress, isLoading) in
                // When done loading, we want to set progress to 1 so that we allow the progress
                // complete animation to happen. But we want to avoid showing incomplete progress
                // when no longer loading (as may happen when a page load is interrupted).
                if let url = webView.url, !InternalURL.isValid(url: url) {
                    if isLoading {
                        chromeModel.estimatedProgress = estimatedProgress
                    } else if estimatedProgress == 1 && chromeModel.estimatedProgress != 1 {
                        chromeModel.estimatedProgress = 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            if chromeModel.estimatedProgress == 1 {
                                chromeModel.estimatedProgress = nil
                            }
                        }
                    } else {
                        chromeModel.estimatedProgress = nil
                    }
                } else {
                    chromeModel.estimatedProgress = nil
                }
            }
            .store(in: &tab.webViewSubscriptions)

        webView.publisher(for: \.url, options: .new)
            .forEach(updateGestureHandler)
            // Special case for "about:blank" popups, if the webView.url is nil, keep the tab url as "about:blank"
            .filter { tab.url != .aboutBlank || $0 != nil }
            // To prevent spoofing, only change the URL immediately if the new URL is on
            // the same origin as the current URL. Otherwise, do nothing and wait for
            // didCommitNavigation to confirm the page load.
            .filter { tab.url?.origin == $0?.origin }
            .sink { [self] url in
                tab.setURL(url)

                if tab === tabManager.selectedTab && !tab.restoring {
                    updateUIForReaderHomeStateForTab(tab)
                }

                // Catch history pushState navigation, but ONLY for same origin navigation,
                // for reasons above about URL spoofing risk.
                navigateInTab(tab: tab, webViewStatus: .url)
            }
            .store(in: &tab.webViewSubscriptions)

        webView.publisher(for: \.title, options: .new)
            .forEach(updateGestureHandler)
            .compactMap { $0 }
            // Ensure that the tab title *actually* changed to prevent repeated calls
            // to navigateInTab(tab:).
            .filter { !$0.isEmpty && $0 != tab.lastTitle }
            .sink { [self] title in
                tab.lastTitle = title
                navigateInTab(tab: tab, webViewStatus: .title)
            }
            .store(in: &tab.webViewSubscriptions)

        webView.publisher(for: \.canGoBack, options: .new)
            .forEach(updateGestureHandler)
            .filter { _ in tab === tabManager.selectedTab }
            .assign(to: \.canGoBack, on: chromeModel)
            .store(in: &tab.webViewSubscriptions)

        webView.publisher(for: \.canGoForward, options: .new)
            .forEach(updateGestureHandler)
            .filter { _ in tab === tabManager.selectedTab }
            .assign(to: \.canGoForward, on: chromeModel)
            .store(in: &tab.webViewSubscriptions)

        webView.scrollView
            .publisher(for: \.contentSize, options: .new)
            .sink { [self] _ in
                browserModel.scrollingControlModel.contentSizeDidChange()
            }
            .store(in: &tab.webViewSubscriptions)
    }

    func tab(_ tab: Tab, didCreateWebView webView: WKWebView) {
        webView.uiDelegate = self

        self.subscribe(to: webView, for: tab)

        let formPostHelper = FormPostHelper(tab: tab)
        tab.addContentScript(formPostHelper, name: FormPostHelper.name())

        let readerMode = ReaderMode(tab: tab)
        readerMode.delegate = self
        tab.addContentScript(readerMode, name: ReaderMode.name())

        // only add the logins helper if the tab is not a private browsing tab
        if !incognitoModel.isIncognito {
            let logins = LoginsHelper(tab: tab, profile: profile)
            tab.addContentScript(logins, name: LoginsHelper.name())
        }

        let contextMenuHelper = ContextMenuHelper(tab: tab)
        contextMenuHelper.delegate = self
        tab.addContentScript(contextMenuHelper, name: ContextMenuHelper.name())

        let errorHelper = ErrorPageHelper(certStore: profile.certStore)
        tab.addContentScript(errorHelper, name: ErrorPageHelper.name())

        let sessionRestoreHelper = SessionRestoreHelper(tab: tab)
        sessionRestoreHelper.delegate = self
        tab.addContentScript(sessionRestoreHelper, name: SessionRestoreHelper.name())

        let findInPageHelper = FindInPageHelper(tab: tab)
        findInPageHelper.delegate = self
        tab.addContentScript(findInPageHelper, name: FindInPageHelper.name())

        let downloadContentScript = DownloadContentScript(tab: tab)
        tab.addContentScript(downloadContentScript, name: DownloadContentScript.name())

        let printHelper = PrintHelper(tab: tab)
        tab.addContentScript(printHelper, name: PrintHelper.name())

        tab.addContentScript(LocalRequestHelper(), name: LocalRequestHelper.name())

        let blocker = NeevaTabContentBlocker(tab: tab)
        tab.contentBlocker = blocker
        tab.addContentScript(blocker, name: NeevaTabContentBlocker.name())

        tab.addContentScript(FocusHelper(tab: tab), name: FocusHelper.name())

        let webuiMessageHelper = WebUIMessageHelper(
            tab: tab,
            webView: webView,
            tabManager: tabManager)
        tab.addContentScript(webuiMessageHelper, name: WebUIMessageHelper.name())
    }

    func tab(_ tab: Tab, didSelectAddToSpaceForSelection selection: String) {
        showAddToSpacesSheet(
            url: tab.url!,
            title: tab.displayTitle, description: selection, webView: tab.webView!)
    }

    func tab(_ tab: Tab, didSelectFindInPageForSelection selection: String) {
        updateFindInPageVisibility(visible: true, query: selection)
    }

    func tab(_ tab: Tab, didSelectSearchWithNeevaForSelection selection: String) {
        openSearchNewTab(isPrivate: incognitoModel.isIncognito, selection)
    }
}

extension BrowserViewController: HistoryPanelDelegate {
    func libraryPanel(didSelectURL url: URL, visitType: VisitType) {
        presentedViewController?.dismiss(
            animated: true,
            completion: {
                self.hideCardGrid(
                    withAnimation: self.tabManager.createOrSwitchToTab(for: url)
                        == .switchedToExistingTab)
            })
    }
}

extension BrowserViewController: ZeroQueryPanelDelegate {
    func zeroQueryPanelDidRequestToSaveToSpace(_ url: URL, title: String?, description: String?) {
        chromeModel.setEditingLocation(to: false)
        showAddToSpacesSheet(url: url, title: title, description: description)
    }

    func zeroQueryPanel(didSelectURL url: URL, visitType: VisitType) {
        if NeevaUserInfo.shared.isUserLoggedIn
            && url.absoluteString.starts(with: NeevaConstants.appSpacesURL.absoluteString)
        {
            hideZeroQuery()
            browserModel.openSpace(spaceID: url.lastPathComponent)
            return
        }
        finishEditingAndSubmit(url, visitType: visitType, forTab: tabManager.selectedTab)
    }

    func zeroQueryPanelDidRequestToOpenInNewTab(_ url: URL, isPrivate: Bool) {
        hideZeroQuery()
        openURLInBackground(url, isPrivate: isPrivate)
    }

    func zeroQueryPanel(didEnterQuery query: String) {
        searchQueryModel.value = query
        chromeModel.setEditingLocation(to: true)
    }
}

extension BrowserViewController: TabManagerDelegate {
    func tabManager(
        _ tabManager: TabManager, didSelectedTabChange selected: Tab?, previous: Tab?,
        isRestoring: Bool, updateZeroQuery: Bool
    ) {
        presentedViewController?.dismiss(animated: false, completion: nil)

        // Remove the old accessibilityLabel. Since this webview shouldn't be visible, it doesn't need it
        // and having multiple views with the same label confuses tests.
        if let wv = previous?.webView {
            wv.endEditing(true)
            wv.accessibilityLabel = nil
            wv.accessibilityElementsHidden = true
            wv.accessibilityIdentifier = nil
        }

        if let tab = selected, let webView = tab.webView {
            updateURLBarDisplayURL(tab)

            readerModeCache =
                tab.isIncognito
                ? MemoryReaderModeCache.sharedInstance : DiskReaderModeCache.sharedInstance
            ReaderModeHandlers.readerModeCache = readerModeCache

            // This is a terrible workaround for a bad iOS 12 bug where PDF
            // content disappears any time the view controller changes (i.e.
            // the user taps on the tabs tray). It seems the only way to get
            // the PDF to redraw is to either reload it or revisit it from
            // back/forward list. To try and avoid hitting the network again
            // for the same PDF, we revisit the current back/forward item and
            // restore the previous scrollview zoom scale and content offset
            // after a short 100ms delay. *facepalm*
            //
            // https://bugzilla.mozilla.org/show_bug.cgi?id=1516524
            if tab.temporaryDocument?.mimeType == MIMEType.PDF {
                let previousZoomScale = webView.scrollView.zoomScale
                let previousContentOffset = webView.scrollView.contentOffset

                if let currentItem = webView.backForwardList.currentItem {
                    webView.go(to: currentItem)
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    webView.scrollView.setZoomScale(previousZoomScale, animated: false)
                    webView.scrollView.setContentOffset(previousContentOffset, animated: false)
                }
            }

            webView.accessibilityLabel = .WebViewAccessibilityLabel
            webView.accessibilityIdentifier = "contentView"
            webView.accessibilityElementsHidden = false

            if webView.url == nil {
                // The web view can go gray if it was zombified due to memory pressure.
                // When this happens, the URL is nil, so try restoring the page upon selection.
                tab.reload()
            }
        }

        updateFindInPageVisibility(visible: false, tab: previous)
        chromeModel.canGoBack =
            (simulateBackModel.canGoBack()
                || selected?.canGoBack ?? false)
        chromeModel.canGoForward =
            (simulateForwardModel.canGoForward()
                || selected?.canGoForward ?? false)
        if let url = selected?.webView?.url, !InternalURL.isValid(url: url) {
            if selected?.isLoading ?? false {
                chromeModel.estimatedProgress = selected?.estimatedProgress
            } else {
                chromeModel.estimatedProgress = nil
            }
            chromeModel.urlInSpace = SpaceStore.shared.urlInASpace(url)
        }

        if let readerMode = selected?.getContentScript(name: ReaderMode.name()) as? ReaderMode {
            readerModeModel.setReadingModeState(state: readerMode.state)
        } else {
            readerModeModel.setReadingModeState(state: .unavailable)
        }

        if updateZeroQuery {
            updateInZeroQuery(selected?.url as URL?)
        }
    }

    func getSceneDelegate() -> SceneDelegate? {
        SceneDelegate.getCurrentSceneDelegate(for: self.view)
    }
}

// MARK: - UIPopoverPresentationControllerDelegate

extension BrowserViewController: UIPopoverPresentationControllerDelegate {
    func popoverPresentationControllerDidDismissPopover(
        _ popoverPresentationController: UIPopoverPresentationController
    ) {
        displayedPopoverController = nil
        updateDisplayedPopoverProperties = nil
    }
}

extension BrowserViewController: UIAdaptivePresentationControllerDelegate {
    // Returning None here makes sure that the Popover is actually presented as a Popover and
    // not as a full-screen modal, which is the default on compact device classes.
    func adaptivePresentationStyle(
        for controller: UIPresentationController, traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        return .none
    }
}

extension BrowserViewController {
    func presentIntroViewController(
        _ alwaysShow: Bool = false,
        signInMode: Bool = false,
        onOtherOptionsPage: Bool = false,
        marketingEmailOptOut: Bool = false,
        completion: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        if alwaysShow || !Defaults[.introSeen] {
            showProperIntroVC(
                signInMode: signInMode,
                onOtherOptionsPage: onOtherOptionsPage,
                marketingEmailOptOut: marketingEmailOptOut,
                completion: completion,
                onDismiss: onDismiss
            )
        }
    }

    // Default browser onboarding
    func presentDBOnboardingViewController(
        _ force: Bool = false,
        modalTransitionStyle: UIModalTransitionStyle? = nil,
        triggerFrom: OpenSysSettingTrigger
    ) {
        let onboardingVC = DefaultBrowserOnboardingViewController(
            didOpenSettings: { [weak self] in
                guard let self = self else { return }
                self.zeroQueryModel.updateState()
            }, triggerFrom: triggerFrom)

        onboardingVC.modalPresentationStyle = .formSheet
        if let modalTransitionStyle = modalTransitionStyle {
            onboardingVC.modalTransitionStyle = modalTransitionStyle
        }
        present(onboardingVC, animated: true, completion: nil)
    }

    private func showProperIntroVC(
        signInMode: Bool = false, onOtherOptionsPage: Bool = false,
        marketingEmailOptOut: Bool = false, completion: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        func createOrSwitchToTabFromAuth(_ url: URL) {
            if let selectedTab = self.tabManager.selectedTab,
                let _ = self.tabManager.selectedTab?.url
            {
                DispatchQueue.main.async {
                    selectedTab.loadRequest(URLRequest(url: url))
                    if self.shouldPresentDBPrompt {
                        self.presentDBPromptView()
                    }
                    self.hideCardGrid(withAnimation: false)
                }
            } else {
                openURLInNewTab(url)
            }
        }

        func setTokenAndOpenURL(token: String, url: URL) {
            NeevaUserInfo.shared.setLoginCookie(token)

            if let notificationToken = Defaults[.notificationToken] {
                NotificationPermissionHelper.shared
                    .registerDeviceTokenWithServer(deviceToken: notificationToken)
            }

            let httpCookieStore = self.tabManager.configuration.websiteDataStore.httpCookieStore
            httpCookieStore.setCookie(NeevaConstants.loginCookie(for: token)) {
                DispatchQueue.main.async {
                    createOrSwitchToTabFromAuth(url)
                }
            }
        }

        introViewModel = IntroViewModel(
            presentationController: self, overlayManager: overlayManager,
            onDismiss: { action in
                self.introViewModel?.dismiss {
                    self.introViewModel = nil

                    switch action {
                    case .signupWithApple(let marketingEmailOptOut, let serverAuthCode):
                        if let serverAuthCode = serverAuthCode {
                            let authURL = NeevaConstants.appleAuthURL(
                                serverAuthCode: serverAuthCode,
                                marketingEmailOptOut: marketingEmailOptOut ?? false,
                                signup: true)
                            let httpCookieStore = self.tabManager.configuration.websiteDataStore
                                .httpCookieStore
                            httpCookieStore.setCookie(
                                NeevaConstants.serverAuthCodeCookie(for: serverAuthCode)
                            ) {
                                self.openURLInNewTab(authURL)
                            }
                        }
                    case .skipToBrowser:
                        if let onDismiss = onDismiss {
                            onDismiss()
                        }
                    case .oktaSignin(let email):
                        createOrSwitchToTabFromAuth(NeevaConstants.oktaSigninURL(email: email))
                    case .oauthWithProvider(_, _, let token, _):
                        // loading appSearchURL to prevent showing marketing site
                        setTokenAndOpenURL(token: token, url: NeevaConstants.appSearchURL)
                    case .oktaAccountCreated(let token):
                        setTokenAndOpenURL(
                            token: token, url: NeevaConstants.verificationRequiredURL)
                    default:
                        break
                    }

                    if NeevaUserInfo.shared.hasLoginCookie() {
                        if let notificationToken = Defaults[.notificationToken] {
                            NotificationPermissionHelper.shared
                                .registerDeviceTokenWithServer(deviceToken: notificationToken)
                        }
                    }

                    if case .skipToBrowser = action {
                    } else {
                        if !Defaults[.didSetDefaultBrowser]
                            && !Defaults[.didShowDefaultBrowserInterstitial]
                        {
                            self.shouldPresentDBPrompt = true
                            self.shouldLogDBPrompt = true
                        }
                    }

                    SpaceStore.shared.refresh(force: true)
                }
            })

        introViewModel?.onSignInMode = signInMode
        introViewModel?.onOtherOptionsPage = onOtherOptionsPage
        introViewModel?.marketingEmailOptOut = marketingEmailOptOut

        overlayManager.presentFullScreenModal(
            content: AnyView(
                IntroFirstRunView()
                    .environmentObject(introViewModel!)
                    .onAppear {
                        AppDelegate.setRotationLock(to: .portrait)
                    }
                    .onDisappear {
                        AppDelegate.setRotationLock(to: .all)
                    }
            )
        ) {
            completion?()
        }
    }

    private func presentDBPromptView() {
        self.shouldPresentDBPrompt = false

        let arm = NeevaExperiment.startExperiment(for: .defaultBrowserSkipEducation)

        self.overlayManager.presentFullScreenModal(
            content: AnyView(
                DefaultBrowserPromptView {
                    self.overlayManager.hideCurrentOverlay()
                } buttonAction: {
                    self.overlayManager.hideCurrentOverlay()

                    if arm == .skipEducation {
                        UIApplication.shared.openSettings(triggerFrom: .defaultBrowserPromptDirect)
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.presentDBOnboardingViewController(
                                modalTransitionStyle: .crossDissolve,
                                triggerFrom: .defaultBrowserPrompt
                            )
                        }
                    }
                }
            )
        ) {}

        Defaults[.didShowDefaultBrowserInterstitial] = true
    }

    private func introVCPresentHelper(
        introViewController: UIViewController, completion: (() -> Void)?
    ) {
        // On iPad we present it modally in a controller
        if traitCollection.horizontalSizeClass == .regular
            && traitCollection.verticalSizeClass == .regular
        {
            introViewController.preferredContentSize = CGSize(width: 375, height: 667)
            introViewController.modalPresentationStyle = .formSheet
        } else {
            introViewController.modalPresentationStyle = .fullScreen
        }
        present(introViewController, animated: true, completion: completion)
    }
}

extension BrowserViewController: ContextMenuHelperDelegate {
    fileprivate static var contextMenuElements: ContextMenuHelper.Elements?

    func contextMenuHelper(
        _ contextMenuHelper: ContextMenuHelper,
        didLongPressElements elements: ContextMenuHelper.Elements,
        gestureRecognizer: UIGestureRecognizer
    ) {
        // locationInView can return (0, 0) when the long press is triggered in an invalid page
        // state (e.g., long pressing a link before the document changes, then releasing after a
        // different page loads).
        let touchPoint = gestureRecognizer.location(in: view)
        guard touchPoint != CGPoint.zero else { return }

        let touchSize = CGSize(width: 0, height: 16)

        let actionSheetController = AlertController(
            title: nil, message: nil, preferredStyle: .actionSheet)
        var dialogTitle: String?

        if let url = elements.link, let currentTab = tabManager.selectedTab {
            dialogTitle = url.absoluteString
            let isPrivate = incognitoModel.isIncognito
            screenshotHelper.takeDelayedScreenshot(currentTab)

            let addTab = { (rURL: URL, isPrivate: Bool) in
                self.openURLInBackground(rURL, isPrivate: isPrivate)
            }

            if !isPrivate {
                let openNewTabAction = UIAlertAction(
                    title: Strings.ContextMenuOpenInNewTab, style: .default
                ) { _ in
                    addTab(url, false)
                }
                actionSheetController.addAction(
                    openNewTabAction, accessibilityIdentifier: "linkContextMenu.openInNewTab")
            }

            let openNewPrivateTabAction = UIAlertAction(
                title: Strings.ContextMenuOpenInNewIncognitoTab, style: .default
            ) { _ in
                addTab(url, true)
            }
            actionSheetController.addAction(
                openNewPrivateTabAction,
                accessibilityIdentifier: "linkContextMenu.openInNewPrivateTab")

            let downloadAction = UIAlertAction(
                title: Strings.ContextMenuDownloadLink, style: .default
            ) { _ in
                // This checks if download is a blob, if yes, begin blob download process
                if !DownloadContentScript.requestBlobDownload(url: url, tab: currentTab) {
                    //if not a blob, set pendingDownloadWebView and load the request in the webview, which will trigger the WKWebView navigationResponse delegate function and eventually downloadHelper.open()
                    self.pendingDownloadWebView = currentTab.webView
                    let request = URLRequest(url: url)
                    currentTab.webView?.load(request)
                }
            }
            actionSheetController.addAction(
                downloadAction, accessibilityIdentifier: "linkContextMenu.download")

            let copyAction = UIAlertAction(title: Strings.ContextMenuCopyLink, style: .default) {
                _ in
                UIPasteboard.general.url = url as URL
            }
            actionSheetController.addAction(
                copyAction, accessibilityIdentifier: "linkContextMenu.copyLink")

            let shareAction = UIAlertAction(title: Strings.ContextMenuShareLink, style: .default) {
                _ in
                self.presentActivityViewController(
                    url as URL, sourceView: self.view,
                    sourceRect: CGRect(origin: touchPoint, size: touchSize), arrowDirection: .any)
            }
            actionSheetController.addAction(
                shareAction, accessibilityIdentifier: "linkContextMenu.share")
        }

        let setupPopover = { [weak self] in
            guard let self = self else { return }

            // If we're showing an arrow popup, set the anchor to the long press location.
            if let popoverPresentationController = actionSheetController
                .popoverPresentationController
            {
                popoverPresentationController.sourceView = self.view
                popoverPresentationController.sourceRect = CGRect(
                    origin: touchPoint, size: touchSize)
                popoverPresentationController.permittedArrowDirections = .any
                popoverPresentationController.delegate = self
            }
        }
        setupPopover()

        if actionSheetController.popoverPresentationController != nil {
            displayedPopoverController = actionSheetController
            updateDisplayedPopoverProperties = setupPopover
        }

        if let dialogTitle = dialogTitle {
            if let _ = dialogTitle.asURL {
                actionSheetController.title = dialogTitle.ellipsize(
                    maxLength: ActionSheetTitleMaxLength)
            } else {
                actionSheetController.title = dialogTitle
            }
        }

        let cancelAction = UIAlertAction(
            title: Strings.CancelString, style: UIAlertAction.Style.cancel, handler: nil)
        actionSheetController.addAction(cancelAction)
        self.present(actionSheetController, animated: true, completion: nil)
    }

    func contextMenuHelper(
        _ contextMenuHelper: ContextMenuHelper,
        didLongPressImage elements: ContextMenuHelper.Elements,
        gestureRecognizer: UIGestureRecognizer
    ) {
        BrowserViewController.contextMenuElements = elements
        let touchPoint = gestureRecognizer.location(in: view)
        let touchSize = CGSize(width: 0, height: 16)

        let saveImage = UIMenuItem(title: "Save Image", action: #selector(saveImage))
        let copyImage = UIMenuItem(title: "Copy Image", action: #selector(copyImage))
        let copyImageLink = UIMenuItem(title: "Copy Image Link", action: #selector(copyImageLink))
        let addToSpace = UIMenuItem(title: "Add To Space", action: #selector(addImageToSpace))
        let addToSpaceWithImage = UIMenuItem(
            title: "Add Page To Space With Image", action: #selector(addToSpaceWithImage))

        tabManager.selectedTab?.webView?.stopLoading()

        UIMenuController.shared.menuItems = [
            saveImage, copyImage, copyImageLink, addToSpace, addToSpaceWithImage,
        ]
        UIMenuController.shared.showMenu(
            from: self.view, rect: CGRect(origin: touchPoint, size: touchSize))
    }

    @objc func saveImage() {
        guard let url = BrowserViewController.contextMenuElements?.image else { return }
        BrowserViewController.contextMenuElements = nil

        self.getImageData(url) { data in
            guard let image = UIImage(data: data) else { return }
            self.writeToPhotoAlbum(image: image)
        }
    }

    @objc func copyImage() {
        guard let url = BrowserViewController.contextMenuElements?.image else { return }
        BrowserViewController.contextMenuElements = nil

        // put the actual image on the clipboard
        // do this asynchronously just in case we're in a low bandwidth situation
        let pasteboard = UIPasteboard.general
        pasteboard.url = url as URL
        let changeCount = pasteboard.changeCount
        let application = UIApplication.shared
        var taskId = UIBackgroundTaskIdentifier(rawValue: 0)
        taskId = application.beginBackgroundTask(expirationHandler: {
            application.endBackgroundTask(taskId)
        })

        makeURLSession(
            userAgent: UserAgent.getUserAgent(),
            configuration: URLSessionConfiguration.default
        ).dataTask(with: url) { (data, response, error) in
            guard let _ = validatedHTTPResponse(response, statusCode: 200..<300) else {
                application.endBackgroundTask(taskId)
                return
            }

            // Only set the image onto the pasteboard if the pasteboard hasn't changed since
            // fetching the image; otherwise, in low-bandwidth situations,
            // we might be overwriting something that the user has subsequently added.
            if changeCount == pasteboard.changeCount, let imageData = data, error == nil {
                pasteboard.addImageWithData(imageData, forURL: url)
            }

            application.endBackgroundTask(taskId)
        }.resume()
    }

    @objc func copyImageLink() {
        guard let url = BrowserViewController.contextMenuElements?.image else { return }
        BrowserViewController.contextMenuElements = nil

        UIPasteboard.general.url = url as URL
    }

    @objc func addImageToSpace() {
        guard let url = BrowserViewController.contextMenuElements?.image,
            let webView = tabManager.selectedTab?.webView
        else {
            return
        }

        showAddToSpacesSheet(
            url: url,
            title: BrowserViewController.contextMenuElements?.title, webView: webView)

        BrowserViewController.contextMenuElements = nil
    }

    @objc func addToSpaceWithImage() {
        guard let pageURL = tabManager.selectedTab?.url,
            let imageURL = BrowserViewController.contextMenuElements?.image,
            let webView = tabManager.selectedTab?.webView
        else {
            return
        }

        getImageData(imageURL) { data in
            let thumbnail = UIImage(data: data)

            self.showAddToSpacesSheet(
                url: pageURL,
                title: self.tabManager.selectedTab?.title, thumbnail: thumbnail,
                webView: webView)

            BrowserViewController.contextMenuElements = nil
        }
    }

    fileprivate func getImageData(_ url: URL, success: @escaping (Data) -> Void) {
        makeURLSession(
            userAgent: UserAgent.getUserAgent(), configuration: URLSessionConfiguration.default
        ).dataTask(with: url) { (data, response, error) in
            if let _ = validatedHTTPResponse(response, statusCode: 200..<300), let data = data {
                success(data)
            }
        }.resume()
    }

    func contextMenuHelper(
        _ contextMenuHelper: ContextMenuHelper, didCancelGestureRecognizer: UIGestureRecognizer
    ) {
        displayedPopoverController?.dismiss(animated: true) {
            self.displayedPopoverController = nil
        }
    }
}

extension BrowserViewController {
    @objc func image(
        _ image: UIImage, didFinishSavingWithError error: NSError?, contextInfo: UnsafeRawPointer
    ) {
    }
}

extension BrowserViewController: KeyboardHelperDelegate {
    func keyboardHelper(
        _ keyboardHelper: KeyboardHelper, keyboardWillShowWithState state: KeyboardState
    ) {
        keyboardState = state
        updateViewConstraints()
    }

    func keyboardHelper(
        _ keyboardHelper: KeyboardHelper, keyboardDidShowWithState state: KeyboardState
    ) {

    }

    func keyboardHelper(
        _ keyboardHelper: KeyboardHelper, keyboardWillHideWithState state: KeyboardState
    ) {
        keyboardState = nil
        updateViewConstraints()
    }

    func keyboardHelper(
        _ keyboardHelper: KeyboardHelper, keyboardDidHideWithState state: KeyboardState
    ) {

    }
}

extension BrowserViewController: SessionRestoreHelperDelegate {
    func sessionRestoreHelper(_ helper: SessionRestoreHelper, didRestoreSessionForTab tab: Tab) {
        tab.restoring = false

        if let tab = tabManager.selectedTab, tab.webView === tab.webView {
            updateUIForReaderHomeStateForTab(tab)
        }
    }
}

extension BrowserViewController: JSPromptAlertControllerDelegate {
    func promptAlertControllerDidDismiss(_ alertController: JSPromptAlertController) {
        showQueuedAlertIfAvailable()
    }
}

extension BrowserViewController {
    func showAddToSpacesSheet(
        url: URL, title: String?, description: String? = nil,
        thumbnail: UIImage? = nil, webView: WKWebView,
        importData: SpaceImportHandler? = nil
    ) {
        // TODO: Avoid needing to lookup the Tab when we already have the WebView.
        // There should be a better way to do this.
        func getTab(tabManager: TabManager, _ url: URL) -> Tab? {
            assert(Thread.isMainThread)
            return tabManager.tabs.filter({ $0.webView?.url == url }).first
        }

        // TODO: Inject this as a ContentScript to avoid the delay here.
        webView.evaluateJavaScript(SpaceImportHandler.descriptionImageScript) {
            [weak self]
            (result, error) in

            guard let self = self else { return }

            let output = result as? [[String]]

            // Look at mediaURL from page metadata and large images within the page and dedupe
            // across URLs
            var set = Set<String>()
            var thumbnailUrls = [URL]()
            if let mediaURL =
                URL(string: getTab(tabManager: self.tabManager, url)?.pageMetadata?.mediaURL ?? "")
            {
                thumbnailUrls.append(mediaURL)
                set.insert(mediaURL.absoluteString)
            }

            if let imageUrls = output?[1]
                .filter({ set.update(with: $0) == nil })
                .compactMap({ $0.asURL })
            {
                thumbnailUrls.append(contentsOf: imageUrls)
            }

            var updater: SocialInfoUpdater? = nil
            weak var model = self.gridModel.spaceCardModel

            updater = SocialInfoUpdater.from(url: url, ogInfo: output?.last, title: title ?? "") {
                range, data, id in
                if let details = model?.detailedSpace {
                    details.allDetails.replaceSubrange(
                        range, with: [SpaceEntityThumbnail(data: data, spaceID: id.id)])
                }
            }

            model?.thumbnailURLCandidates[url] = thumbnailUrls

            self.showAddToSpacesSheet(
                url: url, title: updater?.title ?? title,
                description: description ?? updater?.description ?? output?.first?.first,
                thumbnail: thumbnail,
                importData: importData, updater: updater)
        }
    }

    func showAddToSpacesSheet(
        url: URL, title: String?,
        description: String?, thumbnail: UIImage? = nil,
        importData: SpaceImportHandler? = nil,
        updater: SocialInfoUpdater? = nil
    ) {
        let title = (title ?? "").isEmpty ? url.absoluteString : title!
        let request = AddToSpaceRequest(
            title: title, description: description, url: url, thumbnail: thumbnail, updater: updater
        )

        self.showModal(
            style: .withTitle,
            headerButton: OverlayHeaderButton(
                text: "View Spaces",
                icon: .bookmarkOnBookmark,
                action: {
                    self.browserModel.showSpaces()
                    ClientLogger.shared.logCounter(
                        .ViewSpacesFromSheet,
                        attributes: EnvironmentHelper.shared.getAttributes())
                })
        ) {
            AddToSpaceOverlayContent(
                request: request,
                bvc: self, importData: importData
            )
            .environmentObject(self.chromeModel)
            .environmentObject(self.browserModel)
        } onDismiss: {
            if request.state != .initial
                && request.state != .savingToSpace
                && request.state != .savedToSpace
            {
                ToastDefaults().showToastForAddToSpaceUI(bvc: self, request: request)
            }
        }
    }
}

// MARK: - Neeva Menu Sheet (Portrait Only)
extension BrowserViewController {
    func showNeevaMenuSheet() {
        TourManager.shared.userReachedStep(tapTarget: .neevaMenu)

        updateFeedbackImage()
        showModal(
            style: .grouped,
            headerContent: {
                NeevaMenuWillMoveView()
            }
        ) { [self] in
            NeevaMenuOverlayContent(
                menuAction: perform(neevaMenuAction:),
                isIncognito: incognitoModel.isIncognito)
        }

        self.dismissVC()
    }
}

// MARK: - Cheatsheet Sheet/Popover
extension BrowserViewController {
    /// Fetch chearsheet info and present cheatsheet
    ///
    /// Cheatsheat is presented as sheet on iPhone in portrait; otherwise, it is presented as popover
    /// This is consistent with the behaviour of [showModal](x-source-tag://showModal)
    func showCheatSheetOverlay() {
        // Load cheat sheet data
        tabManager.selectedTab?.fetchCheatsheetInfo()

        // if on iphone and portrait, present as sheet
        // otherwise, present as popover
        showModal(style: .cheatsheet) { [self] in
            CheatsheetOverlayContent(
                menuAction: perform(neevaMenuAction:),
                tabManager: tabManager
            )
            .environment(\.onSigninOrJoinNeeva) {
                ClientLogger.shared.logCounter(
                    .CheatsheetErrorSigninOrJoinNeeva,
                    attributes: EnvironmentHelper.shared.getFirstRunAttributes()
                )
                overlayManager.hideCurrentOverlay()
                presentIntroViewController(
                    true,
                    onDismiss: {
                        DispatchQueue.main.async {
                            hideCardGrid(withAnimation: true)
                        }
                    }
                )
            }
        }

        self.dismissVC()
    }
}

extension UIViewController {
    @objc func dismissVC() {
        self.dismiss(animated: true, completion: nil)
    }
}

extension BrowserViewController {
    func showShareSheet(buttonView: UIView) {
        guard
            let tab = tabManager.selectedTab,
            let url = tab.url
        else { return }

        if url.isFileURL {
            share(fileURL: url, buttonView: buttonView, presentableVC: self)
        } else {
            share(tab: tab, from: buttonView, presentableVC: self)
        }
    }

    func showBackForwardList() {
        guard let backForwardList = tabManager.selectedTab?.webView?.backForwardList else {
            return
        }

        overlayManager.show(
            overlay: .backForwardList(
                BackForwardListView(
                    model: BackForwardListModel(
                        profile: profile, backForwardList: backForwardList),
                    overlayManager: overlayManager,
                    navigationClicked: { navigationListItem in
                        self.tabManager.selectedTab?.goToBackForwardListItem(navigationListItem)
                    })))
    }
}
