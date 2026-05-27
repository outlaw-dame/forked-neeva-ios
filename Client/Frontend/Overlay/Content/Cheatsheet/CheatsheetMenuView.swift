// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Combine
import Defaults
import Shared
import SwiftUI

struct ReviewURLButton: View {
    let url: URL
    @Environment(\.onOpenURL) var onOpenURL

    var body: some View {
        Button(action: { onOpenURL(url) }) {
            getHostName()
        }
    }

    @ViewBuilder
    func getHostName() -> some View {
        let host = url.baseDomain?.replacingOccurrences(of: ".com", with: "")
        let lastPath = url.lastPathComponent
            .replacingOccurrences(of: ".html", with: "")
            .replacingOccurrences(of: "-", with: " ")
        if host != nil {
            HStack {
                Text(host!).bold()
                if !lastPath.isEmpty {
                    Text("(")
                        + Text(lastPath)
                        + Text(")")
                }
            }
            .withFont(unkerned: .bodyMedium)
            .lineLimit(1)
            .background(
                RoundedRectangle(cornerRadius: 10).stroke(Color.gray, lineWidth: 1).padding(-6)
            )
            .padding(6)
            .foregroundColor(.secondaryLabel)
        }
    }
}

struct QueryButton: View {
    let query: String
    let onDismiss: (() -> Void)?

    @Environment(\.onOpenURL) var onOpenURL

    var body: some View {
        Button(action: onClick) {
            ScrollView(.horizontal) {
                HStack(alignment: .center) {
                    Label {
                        Text(query)
                            .foregroundColor(.label)
                    } icon: {
                        Symbol(decorative: .magnifyingglass)
                            .foregroundColor(.tertiaryLabel)
                    }
                }
                .padding(.vertical, 10)
            }
        }
        .withFont(unkerned: .bodyLarge)
        .lineLimit(1)
    }

    func onClick() {
        if let onDismiss = onDismiss {
            onDismiss()
        }

        if let encodedQuery = query.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed), !encodedQuery.isEmpty
        {
            ClientLogger.shared.logCounter(
                .RelatedSearchClick, attributes: EnvironmentHelper.shared.getAttributes())
            let target = URL(string: "\(NeevaConstants.appSearchURL)?q=\(encodedQuery)")!
            onOpenURL(target)
        }
    }
}

struct CheatsheetInfoView: View {
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    let buttonText: String
    let buttonAction: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading) {
                HStack(alignment: .center) {
                    Image("neeva-logo", bundle: .main)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 18, alignment: .center)
                    Text("NeevaScope")
                        .withFont(.headingXLarge)
                }
                Text(
                    "Tap on the Neeva logo to see information related to the website you're visiting."
                )
                .withFont(.bodyLarge)
                .foregroundColor(.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                Text(
                    "From related content to reviews, NeevaScope is your guide to the web!"
                )
                .withFont(.bodyLarge)
                .foregroundColor(.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            }
            Group {
                Spacer(minLength: 10)
                // hide the image on small iPhones in landscape
                if horizontalSizeClass == .regular || verticalSizeClass == .regular {
                    Image("cheatsheet", bundle: .main)
                        .resizable()
                        .scaledToFit()
                        .frame(minHeight: 115, maxHeight: 500)
                        .accessibilityHidden(true)
                        .padding(.bottom)
                } else {
                    Spacer()
                }
                Spacer(minLength: 0)
            }
            .layoutPriority(-1)
            Button(action: buttonAction) {
                HStack {
                    Spacer()
                    Text(buttonText)
                        .withFont(.labelLarge)
                    Spacer()
                }
            }
            .buttonStyle(.neeva(.primary))
        }
        .multilineTextAlignment(.leading)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
    }
}

struct CheatsheetNoResultView: View {
    var body: some View {
        VStack(alignment: .center) {
            Text("Sorry, we couldn't find any results related to your search")
                .withFont(.headingLarge)
                .foregroundColor(.label)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Text("If this persists, let us know what happened, and we'll fix it soon.")
                .withFont(.bodyLarge)
                .foregroundColor(.secondaryLabel)
            Image("question-mark", bundle: .main)
                .resizable()
                .scaledToFit()
                .frame(minHeight: 50, maxHeight: 300)
                .accessibilityHidden(true)
                .padding(.bottom)
        }
        .multilineTextAlignment(.center)
        .padding(.top, 10)
        .padding(.horizontal, 27)
    }
}

struct CheatsheetLoadingView: View {
    public var body: some View {
        VStack(alignment: .center, spacing: 36) {
            Spacer()
            NeevaScopeLoadingView()
                .aspectRatio(1, contentMode: .fit)
                .frame(height: 100)
            Text("Your NeevaScope is coming into focus...")
                .withFont(.headingLarge)
                .foregroundColor(.label)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 170)
            Spacer()
        }
    }
}

public struct CheatsheetMenuView: View {
    @Default(.seenCheatsheetIntro) var seenCheatsheetIntro: Bool
    @Default(.showTryCheatsheetPopover) var defaultShowTryCheatsheetPopover: Bool
    @Default(.cheatsheetDebugQuery) var cheatsheetDebugQuery: Bool

    @Environment(\.hideOverlay) private var hideOverlay
    @Environment(\.onOpenURL) var onOpenURL
    @EnvironmentObject private var model: CheatsheetMenuViewModel

    @State var height: CGFloat = 0

    private let menuAction: (NeevaMenuAction) -> Void

    init(menuAction: @escaping (NeevaMenuAction) -> Void) {
        self.menuAction = menuAction
    }

    public var body: some View {
        ZStack {
            // Show Cheatsheet Info if on Neeva domain page
            if NeevaConstants.isInNeevaDomain(model.currentPageURL) {
                CheatsheetInfoView(buttonText: "Got it!") {
                    ClientLogger.shared.logCounter(
                        .AckCheatsheetEducationOnSRP,
                        attributes: EnvironmentHelper.shared.getAttributes()
                    )
                    hideOverlay()
                    defaultShowTryCheatsheetPopover = !seenCheatsheetIntro
                }
            } else if !seenCheatsheetIntro {
                CheatsheetInfoView(buttonText: "Let's try it!") {
                    ClientLogger.shared.logCounter(
                        .AckCheatsheetEducationOnPage,
                        attributes: EnvironmentHelper.shared.getAttributes()
                    )
                    seenCheatsheetIntro = true
                }
            } else if model.cheatsheetDataLoading {
                CheatsheetLoadingView()
            } else if let error = model.cheatsheetDataError {
                ErrorView(error, in: self, tryAgain: model.reload)
            } else if let error = model.searchRichResultsError {
                ErrorView(error, in: self, tryAgain: model.reload)
            } else if model.cheatSheetIsEmpty {
                VStack(alignment: .center) {
                    CheatsheetNoResultView()
                        .onAppear {
                            // there are some false positives
                            ClientLogger.shared.logCounter(
                                .CheatsheetEmpty,
                                attributes: EnvironmentHelper.shared.getAttributes()
                                    + model.loggerAttributes
                            )
                        }
                    if cheatsheetDebugQuery {
                        VStack(alignment: .leading) {
                            Button(action: {
                                if let url = model.currentCheatsheetQueryAsURL {
                                    onOpenURL(url)
                                }
                            }) {
                                HStack {
                                    Text("View Query")
                                    Symbol(decorative: .arrowUpForward)
                                        .scaledToFit()
                                }
                                .foregroundColor(.label)
                            }

                            Button(action: {
                                if let string = model.currentCheatsheetQueryAsURL?.absoluteString {
                                    UIPasteboard.general.string = string
                                }
                            }) {
                                HStack(alignment: .top) {
                                    Symbol(decorative: .docOnDoc)
                                        .frame(width: 20, height: 20, alignment: .center)
                                    Text(model.currentCheatsheetQueryAsURL?.absoluteString ?? "nil")
                                        .withFont(.bodySmall)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .foregroundColor(.secondaryLabel)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            } else {
                VStack(alignment: .leading) {
                    if isRecipeAllowed() {
                        recipeView
                            .padding()
                    }

                    if let richResults = model.searchRichResults {
                        VStack(alignment: .leading) {
                            ForEach(richResults) { richResult in
                                renderRichResult(for: richResult)
                            }
                        }
                        .padding()

                    }
                    priceHistorySection
                    reviewURLSection
                    memorizedQuerySection
                }
                .onHeightOfViewChanged { height in
                    self.height = height
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: height < 200 ? 200 : height)
    }

    @ViewBuilder
    var recipeView: some View {
        if let recipe = model.cheatsheetInfo?.recipe {
            if let ingredients = recipe.ingredients, let instructions = recipe.instructions {
                if ingredients.count > 0 && instructions.count > 0 {
                    RecipeView(
                        title: recipe.title,
                        imageURL: recipe.imageURL,
                        totalTime: recipe.totalTime,
                        prepTime: recipe.prepTime,
                        ingredients: ingredients,
                        instructions: instructions,
                        yield: recipe.yield,
                        recipeRating: RecipeRating(
                            maxStars: recipe.recipeRating?.maxStars ?? 0,
                            recipeStars: recipe.recipeRating?.recipeStars ?? 0,
                            numReviews: recipe.recipeRating?.numReviews ?? 0),
                        reviews: constructReviewList(recipe: recipe),
                        faviconURL: nil,
                        currentURL: nil,
                        tabUUID: nil
                    )
                }
            }
        }
    }

    func constructReviewList(recipe: Recipe) -> [Review] {
        guard let reviewList = recipe.reviews else { return [] }
        return reviewList.map { item in
            Review(
                body: item.body,
                reviewerName: item.reviewerName,
                rating: Rating(
                    maxStars: item.rating.maxStars,
                    actualStarts: item.rating.actualStarts
                )
            )
        }
    }

    @ViewBuilder
    func renderRichResult(for richResult: SearchController.RichResult) -> some View {
        switch richResult.resultType {
        case .ProductCluster(let productCluster):
            ProductClusterList(
                products: productCluster, currentURL: model.currentPageURL?.absoluteString ?? ""
            )
        case .RecipeBlock(let recipes):
            // filter out result already showing on the current page
            RelatedRecipeList(
                recipes: recipes.filter { $0.url != model.currentPageURL },
                onDismiss: nil
            )
            .padding(.bottom, 20)
        case .RelatedSearches(let relatedSearches):
            RelatedSearchesView(relatedSearches: relatedSearches, onDismiss: nil)
        case .WebGroup(let result):
            // filter out result already showing on the current page
            WebResultList(
                webResult: result.filter { $0.actionURL != model.currentPageURL },
                currentCheatsheetQueryAsURL: model.currentCheatsheetQueryAsURL,
                showQueryString: cheatsheetDebugQuery
            )
        }
    }

    @ViewBuilder
    var reviewURLSection: some View {
        if model.cheatsheetInfo?.reviewURL?.count ?? 0 > 0 {
            VStack(alignment: .leading, spacing: 20) {
                Text("Buying Guide").withFont(.headingMedium)
                ForEach(model.cheatsheetInfo?.reviewURL ?? [], id: \.self) { review in
                    if let url = URL(string: review) {
                        ReviewURLButton(url: url)
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    var memorizedQuerySection: some View {
        if model.cheatsheetInfo?.memorizedQuery?.count ?? 0 > 0 {
            VStack(alignment: .leading, spacing: 10) {
                Text("Keep Looking").withFont(.headingXLarge)
                ForEach(model.cheatsheetInfo?.memorizedQuery?.prefix(5) ?? [], id: \.self) {
                    query in
                    QueryButton(query: query, onDismiss: nil)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    var priceHistorySection: some View {
        if let priceHistory = model.cheatsheetInfo?.priceHistory,
            !priceHistory.Max.Price.isEmpty || !priceHistory.Min.Price.isEmpty
        {
            VStack(alignment: .leading, spacing: 10) {
                Text("Price History").withFont(.headingMedium)
                if !priceHistory.Max.Price.isEmpty {
                    HStack {
                        Text("Highest: ").bold()
                        Text("$")
                            + Text(priceHistory.Max.Price)

                        if !priceHistory.Max.Date.isEmpty {
                            Text("(")
                                + Text(priceHistory.Max.Date)
                                + Text(")")
                        }
                    }
                    .foregroundColor(.hex(0xCC3300))
                    .withFont(unkerned: .bodyMedium)
                }

                if !priceHistory.Min.Price.isEmpty {
                    HStack {
                        Text("Lowest: ").bold()
                        Text("$")
                            + Text(priceHistory.Min.Price)

                        if !priceHistory.Min.Date.isEmpty {
                            Text("(")
                                + Text(priceHistory.Min.Date)
                                + Text(")")
                        }
                    }
                    .foregroundColor(.hex(0x008800))
                    .withFont(unkerned: .bodyMedium)
                }

                if !priceHistory.Average.Price.isEmpty {
                    HStack {
                        Text("Average: ").bold()
                        Text("$")
                            + Text(priceHistory.Average.Price)
                    }
                    .foregroundColor(.hex(0x555555))
                    .withFont(unkerned: .bodyMedium)
                }
            }
            .padding()
        }
    }

    func isRecipeAllowed() -> Bool {
        guard let host = model.currentPageURL?.host,
            let baseDomain = model.currentPageURL?.baseDomain
        else { return false }
        return DomainAllowList.recipeDomains[host] ?? false
            || DomainAllowList.recipeDomains[baseDomain] ?? false
    }
}

struct CheatsheetMenuView_Previews: PreviewProvider {
    static var previews: some View {
        CheatsheetMenuView(menuAction: { _ in })
    }
}
