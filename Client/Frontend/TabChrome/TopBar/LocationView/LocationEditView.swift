// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Shared
import SwiftUI

/// The view displayed when editing the URL; containing the favicon, text input, and completion.
struct LocationEditView: View {
    @Binding var isEditing: Bool
    let onSubmit: (String) -> Void

    @EnvironmentObject private var searchQuery: SearchQueryModel
    @EnvironmentObject private var suggestionModel: SuggestionModel

    var body: some View {
        ZStack(alignment: .leading) {
            if let completion = suggestionModel.completion {
                HStack(spacing: 0) {
                    Text(searchQuery.value)
                        .foregroundColor(.clear)
                    Text(completion)
                        .padding(.vertical, 1)
                        .padding(.trailing, 3)
                        .background(Color.textSelectionHighlight.cornerRadius(2))
                        .padding(.vertical, -1)
                }
                .accessibilityHidden(true)
                .font(.system(size: 16))
            }

            // As of iOS 15, placing LocationTextField in an overlay is needed to
            // avoid issue #1814.
            Color.clear.overlay(
                LocationTextField(text: $searchQuery.value, editing: $isEditing, onSubmit: onSubmit)
            )
        }
        .padding(.trailing, 6)
    }
}

struct LocationTextField_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LocationEditView(isEditing: .constant(true), onSubmit: { _ in })
                .environmentObject(SearchQueryModel(previewValue: ""))
            LocationEditView(isEditing: .constant(true), onSubmit: { _ in })
                .environmentObject(SearchQueryModel(previewValue: "hello, world"))
            LocationEditView(isEditing: .constant(true), onSubmit: { _ in })
                .environmentObject(SearchQueryModel(previewValue: "https://apple.com"))
        }
        .environmentObject(SuggestionModel(bvc: SceneDelegate.getBVC(for: nil), previewSites: []))
        .frame(height: TabLocationViewUX.height)
        .background(Capsule().fill(Color.systemFill))
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
