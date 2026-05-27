// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Defaults
import SafariServices
import Shared
import SwiftUI

struct FirstRunHomePage: View {
    @EnvironmentObject var model: IntroViewModel
    let smallSizeScreen: CGFloat = 375.0

    var body: some View {
        GeometryReader { geom in
            VStack(spacing: 0) {
                Spacer(minLength: 17.5)

                VStack(alignment: .leading, spacing: 30) {
                    Image(decorative: "neeva-letter-only")

                    let isSmallScreen = geom.size.width < 350
                    VStack(alignment: .leading) {
                        Text("Welcome To Neeva")
                            .font(.roobert(size: isSmallScreen ? 28 : 36))
                        Text("Create your free Neeva account")
                            .font(.roobert(size: isSmallScreen ? 16 : 20))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 50)

                VStack(spacing: 25) {
                    IntroButton(
                        icon: Image(systemSymbol: .applelogo), label: "Sign up with Apple",
                        color: .black
                    ) {
                        logFirstRunSignUpWithAppleClick()
                        model.buttonAction(.signupWithApple(model.marketingEmailOptOut, nil))
                    }

                    IntroButton(icon: nil, label: "Other sign up options", color: .brand.blue) {
                        logFirstRunOtherSignupOption()
                        model.onOtherOptionsPage = true
                    }

                    TermsAndPrivacyLinks(width: geom.size.width)

                    Button(action: { model.marketingEmailOptOut.toggle() }) {
                        HStack {
                            model.marketingEmailOptOut
                                ? Symbol(decorative: .circle, size: 20)
                                    .foregroundColor(Color.tertiaryLabel)
                                : Symbol(decorative: .checkmarkCircleFill, size: 20)
                                    .foregroundColor(Color.blue)
                            Text("Send me product & privacy tips")
                                .font(.roobert(size: 13))
                                .foregroundColor(Color.ui.gray20)
                                .multilineTextAlignment(.center)
                        }
                    }
                }

                Spacer(minLength: 17.5)

                SignInButton {
                    logFirstRunSignin()
                    model.onOtherOptionsPage = true
                    model.onSignInMode = true
                }
            }
            .padding(.horizontal, 25)
            .padding(.vertical, 35)
        }
        .onAppear(perform: logImpression)
    }

    func logImpression() {
        if Defaults[.introSeen] {
            // open by clicking sign in beyond first run
            ClientLogger.shared.logCounter(
                .AuthImpression, attributes: EnvironmentHelper.shared.getFirstRunAttributes())
        } else {
            // at first run screen
            if !Defaults[.firstRunImpressionLogged] {
                ClientLogger.shared.logCounter(
                    .FirstRunImpression,
                    attributes: EnvironmentHelper.shared.getFirstRunAttributes())
                Defaults[.firstRunImpressionLogged] = true
            }
            Defaults[.firstRunSeenAndNotSignedIn] = true
        }
    }

    func logFirstRunSignUpWithAppleClick() {
        if model.onSignInMode {
            return
        }

        if Defaults[.introSeen] {
            // beyond first run screen
            ClientLogger.shared.logCounter(
                .AuthSignUpWithApple,
                attributes: EnvironmentHelper.shared.getFirstRunAttributes())
        } else {
            // first run screen
            ClientLogger.shared.logCounter(
                .FirstRunSignupWithApple,
                attributes: EnvironmentHelper.shared.getFirstRunAttributes())
        }
    }

    func logFirstRunOtherSignupOption() {
        if model.onSignInMode {
            return
        }

        if Defaults[.introSeen] {
            // beyond first run screen
            ClientLogger.shared.logCounter(
                .AuthOtherSignUpOptions,
                attributes: EnvironmentHelper.shared.getFirstRunAttributes())
        } else {
            // first run screen
            ClientLogger.shared.logCounter(
                .FirstRunOtherSignUpOptions,
                attributes: EnvironmentHelper.shared.getFirstRunAttributes())
            Defaults[.firstRunPath] = "FirstRunOtherSignUpOptions"
        }
    }

    func logFirstRunSignin() {
        if Defaults[.introSeen] {
            // beyond first run screen
            ClientLogger.shared.logCounter(
                .AuthSignin,
                attributes: EnvironmentHelper.shared.getFirstRunAttributes())
        } else {
            // first run screen
            ClientLogger.shared.logCounter(
                .FirstRunSignin,
                attributes: EnvironmentHelper.shared.getFirstRunAttributes())
            Defaults[.firstRunPath] = "FirstRunSignin"
        }
    }
}

struct IntroFirstRunView: View {
    @EnvironmentObject var model: IntroViewModel

    var body: some View {
        VStack {
            FirstRunCloseButton {
                model.buttonAction(.skipToBrowser)

                if model.onOtherOptionsPage {
                    logOtherOptionsSkipToBrowser()
                } else {
                    logFirstRunSkipToBrowser()
                }
            }.padding(.top, 24)

            Spacer()

            if model.onOtherOptionsPage {
                OtherOptionsPage()
            } else {
                FirstRunHomePage()
            }
        }.background(
            Color.brand.offwhite
                .ignoresSafeArea(.all)
        )
        .colorScheme(.light)
    }

    func logFirstRunSkipToBrowser() {
        if model.onSignInMode {
            return
        }

        if Defaults[.introSeen] {
            // beyond first run screen
            ClientLogger.shared.logCounter(
                .AuthClose,
                attributes: EnvironmentHelper.shared.getFirstRunAttributes())
        } else {
            ClientLogger.shared.logCounter(
                .FirstRunSkipToBrowser,
                attributes: EnvironmentHelper.shared.getFirstRunAttributes())
        }
    }

    func logOtherOptionsSkipToBrowser() {
        if Defaults[.introSeen] {
            // beyond first run screen
            ClientLogger.shared.logCounter(
                .AuthOptionClosePanel,
                attributes: EnvironmentHelper.shared.getFirstRunAttributes())
        } else {
            // first run screen
            ClientLogger.shared.logCounter(
                .OptionClosePanel,
                attributes: EnvironmentHelper.shared.getFirstRunAttributes())
        }
    }
}

private struct IntroButton: View {
    let icon: Image?
    let label: LocalizedStringKey
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if let icon = icon {
                    icon.font(.system(size: 20, weight: .semibold))
                }
                Spacer(minLength: 0)
                Text(label)
                    .font(.roobert(.semibold, size: 20))
                Spacer(minLength: 0)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .frame(height: 60)
            .background(Capsule().fill(color))
        }
    }
}

// This is hacky but there isn’t a better way in the current version of SwiftUI.
private struct TermsAndPrivacyLinks: View {
    let width: CGFloat  // width of screen, determines line break behavior

    var termsButton: some View {
        SafariVCLink("Terms of Service", url: NeevaConstants.appTermsURL)
    }

    var privacyButton: some View {
        SafariVCLink("Privacy Policy", url: NeevaConstants.appPrivacyURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            if width < 350 {
                Text("By creating your Neeva account you")
                    .accessibilityLabel("By creating your Neeva account you acknowledge Neeva’s")
                HStack(spacing: 0) {
                    Text("acknowledge Neeva’s ")
                        .accessibilityHidden(true)
                    termsButton
                    Text(" and")
                }
                privacyButton
            } else {
                Text("By creating your Neeva account you acknowledge")
                    .accessibilityLabel("By creating your Neeva account you acknowledge Neeva’s")
                HStack(spacing: 0) {
                    Text("Neeva’s ")
                        .accessibilityHidden(true)
                    termsButton
                    Text(" and ")
                    privacyButton
                }
            }
        }
        .font(.system(size: 13))
        .foregroundColor(.secondaryLabel)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct SafariVCLink: View {
    let title: LocalizedStringKey
    let url: URL

    private var token: Any? = nil

    @State private var modal = ModalState()

    init(_ title: LocalizedStringKey, url: URL) {
        self.title = title
        self.url = url

        // Strictly an optimization, no need for a fallback on older versions
        if #available(iOS 15.0, *) {
            token = SFSafariViewController.prewarmConnections(to: [url])
        }
    }

    var body: some View {
        Button {
            modal.present()
        } label: {
            Text(title)
                .underline()
                .foregroundColor(.secondaryLabel)
        }.modal(state: $modal) {
            Safari(url: url)
        }
    }
}

private struct Safari: ViewControllerWrapper {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.barCollapsingEnabled = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = UIColor.ui.adaptive.blue
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

struct IntroFirstRunView_Previews: PreviewProvider {
    static var previews: some View {
        IntroFirstRunView()
    }
}
