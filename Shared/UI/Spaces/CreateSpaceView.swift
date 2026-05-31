// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import SwiftUI

private struct SaveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Capsule()
            .fill(configuration.isPressed ? Color(hex: 0x3254CE) : Color.ui.adaptive.blue)
            .frame(height: 44)
            .overlay(
                configuration.label
                    .foregroundColor(.white)
            )
    }
}

public struct CreateSpaceView: View {
    @State private var spaceName = ""
    let onDismiss: (String) -> Void

    public init(onDismiss: @escaping (String) -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 20) {
            SingleLineTextField("Space name", text: $spaceName, focusTextField: true)

            Button(action: {
                self.onDismiss(self.spaceName)
            }) {
                Text("Save").fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(SaveButtonStyle())
            .padding(.bottom, 11)
        }.padding(16)
    }
}
struct CreateSpaceView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CreateSpaceView(onDismiss: { _ in })
            CreateSpaceView(onDismiss: { _ in })
                .preferredColorScheme(.dark)
        }.previewLayout(.sizeThatFits)
    }
}
