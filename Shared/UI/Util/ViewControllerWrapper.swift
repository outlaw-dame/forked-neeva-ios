// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import SwiftUIIntrospect
import SwiftUI

/// # Why do we need `ViewControllerWrapper`?
///
/// SwiftUI allows you to use `UIViewControllerRepresentable` to embed an arbitrary subclass of `UIViewController`
/// in a SwiftUI view hierarchy. However, this is suboptimal when used with a modifier like `sheet(isPresented:)` for a couple of reasons:
/// 1. SwiftUI will size the view controller to keep it inside the safe area, which we don’t actually want since the view controllers are
///   perfectly capable of handling that themselves. This also leaves blank space at the bottom of the screen, which looks bad.
/// 2. The presented view controller doesn’t know that it’s being modally presented. This means that some things won’t work properly,
///   such as swiping down to dismiss an `INUIEditVoiceShortcutViewController`.
///
/// To solve these problems, we use a little magic to directly present the view controller on top of the current `UIViewController`.

// this is used to obscure the current presentation status from other code
// since we don’t have a way to know whether the modal has been manually dismissed
public struct ModalState {
    public init() {}

    /// Present the view controller if it is not already presented
    public mutating func present() { desiredAction = .present }
    /// Dismiss the view controller if it is presented.
    public mutating func dismiss() { desiredAction = .dismiss }

    fileprivate var desiredAction: DesiredAction?
    fileprivate enum DesiredAction {
        case present
        case dismiss
    }
}

extension View {
    /// Usage:
    /// ```
    /// @State var modal = ModalState()
    ///
    /// Button("...") { modal.present() }
    ///     .modal(state: $modal) {
    ///         MyViewControllerWrapper(...)
    ///     }
    /// ```
    public func modal<Content: ViewControllerWrapper>(
        state: Binding<ModalState>, content: () -> Content
    ) -> some View {
        overlay(ViewControllerWrapper_Presenter(state: state, wrapper: content()))
    }
}

/// This is designed to be compatible with `UIViewControllerRepresentable`.
/// You can implement this protocol’s methods in the same way as you would with that protocol.
/// We need this protocol because we don’t have access to `UIViewControllerRepresentableContext`’s initializers
/// and because we don’t have access to `transaction` and `environment`.
public protocol ViewControllerWrapper {
    associatedtype ViewController: UIViewController
    associatedtype Coordinator = Void

    typealias Context = ViewControllerWrapperContext<Self>
    func makeUIViewController(context: Context) -> ViewController
    func updateUIViewController(_ vc: ViewController, context: Context)

    /// Optional.
    static func dismantleUIViewController(_ vc: ViewController, coordinator: Coordinator)
    /// Optional.
    func makeCoordinator() -> Coordinator
}
extension ViewControllerWrapper {
    public static func dismantleUIViewController(_ vc: ViewController, coordinator: Coordinator) {}
}
extension ViewControllerWrapper where Coordinator == Void {
    public func makeCoordinator() {}
}

/// This is designed to match `UIViewRepresentableContext`, although it is currently missing `transaction` and
/// `environment` for technical reasons. Specifically, `transaction` and `environment` are only provided to
/// `UI{View,ViewController}Representable` instances. Since we don’t have direct access to these at the time
/// we run the relevant functions on the `ViewControllerWrapper` instance, we can’t be sure we’re supplying up-to-date values.
public struct ViewControllerWrapperContext<Wrapper: ViewControllerWrapper> {
    public let coordinator: Wrapper.Coordinator
    // currently unimplemented:
    // public let transaction: Transaction
    // public let environment: EnvironmentValues
}

// MARK: - Internals


/// The SwiftUI view that handles the actual present/dismiss logic
public struct ViewControllerWrapper_Presenter<Wrapper: ViewControllerWrapper>: View {
    @Binding var state: ModalState
    let wrapper: Wrapper

    /// `@State` is used instead of `@StateObject` because we never update the class,
    /// instead always updating its identity when changing presented view controllers.
    @State private var presentee: Presentee?

    /// This class stores the presented view controller and the coordinator, and takes
    /// care of dismantling + dismissing the view controller when the `.modal` modifier
    /// is removed from the view hierarchy, or when `modal.dismiss()` called.
    /// It has to be a `class` because `deinit` only works on classes.
    private class Presentee {
        let vc: Wrapper.ViewController
        let coordinator: Wrapper.Coordinator

        init(from wrapper: Wrapper, in parent: UIViewController) {
            coordinator = wrapper.makeCoordinator()
            vc = wrapper.makeUIViewController(context: .init(coordinator: coordinator))
            parent.present(vc, animated: true, completion: nil)
        }

        func update(using wrapper: Wrapper) {
            wrapper.updateUIViewController(vc, context: .init(coordinator: coordinator))
        }

        /// Dismiss the view controller
        deinit {
            // captures the two members to keep them alive until the VC is dismissed
            vc.presentingViewController?.dismiss(animated: true) { [vc, coordinator] in
                Wrapper.dismantleUIViewController(vc, coordinator: coordinator)
            }
        }
    }

    public var body: some View {
        // Reference `state` in the view body to make sure this view gets re-rendered whenever the state changes
        let _ = state
        // use introspect(.viewController) to find the nearest ancestor UIViewController;
        // the old selector-based API is gone in SwiftUI-Introspect 1.x
        return EmptyView().frame(width: 0, height: 0)
            .introspect(.viewController, on: .iOS(.v18), scope: .ancestor) { vc in
            if let presentee = presentee {
                presentee.update(using: wrapper)

                if state.desiredAction == .dismiss {
                    self.presentee = nil
                    state.desiredAction = nil
                } else if presentee.vc.presentingViewController == nil {
                    // if this view has been re-rendered after the view controller was manually dismissed, set `presentee` to nil.
                    self.presentee = nil
                }
            }

            if state.desiredAction == .present && self.presentee == nil {
                self.presentee = Presentee(from: wrapper, in: vc)
                // reset the state to `nil` so that this code will be run if the view controller
                // is manually dismissed (which we don’t detect), then `state` is set to `.present`.
                state.desiredAction = nil
            }
        }
    }
}
