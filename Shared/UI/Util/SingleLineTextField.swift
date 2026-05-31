// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import SwiftUI
import SwiftUIIntrospect

/// A custom `TextField` that matches our style — a rounded, gray background with slightly darker placeholder text than normal. We also add a clear button.
/// TODO: make this into a `TextFieldStyle` when that becomes possible
public struct SingleLineTextField<Icon: View>: View {
    private let onEditingChanged: ((Bool) -> Void)?

    let useCapsuleBackground: Bool
    let icon: Icon?
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var detailText: LocalizedStringKey?

    @State private var textFieldWidth: CGFloat = 0
    private let alwaysShowClearButton: Bool
    private var showClearButton: Bool {
        if !alwaysShowClearButton {
            // about the maximum number of characters before the textfield "scrolls"
            return
                text.size(withAttributes: [
                    .font: FontStyle.bodyMedium.uiFont(for: textFieldSizeCategory)
                ]).width > textFieldWidth - 5
        } else {
            return true
        }
    }

    let focusTextField: Bool
    @State private var focusedTextField = false
    @State private var isEditing = false

    var secureText: Bool

    @Binding var errorMessage: String

    @Environment(\.sizeCategory) var textFieldSizeCategory

    @ViewBuilder
    var textField: some View {
        if #available(iOSApplicationExtension 15.0, *) {
            FocusableTextField(
                text: $text, focus: focusTextField,
                onEditChanged: { isEditing in
                    self.isEditing = isEditing
                    onEditingChanged?(isEditing)

                    errorMessage = ""
                })
        } else {
            if secureText {
                SecureField("", text: $text) {
                    isEditing = false
                    onEditingChanged?(isEditing)
                }
                .onTapGesture {
                    isEditing = true
                    onEditingChanged?(isEditing)

                    errorMessage = ""

                    if focusTextField {
                        focusedTextField = false
                    }
                }
            } else {
                TextField(
                    "", text: $text,
                    onEditingChanged: { editing in
                        isEditing = editing
                        onEditingChanged?(editing)

                        errorMessage = ""

                        if editing && focusTextField {
                            focusedTextField = false
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    var background: some View {
        if useCapsuleBackground {
            Capsule()
        } else {
            EmptyView()
        }
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                icon.foregroundColor(.secondaryLabel)
            }

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .withFont(useCapsuleBackground ? .bodyMedium : .bodyLarge)
                            .lineLimit(1)
                            .foregroundColor(.red)
                            .accessibilityHidden(true)
                    } else {
                        Text(placeholder)
                            .withFont(useCapsuleBackground ? .bodyMedium : .bodyLarge)
                            .lineLimit(1)
                            .foregroundColor(
                                useCapsuleBackground
                                    ? .secondaryLabel : Color(UIColor.placeholderText)
                            )
                            .padding(.leading, useCapsuleBackground ? 0 : 4)
                            .accessibilityHidden(true)
                    }
                }

                textField
                    .accessibilityLabel(placeholder)
                    .withFont(unkerned: useCapsuleBackground ? .bodyMedium : .bodyLarge)
                    .introspect(.textField, on: .iOS(.v18)) { textField in
                        if #available(iOSApplicationExtension 15.0, *) {
                        } else {
                            if focusTextField && !focusedTextField {
                                focusedTextField = true

                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    textField.becomeFirstResponder()
                                    textField.selectAll(nil)
                                }
                            }
                        }
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onChange(of: geo.size.width) { _ in
                                    textFieldWidth = geo.size.width
                                }
                        }
                    )
            }

            if isEditing && !text.isEmpty && showClearButton {
                Button(action: { text = "" }) {
                    Symbol(.xmarkCircleFill, label: "Clear")
                }
                .accentColor(.tertiaryLabel)
                .padding(.horizontal, 2)
            }

            if let detailText = detailText, !showClearButton {
                Text(detailText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.1)
                    .foregroundColor(.secondaryLabel)
                    .padding(.trailing, 2)
                    .accessibilityIdentifier("Overlay_Text-Field_Detail_Text")
            }
        }
        .font(.system(size: 14))
        .padding(useCapsuleBackground ? 10 : 0)
        .padding(.leading, useCapsuleBackground ? 7 : 0)
        .frame(minHeight: 44)
        .background(background.foregroundColor(Color.tertiarySystemFill))
    }

    public init(
        useCapsuleBackground: Bool = true,
        icon: Icon,
        placeholder: LocalizedStringKey,
        text: Binding<String>,
        errorMessage: Binding<String> = .constant(""),
        alwaysShowClearButton: Bool = true,
        detailText: LocalizedStringKey? = nil,
        focusTextField: Bool = false,
        secureText: Bool = false,
        onEditingChanged: ((Bool) -> Void)? = nil
    ) {
        self.useCapsuleBackground = useCapsuleBackground
        self.icon = icon
        self.placeholder = placeholder
        self._text = text
        self._errorMessage = errorMessage
        self.detailText = detailText

        self.alwaysShowClearButton = alwaysShowClearButton
        self.focusTextField = focusTextField
        self.secureText = secureText

        self.onEditingChanged = onEditingChanged
    }
}

extension SingleLineTextField where Icon == Never {
    init(
        useCapsuleBackground: Bool = true,
        _ placeholder: LocalizedStringKey,
        text: Binding<String>,
        errorMessage: Binding<String> = .constant(""),
        alwaysShowClearButton: Bool = true,
        detailText: LocalizedStringKey? = nil,
        focusTextField: Bool = false,
        secureText: Bool = false,
        onEditingChanged: ((Bool) -> Void)? = nil
    ) {
        self.useCapsuleBackground = useCapsuleBackground
        self.icon = nil
        self.placeholder = placeholder
        self._text = text
        self._errorMessage = errorMessage
        self.detailText = detailText

        self.alwaysShowClearButton = alwaysShowClearButton
        self.focusTextField = focusTextField
        self.secureText = secureText

        self.onEditingChanged = onEditingChanged
    }
}

struct PlaceholderField_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SingleLineTextField("Placeholder", text: .constant(""))
            SingleLineTextField("Placeholder", text: .constant("Hello, world!"))
            SingleLineTextField("Placeholder", text: .constant("Hello, world!"), detailText: "Text")
            SingleLineTextField(
                icon: Symbol(decorative: .starFill), placeholder: "Placeholder", text: .constant("")
            )
            SingleLineTextField(
                icon: Symbol(decorative: .starFill), placeholder: "Placeholder",
                text: .constant("Hello, world!"))
        }.padding().previewLayout(.sizeThatFits)
    }
}
