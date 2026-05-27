// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import SDWebImageSwiftUI
import Shared
import SwiftUI

struct BuyingGuideItem: View {
    let guide: BuyingGuide
    let index: Int
    let total: Int
    @Environment(\.onOpenURL) var onOpenURL

    var body: some View {
        Button(action: onClick) {
            HStack {
                WebImage(url: URL(string: guide.thumbnailURL))
                    .placeholder {
                        Rectangle().foregroundColor(.gray)
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 120, alignment: .center)
                    .clipped()
                    .cornerRadius(11)

                VStack(alignment: .leading) {
                    if let reviewType = guide.reviewType {
                        Text(reviewType)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .textCase(.uppercase)
                            .font(.system(size: 11).bold())
                            .foregroundColor(
                                Color(light: .brand.variant.blue, dark: Color(hex: 0x7cabe4)))
                        Spacer()
                    }
                    Text(guide.productName)
                        .lineLimit(1)
                        .font(.system(size: 12))
                    Spacer()
                    if let reviewSummary = guide.reviewSummary {
                        Text(reviewSummary)
                            .lineLimit(2)
                            .font(.system(size: 10).italic())
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    HStack {
                        if let price = guide.price {
                            Text(price)
                                .font(.system(size: 14))
                        }
                        Spacer()
                        Text("\(index + 1) OF \(total)")
                            .font(.system(size: 11))
                    }
                }
                .foregroundColor(.label)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            .frame(width: 270, height: 125, alignment: .leading)
            .padding(8)
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Color(light: Color.ui.gray91, dark: Color(hex: 0x383b3f)), lineWidth: 1)
            )
        }
    }

    func onClick() {
        onOpenURL(guide.actionURL)
    }
}

struct BuyingGuideList: View {
    let buyingGuides: [BuyingGuide]

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(Array(buyingGuides.enumerated()), id: \.0) { index, item in
                    BuyingGuideItem(guide: item, index: index, total: buyingGuides.count)
                }
            }
        }
    }
}
