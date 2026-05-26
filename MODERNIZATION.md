# Modernization roadmap

This fork inherited an Xcode 13 / Swift 5.5 / iOS 14.0+ browser baseline from the Neeva iOS project (itself a fork of Firefox for iOS). Modernization is staged incrementally so each slice stays buildable, reviewable, and testable on its own.

---

## Principles

- Build green before modernizing. A failing CI is not a safe baseline.
- One concern per PR. Don't mix dependency changes with API cleanups.
- Prefer SPM over Carthage for new work. Migrate existing packages opportunistically.
- Keep the deployment target honest. Drop iOS versions that represent <1 % of devices.

---

## Phase 0 — Build infrastructure (complete)

| PR | Branch | Description | Status |
|----|--------|-------------|--------|
| [#5](https://github.com/outlaw-dame/forked-neeva-ios/pull/5) | dev-1 | Modernization baseline docs, README refresh, retry helper | Merged |
| [#4](https://github.com/outlaw-dame/forked-neeva-ios/pull/4) | dev-2 | iOS simulator build baseline CI workflow | Merged |
| [#10](https://github.com/outlaw-dame/forked-neeva-ios/pull/10) | dev-7 | Fix Package.resolved — pin Starscream 3.1.1 to unblock build | **Open** |
| [#11](https://github.com/outlaw-dame/forked-neeva-ios/pull/11) | dev-8 | Remove vestigial Bitrise update workflow (hourly failures) | **Open** |

### Root cause of build failure (fixed in #10)

`Client.xcodeproj`'s `Package.resolved` was stale — `web3swift`, `WalletConnectSwift`,
`BigInt`, `CryptoSwift`, and `PromiseKit` were missing. Xcode resolved them fresh each
run and pulled **Starscream 4.0.4**, whose `WebSocketDelegate` API breaks `web3swift@6ebfd9a5`.

Fix: rebuilt `Package.resolved` from the workspace's resolved set with Starscream pinned
to 3.1.1 (revision `e6b65c6d`).

---

## Phase 1 — Baseline lift (in progress)

| PR | Branch | Description | Status |
|----|--------|-------------|--------|
| [#12](https://github.com/outlaw-dame/forked-neeva-ios/pull/12) | dev-9 | Deployment target iOS 16, Swift 5.9 | **Open** |

### Next: CI speed

- Add `actions/cache@v4` for Carthage (`~/Library/Caches/org.carthage.CarthageKit` + `Carthage/Build`, keyed on `Cartfile.resolved` hash)
- First run: ~45 min Carthage build. Subsequent runs: ~2–3 min restore. Net savings: ~40 min/run.

### Next: available-guard sweep

After the iOS 16 deployment target lands, scan for `if #available(iOS 15, *)` and
`if #available(iOS 16, *)` guards that can be flattened now that the minimum is 16.

---

## Phase 2 — Dependency modernization (planned)

### Carthage → SPM migration

The app uses Carthage for 9 packages. Several have good SPM equivalents and should be
migrated one package at a time. Migrate in order of impact (most-used first).

| Package | Cartfile version | SPM status | Priority |
|---------|-----------------|------------|----------|
| SnapKit | ~> 5.0 | `SnapKit/SnapKit` — SPM supported | High |
| SwiftyJSON | ~> 5.0 | `SwiftyJSON/SwiftyJSON` — SPM supported | High |
| XCGLogger | ~> 7.0 | `DaveWoodCom/XCGLogger` — SPM supported | Medium |
| Fuzi | ~> 3.0 | `cezheng/Fuzi` — SPM supported | Medium |
| SwiftKeychainWrapper | ~> 3.2 | `jrendel/SwiftKeychainWrapper` — SPM supported (also have KeychainAccess via SPM already) | Low |
| SDWebImageSwiftUI | ~> 2.0 | Already declared as SPM dep in project.pbxproj — remove from Cartfile | High |
| GCDWebServer | ~> 3.5 | No official SPM support — keep in Carthage | Keep |
| KIF | v3.8.3 | Testing framework — migrate to XCTest UI or keep | Defer |
| onepassword-app-extension | custom branch | iOS 18+ uses universal autofill — consider removing | Defer |

### Webpack 4 → Webpack 5

The user-script bundler (`npm run build`) uses Webpack 4, which requires `NODE_OPTIONS=--openssl-legacy-provider` on Node 18+.

Migration path:
1. Update `package.json`: `webpack ^5`, `webpack-cli ^5`
2. Remove unused Babel dependencies (`babel-preset-es2015`, `babel-loader` are installed but `rules: []` — dead weight)
3. Bump `@babel/preset-env` to `^7.24` or remove entirely
4. Remove `NODE_OPTIONS: --openssl-legacy-provider` from CI workflows

The `webpack.config.js` requires no changes for webpack 5 (simple concat+minify, no loaders).

---

## Phase 3 — Swift / Xcode lift (planned)

To be done **after** Phase 1 and 2 are merged and CI is stable.

1. **Xcode 15 → 16**: Test that the baseline build passes on `macos-15` runner with Xcode 16. Update CI `runs-on` target.
2. **Swift 5.9 → 6.0 (strict concurrency)**: Enable `SWIFT_STRICT_CONCURRENCY = complete` one target at a time, fix actor isolation warnings.
3. **Swift concurrency migration**: Replace PromiseKit chains with `async/await` where safe.
4. **UIKit → SwiftUI migration**: Selected views only; full migration is out of scope for now.

---

## Inherited tech debt (not blocking, document for future)

- `firefoxios-l10n` localization import scripts (`bootstrap.sh --importLocales`) clone from external repos — not tested in CI.
- `web3swift` is pinned to an archived revision (`skywinder/web3swift` is no longer maintained). Long-term replacement: `matter-labs/web3swift` which is maintained and Starscream 4.x compatible.
- `WalletConnectSwift 1.6.2` depends on Starscream 3.x. The newer `WalletConnect/WalletConnectSwift-v2` is a full rewrite that doesn't depend on Starscream at all.
- `apollo-ios 0.49.0` is many major versions behind (current: 1.x). Apollo iOS 1.0 changed its API substantially; migration is a separate project.
