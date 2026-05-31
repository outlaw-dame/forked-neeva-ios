// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Defaults
import SwiftUIIntrospect
import Shared
import SwiftUI

struct CollapsedCardGroupView: View {
    @ObservedObject var groupDetails: TabGroupCardDetails
    let containerGeometry: GeometryProxy
    let rowIndex: Int?

    @Environment(\.aspectRatio) private var aspectRatio
    @Environment(\.cardSize) private var size
    @Environment(\.columns) private var columns
    @EnvironmentObject var browserModel: BrowserModel
    @EnvironmentObject var tabGroupCardModel: TabGroupCardModel
    @EnvironmentObject private var gridModel: GridModel

    @State private var frame = CGRect.zero

    var body: some View {
        if groupDetails.allDetails.count <= columns.count {
            // Don't make it a scroll view if the tab group can't be expanded
            ExpandedCardGroupRowView(
                groupDetails: groupDetails, containerGeometry: containerGeometry,
                range: 0..<groupDetails.allDetails.count, rowIndex: rowIndex
            )
        } else {
            VStack(spacing: 0) {
                TabGroupHeader(groupDetails: groupDetails, rowIndex: rowIndex)
                scrollView
            }
            .animation(nil)
            .transition(.fade)
            .background(
                Color.secondarySystemFill
                    .cornerRadius(
                        24,
                        corners: groupDetails.allDetails.count <= 2 || groupDetails.isExpanded
                            ? .all : .leading
                    )
            )
        }
    }

    @ViewBuilder
    private var scrollView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(
                    spacing: SingleLevelTabCardsViewUX.TabGroupCarouselTabSpacing
                ) {
                    ForEach(Array(groupDetails.allDetails.enumerated()), id: \.1.id) {
                        index, childTabDetail in
                        FittedCard(details: childTabDetail, dragToClose: false)
                            .modifier(
                                CardTransitionModifier(
                                    details: childTabDetail,
                                    containerGeometry: containerGeometry)
                            )
                            .id(childTabDetail.id)
                            .environment(\.selectionCompletion) {
                                ClientLogger.shared.logCounter(
                                    .tabInTabGroupClicked,
                                    attributes: getLogCounterAttributesForTabGroups(
                                        TabGroupRowIndex: rowIndex, selectedChildTabIndex: index,
                                        expanded: false, numTabs: groupDetails.allDetails.count))

                                browserModel.hideWithAnimation()
                            }
                    }
                }
                .padding(.horizontal, CardGridUX.GridSpacing)
                .padding(
                    .bottom, SingleLevelTabCardsViewUX.TabGroupCarouselBottomPadding
                )
            }
            .useEffect(deps: gridModel.needsScrollToSelectedTab) { _ in
                if groupDetails.allDetails.contains(where: \.isSelected) {
                    withAnimation(nil) {
                        scrollProxy.scrollTo(groupDetails.allDetails.first(where: \.isSelected)?.id)
                    }
                }
            }
            .introspect(.scrollView, on: .iOS(.v18)) { scrollView in
                // Hack: trigger SwiftUI to run this code each time an instance of this View type is
                // instantiated. This works by referencing an input parameter (groupDetails), which causes
                // SwiftUI to think that this ViewModifier needs to be evaluated again.
                let _ = groupDetails
                scrollView.clipsToBounds = false
            }
        }
    }
}

struct ExpandedCardGroupRowView: View {
    @ObservedObject var groupDetails: TabGroupCardDetails
    let containerGeometry: GeometryProxy
    var range: Range<Int>
    let rowIndex: Int?

    @Environment(\.aspectRatio) private var aspectRatio
    @Environment(\.cardSize) private var size
    @EnvironmentObject var browserModel: BrowserModel
    @EnvironmentObject var tabGroupCardModel: TabGroupCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isFirstRow(range) {
                TabGroupHeader(groupDetails: groupDetails, rowIndex: rowIndex)
            } else {
                HStack {
                    // Spacer to expand the width of the view
                    Spacer()
                }
            }
            HStack(spacing: CardGridUX.GridSpacing) {
                ForEach(Array(zip(range, groupDetails.allDetails[range])), id: \.1.id) {
                    index, childTabDetail in
                    FittedCard(details: childTabDetail)
                        .modifier(
                            CardTransitionModifier(
                                details: childTabDetail,
                                containerGeometry: containerGeometry)
                        )
                        .environment(\.selectionCompletion) {

                            ClientLogger.shared.logCounter(
                                .tabInTabGroupClicked,
                                attributes: getLogCounterAttributesForTabGroups(
                                    TabGroupRowIndex: rowIndex, selectedChildTabIndex: index + 1,
                                    expanded: true, numTabs: groupDetails.allDetails.count))
                            browserModel.hideWithAnimation()
                        }
                }
                if isLastRowSingleTab(range, groupDetails) {
                    Spacer()
                }
            }
            .zIndex(groupDetails.allDetails[range].contains(where: \.isSelected) ? 1 : 0)
            .padding(
                .bottom, SingleLevelTabCardsViewUX.TabGroupCarouselBottomPadding
            )
            .padding(.leading, CardGridUX.GridSpacing)
        }
        .animation(nil)
        .transition(.fade)
        .background(
            Color.secondarySystemFill
                .cornerRadius(
                    isFirstRow(range) ? 24 : 0,
                    corners: .top
                )
                .cornerRadius(
                    isLastRow(range, groupDetails) ? 24 : 0,
                    corners: .bottom
                )
        )
    }

    func isLastRow(_ rowInfo: Range<Int>, _ groupDetails: TabGroupCardDetails) -> Bool {
        return rowInfo.last == groupDetails.allDetails.count - 1
    }

    func isLastRowSingleTab(_ rowInfo: Range<Int>, _ groupDetails: TabGroupCardDetails) -> Bool {
        return rowInfo.last == groupDetails.allDetails.count - 1
            && groupDetails.allDetails.count % 2 == 1
    }

    func isFirstRow(_ rowInfo: Range<Int>) -> Bool {
        return rowInfo.first == 0
    }
}

struct TabGroupHeader: View {
    @ObservedObject var groupDetails: TabGroupCardDetails
    @EnvironmentObject var tabGroupCardModel: TabGroupCardModel
    @Environment(\.columns) private var columns
    let rowIndex: Int?

    @State private var renaming = false
    @State private var deleting = false {
        didSet {
            if deleting {
                guard Defaults[.confirmCloseAllTabs] else {
                    groupDetails.onClose()
                    deleting = false
                    return
                }
            }
        }
    }

    var groupFromSpace: Bool {
        return groupDetails.id
            == tabGroupCardModel.manager.get(for: groupDetails.id)?.children.first?.parentSpaceID
    }

    var body: some View {
        HStack {
            Menu {
                if let title = groupDetails.customTitle {
                    Text("\(groupDetails.allDetails.count) tabs from “\(title)”")
                } else {
                    Text("\(groupDetails.allDetails.count) Tabs")
                }

                Button(action: {
                    ClientLogger.shared.logCounter(.tabGroupRenameThroughThreeDotMenu)
                    renaming = true
                }) {
                    Label("Rename", systemSymbol: .pencil)
                }

                if #available(iOS 15.0, *) {
                    Button(
                        role: .destructive,
                        action: {
                            ClientLogger.shared.logCounter(.tabGroupDeleteThroughThreeDotMenu)
                            deleting = true
                        }
                    ) {
                        Label("Close All", systemSymbol: .trash)
                    }
                } else {
                    Button(action: {
                        ClientLogger.shared.logCounter(.tabGroupDeleteThroughThreeDotMenu)
                        deleting = true
                    }) {
                        Label("Close All", systemSymbol: .trash)
                    }
                }
            } label: {
                Label("ellipsis", systemImage: "ellipsis")
                    .foregroundColor(.label)
                    .labelStyle(.iconOnly)
                    .frame(height: 44)
            }
            Text(groupDetails.title)
                .withFont(.labelLarge)
                .foregroundColor(.label)
            Spacer()
            if groupDetails.allDetails.count > columns.count {
                Button {
                    if groupDetails.isExpanded {
                        ClientLogger.shared.logCounter(
                            .tabGroupCollapsed,
                            attributes: getLogCounterAttributesForTabGroups(
                                TabGroupRowIndex: rowIndex, selectedChildTabIndex: nil,
                                expanded: nil, numTabs: groupDetails.allDetails.count))
                    } else {
                        ClientLogger.shared.logCounter(
                            .tabGroupExpanded,
                            attributes: getLogCounterAttributesForTabGroups(
                                TabGroupRowIndex: rowIndex, selectedChildTabIndex: nil,
                                expanded: nil, numTabs: groupDetails.allDetails.count))
                    }
                    groupDetails.isExpanded.toggle()
                } label: {
                    Label(
                        "arrows",
                        systemImage: groupDetails.isExpanded
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right"
                    )
                    .foregroundColor(.label)
                    .labelStyle(.iconOnly)
                    .padding()
                }.accessibilityHidden(true)
            }
        }
        .padding(.leading, CardGridUX.GridSpacing)
        .frame(height: SingleLevelTabCardsViewUX.TabGroupCarouselTitleSize)
        // the top and bottom paddings applied below are to make the tap target
        // of the context menu taller
        .padding(.top, SingleLevelTabCardsViewUX.TabGroupCarouselTopPadding)
        .padding(.bottom, SingleLevelTabCardsViewUX.TabGroupCarouselTitleSpacing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tab Group, \(groupDetails.title)")
        .accessibilityAddTraits([.isHeader, .isButton])
        .accessibilityValue(groupDetails.isShowingDetails ? "Expanded" : "Collapsed")
        .accessibilityAction {
            groupDetails.isShowingDetails.toggle()
        }
        .contentShape(Rectangle())
        .contextMenu {
            if let title = groupDetails.customTitle {
                Text("\(groupDetails.allDetails.count) tabs from “\(title)”")
            } else {
                Text("\(groupDetails.allDetails.count) Tabs")
            }

            Button(action: {
                ClientLogger.shared.logCounter(.tabGroupRemaneThroughLongPressMenu)
                renaming = true
            }) {
                Label("Rename", systemSymbol: .pencil)
            }

            if #available(iOS 15.0, *) {
                Button(
                    role: .destructive,
                    action: {
                        ClientLogger.shared.logCounter(.tabGroupDeleteThroughLongPressMenu)
                        deleting = true
                    }
                ) {
                    Label("Close All", systemSymbol: .trash)
                }
            } else {
                Button(action: {
                    ClientLogger.shared.logCounter(.tabGroupDeleteThroughLongPressMenu)
                    deleting = true
                }) {
                    Label("Close All", systemSymbol: .trash)
                }
            }
        }
        .textFieldAlert(
            isPresented: $renaming, title: "Rename “\(groupDetails.title)”", required: false
        ) { newName in
            if newName.isEmpty {
                groupDetails.customTitle = nil
            } else {
                groupDetails.customTitle = newName
            }
        } configureTextField: { tf in
            tf.clearButtonMode = .always
            tf.placeholder = groupDetails.defaultTitle ?? ""
            tf.text = groupDetails.customTitle
            tf.autocapitalizationType = .words
        }
        .actionSheet(isPresented: $deleting) {
            let buttons: [ActionSheet.Button] = [
                .destructive(Text("Close All")) {
                    groupDetails.onClose(showToast: false)
                },
                .cancel(),
            ]

            if let title = groupDetails.customTitle {
                return ActionSheet(
                    title: Text("Close all \(groupDetails.allDetails.count) tabs from “\(title)”?"),
                    buttons: buttons)
            } else {
                return ActionSheet(
                    title: Text("Close these \(groupDetails.allDetails.count) tabs?"),
                    buttons: buttons)
            }
        }
    }
}

func getLogCounterAttributesForTabGroups(
    TabGroupRowIndex: Int?, selectedChildTabIndex: Int?, expanded: Bool?, numTabs: Int
) -> [ClientLogCounterAttribute] {
    var attributes = EnvironmentHelper.shared.getAttributes()

    attributes.append(
        ClientLogCounterAttribute(
            key: LogConfig.TabGroupAttribute.TabGroupRowIndex, value: String(TabGroupRowIndex ?? -1)
        )
    )

    attributes.append(
        ClientLogCounterAttribute(
            key: LogConfig.TabGroupAttribute.selectedChildTabIndex,
            value: String(selectedChildTabIndex ?? -1)

        )
    )
    if let expanded = expanded {
        attributes.append(
            ClientLogCounterAttribute(
                key: LogConfig.TabGroupAttribute.isExpanded, value: String(expanded))
        )
    }

    attributes.append(
        ClientLogCounterAttribute(
            key: LogConfig.TabGroupAttribute.numTabsInTabGroup, value: String(numTabs))
    )
    return attributes
}
