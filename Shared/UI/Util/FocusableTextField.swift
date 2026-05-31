// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import SwiftUI
import SwiftUIIntrospect

@available(iOSApplicationExtension 15.0, *)
struct FocusableTextField: View {
    @Binding var text: String
    let isSecure: Bool = false
    let focus: Bool
    let onEditChanged: (Bool) -> Void

    @State var needsToFocus = true
    @FocusState var focusTextField: Bool

    @ViewBuilder
    var textField: some View {
        if isSecure {
            SecureField("", text: $text) {
                onEditChanged(false)
            }
            .onTapGesture {
                needsToFocus = true
                onEditChanged(true)
            }
        } else {
            TextField(
                "", text: $text,
                onEditingChanged: { editing in
                    onEditChanged(editing)

                    if editing {
                        needsToFocus = true
                    }
                }
            )
        }
    }

    var body: some View {
        textField
            .focused($focusTextField)
            .onAppear {
                if focus {
                    focusTextField = true
                }
            }
            .introspect(.textField, on: .iOS(.v18, .v26)) { textField in
                if focusTextField && needsToFocus {
                    needsToFocus = false

                    DispatchQueue.main.async {
                        textField.selectAll(nil)
                    }
                }
            }
    }
}
