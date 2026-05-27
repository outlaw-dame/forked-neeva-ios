// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Inspired by SwiftUIRefresh:
// https://github.com/siteline/SwiftUIRefresh/blob/fa8fac7b5eb5c729983a8bef65f094b5e0d12014/Sources/PullToRefresh.swift

import Apollo
import Combine
import SwiftUIIntrospect
import Shared
import SwiftUI

extension View {
    /// Add a refresh control to the nearest `List`.
    /// - Parameter controller: the `QueryController` to refresh when the refresh control is activated
    func refreshControl<Query, Data>(refreshing controller: QueryController<Query, Data>)
        -> some View
    {
        StorageView(content: self, controller: controller)
    }
}

private let refreshActionID = UIAction.Identifier("co.neeva.refreshControl.action")

private struct StorageView<Content: View, Query: GraphQLQuery, Data>: View {
    let content: Content
    let controller: QueryController<Query, Data>

    @State var storage: Set<AnyCancellable> = []
    var body: some View {
        // NB: this should be fairly easy to convert to work with scroll views as well, we just need
        //     to specify at the call site which type of view we're looking for.
        content.introspect(.list, on: .iOS(.v18)) { collectionView in
            if collectionView.refreshControl == nil {
                collectionView.refreshControl = UIRefreshControl()
                collectionView.refreshControl!.addAction(
                    UIAction(title: "Refresh", identifier: refreshActionID) { _ in
                        collectionView.refreshControl!.beginRefreshing()
                        controller.reload()
                    }, for: .valueChanged)

                controller.$state
                    .receive(on: RunLoop.main)
                    .sink { state in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            if let rc = collectionView.refreshControl,
                                rc.isRefreshing != state.isRunning
                            {
                                if state.isRunning {
                                    rc.beginRefreshing()
                                } else {
                                    rc.endRefreshing()
                                }
                            }
                        }
                    }.store(in: &storage)
            }
        }
    }
}
