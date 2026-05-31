// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Defaults
import SwiftUIIntrospect
import SDWebImageSwiftUI
import Shared
import SwiftUI

enum ShareSpaceViewUX {
    static let Padding: CGFloat = 8
}

extension SpaceACLLevel {
    var editText: LocalizedStringKey {
        switch self {
        case .comment:
            return "Can comment"
        case .edit:
            return "Can edit"
        case .view:
            return "Can view"
        default:
            return ""
        }
    }
}

struct ShareSpaceContent: View {
    @Environment(\.hideOverlay) private var hideOverlay
    
    let space: Space
    let shareTargetView: UIView
    let fromAddToSpace: Bool
    let noteText: String

    var body: some View {
        ShareSpaceView(
            space: space,
            shareTarget: shareTargetView,
            isPresented: Binding(
                get: { true },
                set: { present in
                    if !present {
                        hideOverlay()
                    }
                }),
            compact: fromAddToSpace,
            noteText: noteText
        )
        .overlayTitle(title: "Share Space")
    }
}

struct ShareSpaceView: View {
    typealias ACL = ListSpacesQuery.Data.ListSpace.Space.Space.Acl
    let space: Space
    let shareTargetView: UIView
    let fromAddToSpace: Bool
    @Binding var isPresented: Bool

    @Default(.seenSpacesShareIntro) var seenSpacesShareIntro: Bool
    @EnvironmentObject var tabModel: TabCardModel
    @EnvironmentObject var spaceModel: SpaceCardModel
    @State var suggestedContacts: [ContactsProvider.Profile] = []
    @State var selectedProfiles: [ContactsProvider.Profile] = []
    @State var isPublic: Bool
    @State var soloACLSharePresented: Bool = false
    @State var editingName: Bool = false
    @State var emailText: String = ""
    @State var noteText: String
    @State var selectedACL = SpaceACLLevel.view
    @State var nameText: String = NeevaUserInfo.shared.displayName ?? ""

    private var profileNameToDisplay: String {
        return !nameText.isEmpty ? nameText : NeevaUserInfo.shared.displayName ?? ""
    }

    init(
        space: Space, shareTarget: UIView, isPresented: Binding<Bool>, compact: Bool = false,
        noteText: String
    ) {
        self.space = space
        self.shareTargetView = shareTarget
        self.isPublic = space.isPublic
        self._isPresented = isPresented
        self.fromAddToSpace = compact
        self.noteText = noteText
    }

    var selectedProfilesUI: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 75, maximum: 200)), count: 2)
        ) {
            ForEach(selectedProfiles, id: \.email) { profile in
                HStack {
                    Text(profile.displayName)
                        .withFont(.bodyLarge)
                        .lineLimit(1)
                        .foregroundColor(.brand.white)
                    Button {
                        let index = selectedProfiles.firstIndex {
                            $0.email == profile.email
                        }
                        selectedProfiles.remove(at: index!)
                    } label: {
                        Symbol(decorative: .xmark, style: .labelMedium)
                            .foregroundColor(.brand.white)
                            .padding(.vertical, 8)
                    }
                }.padding(.horizontal, 10)
                    .background(Color.brand.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }.padding(.vertical, 10)
    }

    var emailEntry: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !selectedProfiles.isEmpty {
                selectedProfilesUI
            }
            HStack {
                TextField(
                    "Enter email address", text: $emailText,
                    onCommit: {
                        if emailText.contains("@") {
                            selectedProfiles.append(
                                ContactsProvider.Profile(
                                    displayName: emailText, email: emailText, pictureUrl: ""))
                            emailText = ""
                        }
                    }
                )
                .autocapitalization(.none)
                .textContentType(.emailAddress)
                .withFont(unkerned: .bodyLarge)
                .lineLimit(1)
                .foregroundColor(Color.label)
                .padding(.vertical, 10)
                ACLView(selectedACL: $selectedACL).padding(10)
            }.frame(height: 22)
        }.padding(20)
            .background(Color.DefaultBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.tertiaryLabel, lineWidth: 1)
            )
            .padding(.vertical, 12)
    }

    var suggestedContactsCell: some View {
        LazyVStack(alignment: .leading) {
            ForEach(
                suggestedContacts.filter { suggested in
                    !selectedProfiles.contains(where: { $0.email == suggested.email })
                }, id: \.email
            ) { profile in
                Button(action: {
                    selectedProfiles.append(profile)
                    emailText = ""
                    suggestedContacts = []
                }) {
                    HStack {
                        ProfileView(
                            pictureURL: profile.pictureUrl, displayName: profile.displayName,
                            email: profile.email)
                        Spacer()
                    }
                }
            }.buttonStyle(.tableCell)
        }.padding(.vertical, ShareSpaceViewUX.Padding)
    }

    var currentACLList: some View {
        LazyVStack(alignment: .leading) {
            ForEach(space.acls, id: \.userId) { acl in
                HStack {
                    ProfileView(
                        pictureURL: acl.profile.pictureUrl,
                        displayName: acl.profile.displayName, email: acl.profile.email)
                    Spacer(minLength: 0)
                    Text(acl.acl.editText)
                        .withFont(.labelMedium)
                        .lineLimit(1)
                        .foregroundColor(Color.label)
                }
            }
        }.padding(.vertical, ShareSpaceViewUX.Padding)
            .padding(.horizontal, 16)
            .background(Color.DefaultBackground)
    }

    var soloShareButtonUI: some View {
        Group {
            TextField("Add a note!", text: $noteText)
                .withFont(unkerned: .bodyLarge)
                .lineLimit(3)
                .foregroundColor(Color.label)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(height: 112, alignment: .topLeading)
                .background(Color.DefaultBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.tertiaryLabel, lineWidth: 1)
                )
                .padding(.bottom, 16)
            Button(
                action: {
                    var sharedUsers = 0
                    if !selectedProfiles.isEmpty {
                        sharedUsers = selectedProfiles.count
                        spaceModel.addSoloACLs(
                            space: space, emails: selectedProfiles.map { $0.email },
                            acl: selectedACL, note: noteText)
                    } else if emailText.contains("@") {
                        sharedUsers = 1
                        spaceModel.addSoloACLs(
                            space: space, emails: [emailText],
                            acl: selectedACL, note: noteText)
                    }

                    if sharedUsers > 0,
                        let toastManager = SceneDelegate.getCurrentSceneDelegate(
                            with: tabModel.manager.scene)?.toastViewManager
                    {
                        toastManager.makeToast(
                            text: sharedUsers == 1
                                ? "Success! Space shared with 1 person"
                                : "Success! Space shared with \(sharedUsers) people"
                        )
                        .enqueue(manager: toastManager)
                    }

                    isPresented = false
                },
                label: {
                    Text("Invite")
                        .withFont(.labelLarge)
                        .frame(maxWidth: .infinity)
                        .clipShape(Capsule())
                }
            )
            .buttonStyle(.neeva(.primary))
            .padding(.bottom, 16)
        }
    }

    var soloACLShareView: some View {
        VStack(spacing: 0) {
            Button(
                action: { soloACLSharePresented.toggle() },
                label: {
                    HStack(spacing: 0) {
                        Text("Invite someone")
                            .withFont(.headingMedium)
                            .foregroundColor(.label)
                        Spacer()
                        Symbol(decorative: soloACLSharePresented ? .chevronUp : .chevronDown)
                            .foregroundColor(.label)
                    }.padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            ).buttonStyle(.tableCell)
            if soloACLSharePresented {
                emailEntry.padding(.horizontal, 16)
                if suggestedContacts.isEmpty {
                    soloShareButtonUI.padding(.horizontal, 16)
                } else {
                    suggestedContactsCell.padding(.horizontal, 16)
                }
            }
        }
    }

    var publicACLShareView: some View {
        VStack(spacing: 0) {
            if space.ACL == .owner {
                Toggle(
                    isOn: $isPublic,
                    label: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Enable shareable link")
                                .withFont(.headingMedium)
                                .foregroundColor(.label)
                            Text("Anyone with the link can view")
                                .withFont(.bodyMedium)
                                .foregroundColor(.secondaryLabel)
                        }
                    }
                ).padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            if !fromAddToSpace, space.ACL == .owner, isPublic {
                VStack(alignment: .leading, spacing: 12) {
                    Text("You'll be shown as the owner of the Space")
                        .withFont(.bodyMedium)
                        .foregroundColor(.label)
                    HStack {
                        if editingName {
                            VStack(spacing: 2) {
                                TextField(
                                    "Enter a profile name", text: $nameText,
                                    onCommit: {
                                        editingName = false
                                    }
                                )
                                .withFont(unkerned: .bodyMedium)
                                .foregroundColor(.label)
                                Color.label.frame(height: 1)
                            }
                            .introspect(.textField, on: .iOS(.v18)) { textfield in
                                textfield.becomeFirstResponder()
                            }
                        } else {
                            ProfileView(
                                pictureURL: NeevaUserInfo.shared.pictureUrl ?? "",
                                displayName: profileNameToDisplay,
                                email: "")
                        }

                        Spacer()
                        Button(
                            action: {
                                editingName.toggle()
                            },
                            label: {
                                Text(editingName ? "Update" : "Edit Name")
                                    .withFont(.bodyMedium)
                            })
                    }
                    .padding(.vertical, 19)
                    .padding(.horizontal, 12)
                    .background(Color.secondaryBackground)
                    .cornerRadius(16)
                    .onChange(of: editingName) { value in
                        if !value {
                            if nameText != NeevaUserInfo.shared.displayName {
                                let index = nameText.lastIndex(of: " ")
                                let firstName =
                                    index == nil ? nameText : String(nameText.prefix(upTo: index!))
                                let lastName =
                                    index == nil
                                    ? ""
                                    : String(
                                        nameText.dropFirst(index!.utf16Offset(in: nameText) + 1))
                                let _ =
                                    UpdateProfileRequest(firstName: firstName, lastName: lastName)
                            }
                        }
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
                .background(Color.DefaultBackground)
                .cornerRadius(16)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
            }
            if space.ACL == .owner || isPublic {
                ShareToSocialView(
                    url: fromAddToSpace ? space.urlWithAddedItem : space.url, noteText: noteText,
                    shareTarget: shareTargetView
                ) { onShared in
                    guard !isPublic else {
                        isPresented = false
                        onShared()
                        return
                    }
                    if seenSpacesShareIntro {
                        self.isPublic = true
                        isPresented = false
                        onShared()
                    } else {
                        let bvc = SceneDelegate.getBVC(with: tabModel.manager.scene)
                        bvc.showModal(
                            style: .spaces,
                            content: {
                                SpacesShareIntroOverlayContent(
                                    onDismiss: {
                                        bvc.overlayManager.hideCurrentOverlay(ofPriority: .modal)
                                        seenSpacesShareIntro = true
                                    }, onShare: {
                                        onShared()
                                        bvc.overlayManager.hideCurrentOverlay(ofPriority: .modal)

                                        seenSpacesShareIntro = true
                                        self.isPublic = true
                                    })
                            })
                    }
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 2) {
                if !soloACLSharePresented {
                    publicACLShareView
                }
                if space.ACL == .owner {
                    soloACLShareView
                }
                if !fromAddToSpace {
                    Text("Who has access")
                        .withFont(.headingSmall)
                        .foregroundColor(.label)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    currentACLList
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(
            of: emailText,
            perform: { value in
                guard !emailText.isEmpty else {
                    suggestedContacts = []
                    return
                }
                if emailText.last == " " && emailText.contains("@") {
                    let email = String(emailText.dropLast())
                    selectedProfiles.append(
                        ContactsProvider.Profile(
                            displayName: email, email: email, pictureUrl: ""))
                    emailText = ""
                    return
                }

                ContactsProvider.getContacts(for: emailText.lowercased()) { result in
                    switch result {
                    case .success(let profiles):
                        self.suggestedContacts = profiles.compactMap { $0 }
                    case .failure(let error):
                        Logger.browser.info(error.localizedDescription)
                    }
                }
            }
        )
        .onChange(of: isPublic) { value in
            spaceModel.changePublicACL(space: space, add: value)
        }
    }
}
