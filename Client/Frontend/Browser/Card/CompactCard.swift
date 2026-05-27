// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Shared
import SwiftUI

struct CompactCard<Details>: View where Details: TabCardDetails {
    @ObservedObject var details: Details
    @Environment(\.selectionCompletion) private var selectionCompletion: () -> Void
    @Environment(\.sizeCategory) var sizeCategory
    @EnvironmentObject var incognitoModel: IncognitoModel
    @EnvironmentObject var browserModel: BrowserModel

    var animate = false
    @State private var isPressed = false
    @State var width: CGFloat = 0

    private let isTop = FeatureFlag[.topCardStrip]
    private let minimumContentWidthRequirement: CGFloat = 115
    private let squareSize = CardUX.FaviconSize + 1

    var preferredWidth: CGFloat {
        return
            details.title.size(withAttributes: [
                .font: FontStyle.labelMedium.uiFont(for: sizeCategory)
            ]).width + CardUX.CloseButtonSize + CardUX.FaviconSize + 45  // miscellaneous padding
    }

    @ViewBuilder
    var buttonContent: some View {
        HStack {
            if width <= minimumContentWidthRequirement {
                Spacer()
            }

            HStack {
                details.favicon
                    .frame(width: CardUX.FaviconSize, height: CardUX.FaviconSize)
                    .cornerRadius(CardUX.FaviconCornerRadius)
                    .padding(5)
                    .padding(.vertical, 6)

                if width > minimumContentWidthRequirement {
                    Text(details.title).withFont(.labelMedium)
                        .frame(alignment: .center)
                        .padding(.trailing, 5).padding(.vertical, 4).lineLimit(1)
                }
            }

            Spacer()

            if let image = details.closeButtonImage, width > minimumContentWidthRequirement - 15 {
                Button(action: details.onClose) {
                    Image(uiImage: image).resizable().renderingMode(.template)
                        .foregroundColor(.secondaryLabel)
                        .padding(6)
                        .frame(width: CardUX.CloseButtonSize, height: CardUX.CloseButtonSize)
                        .background(Color(UIColor.systemGray6))
                        .clipShape(Circle())
                        .padding(6)
                        .accessibilityLabel("Close \(details.title)")
                        .opacity(animate && !browserModel.showGrid ? 0 : 1)
                }
            }
        }
    }

    var card: some View {
        Button(action: {
            details.onSelect()
            selectionCompletion()
        }) {
            if details.isPinned {
                buttonContent
                    .frame(width: CardUX.FaviconSize + 12)
            } else {
                buttonContent
                    .frame(minWidth: details.isSelected ? preferredWidth : CardUX.FaviconSize + 12)
            }
        }
        .buttonStyle(.reportsPresses(to: $isPressed))
        .padding(.horizontal)
        .background(
            GeometryReader { geom in
                Color.clear
                    .useEffect(deps: geom.size.width) { _ in
                        width = geom.size.width
                    }
            }
        )
    }

    var body: some View {
        if isTop {
            card
                .background(
                    details.isSelected
                        ? Color.DefaultBackground : Color.groupedBackground)
        } else {
            card
                .background(Color.background)
                .cornerRadius(CardUX.CompactCornerRadius)
                .modifier(
                    BorderTreatment(
                        isSelected: details.isSelected,
                        thumbnailDrawsHeader: details.thumbnailDrawsHeader,
                        isIncognito: incognitoModel.isIncognito,
                        cornerRadius: CardUX.CompactCornerRadius
                    )
                )
        }
    }

    private struct ActionsModifier: ViewModifier {
        let close: (() -> Void)?

        func body(content: Content) -> some View {
            if let close = close {
                content.accessibilityAction(named: "Close", close)
            } else {
                content
            }
        }
    }
}
