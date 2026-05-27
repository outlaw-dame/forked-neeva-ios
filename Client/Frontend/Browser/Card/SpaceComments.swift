// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import SDWebImageSwiftUI
import Shared
import SwiftUI

class SpaceCommentsModel: ObservableObject {
    @Published var addedComments: [SpaceCommentData] = []
    @Published var commentAdded: String = ""
    @Published var addingComment: Bool = false {
        didSet {
            if !addingComment && !commentAdded.isEmpty {
                let originalDateFormatter = DateFormatter()
                originalDateFormatter.locale = Locale(
                    identifier: "en_US_POSIX")
                originalDateFormatter.dateFormat =
                    "yyyy-MM-dd'T'HH:mm:ssZ"
                let convertedDate = originalDateFormatter.string(
                    from: Date())
                addedComments.append(
                    SpaceCommentData(
                        id: UUID().uuidString,
                        profile: SpaceCommentData.Profile(
                            displayName: NeevaUserInfo.shared
                                .displayName!,
                            pictureUrl: NeevaUserInfo.shared.pictureUrl
                                ?? ""),
                        createdTs: convertedDate, comment: commentAdded)
                )

                addCommentRequest(commentAdded)
                commentAdded = ""
            }
        }
    }
    var addCommentRequest: ((String) -> Void)!
}

struct SpaceCommentsView: View {
    @ObservedObject var model: SpaceCommentsModel
    let space: Space

    init(space: Space, model: SpaceCommentsModel) {
        self.space = space
        self.model = model
        self.model.addCommentRequest = self.addCommentRequest
    }

    func addCommentRequest(commentAdded: String) {
        _ = AddSpaceCommentRequest(
            spaceID: space.id.id, comment: commentAdded)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Comments")
                    .withFont(.headingSmall)
                    .foregroundColor(.label)
                Spacer()
                Button(action: {
                    model.addingComment = true
                }) {
                    Text("Add")
                        .withFont(.bodyMedium)
                        .foregroundColor(.ui.adaptive.blue)
                }
            }
            if let comments = space.comments {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(comments, id: \.id) { comment in
                            CommentView(comment: comment)
                        }
                        ForEach(model.addedComments, id: \.id) { comment in
                            CommentView(comment: comment)
                        }
                        if model.addingComment {
                            AddCommentView(
                                commentText: $model.commentAdded,
                                editing: $model.addingComment
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.secondaryBackground)
    }
}

struct AddCommentView: View {
    @Binding var commentText: String
    @Binding var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                CompactProfileView(
                    pictureURL: NeevaUserInfo.shared.pictureUrl ?? "",
                    displayName: NeevaUserInfo.shared.displayName!)
                Text("Now")
                    .withFont(.bodySmall)
                    .foregroundColor(.secondaryLabel)
                Spacer()
            }
            TextField(
                "What's on your mind?", text: $commentText,
                onCommit: {
                    editing = false
                }
            )
            .withFont(unkerned: .bodyMedium)
            .foregroundColor(.label)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.quaternarySystemFill)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity)
        .introspectTextField { textField in
            textField.becomeFirstResponder()
        }
    }
}

struct CommentView: View {
    let comment: SpaceCommentData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                CompactProfileView(
                    pictureURL: comment.profile.pictureUrl,
                    displayName: comment.profile.displayName)
                Text(comment.formattedRelativeTime)
                    .withFont(.bodySmall)
                    .foregroundColor(.secondaryLabel)
                Spacer()
            }
            Text(comment.comment)
                .withFont(.bodyMedium)
                .foregroundColor(.label)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.quaternarySystemFill)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity)
    }
}

struct CompactProfileView: View {
    let pictureURL: String
    let displayName: String

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let pictureUrl = URL(string: pictureURL) {
                    WebImage(url: pictureUrl).resizable()
                } else {
                    let name = (displayName).prefix(2).uppercased()
                    Color.brand.blue
                        .overlay(
                            Text(name)
                                .accessibilityHidden(true)
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                        )
                }
            }
            .clipShape(Circle())
            .aspectRatio(contentMode: .fill)
            .frame(width: 20, height: 20)
            Text(displayName)
                .withFont(.bodyMedium)
                .lineLimit(1)
                .foregroundColor(Color.label)
        }
    }
}
