# Modernization Roadmap

This fork inherited an Xcode 13 / Swift 5.5 / iOS 14.0+ baseline from the Neeva iOS browser.
The goal is to revive and modernize it in a staged, CI-validated approach.

---

## ✅ Completed

### Phase 0 — CI Baseline (dev-1 → dev-9)

| PR | Branch | Summary |
|----|--------|---------|
| #5  | dev-1  | Add retry utility, fix executable bits on `bootstrap.sh`/`carthage_command.sh`, add `Scripts/build-api-config.sh` |
| #10 | dev-7  | Pin Starscream 3.1.1, fix 6 Swift 5.7+ strict `if let` errors, add Carthage-cached iOS build CI |
| #11 | dev-8  | Remove vestigial Bitrise workflow + CircleCI config; port all fixes from dev-7 |
| #12 | dev-9  | Lift deployment target to **iOS 16.0**, raise `SWIFT_VERSION` to **5.9**, fix web3swift SPM pin |

Key bugs squashed in Phase 0:
- `@available` on stored property (`IntroFirstRunView.swift`)
- `if let` on non-optional types (6 files: `BuyingGuideView`, `CompactCard`, `LocationEditView`, `SpaceEntityDetail`, `CheatsheetMenuView`)
- web3swift pinned to bad commit hash `6ebfd9a5` → fixed to `e5e339b65`
- `NODE_OPTIONS=--openssl-legacy-provider` added to CI (webpack 4 + Node 18+)
- npm build skipped on Carthage cache hits (latent bug, fixed across all branches)

### Phase 1 — Dependency Modernization (dev-10 → dev-11)

| PR | Branch | Summary |
|----|--------|---------|
| #13 | dev-10 | **webpack 4 → 5**: remove babel dead deps, add `url` polyfill for `page-metadata-parser`, drop `NODE_OPTIONS` legacy-provider workaround |
| #14 | dev-11 | Bump Carthage deps: SnapKit 5.7.1, SDWebImageSwiftUI 2.2.7, SDWebImage 5.21.7, XCGLogger 7.1.5, SwiftyJSON 5.0.2, KIF v3.12.3 |

---

## 🔜 Upcoming

### Phase 2 — Carthage → SPM Migration

All current Carthage deps (except `GCDWebServer`) ship `Package.swift` and can be moved to SPM:

| Dep | Current | SPM target |
|-----|---------|------------|
| SnapKit | 5.7.1 | 5.7.1 |
| SDWebImage / SDWebImageSwiftUI | 5.21.7 / 2.2.7 | 5.21.7 / **3.x** |
| SwiftyJSON | 5.0.2 | 5.0.2 |
| XCGLogger | 7.1.5 | 7.1.5 |
| SwiftKeychainWrapper | 3.4.0 | **4.0.1** (API review needed) |
| KIF | v3.12.3 | v3.12.3 |
| GCDWebServer | 3.5.4 | keep in Carthage (no SPM) |

### Phase 3 — SPM + Apollo Upgrade

- apollo-ios: 0.49.0 → **1.x / 2.x** (significant API rewrite — requires GraphQL codegen migration)
- SQLite.swift: 0.12.2 → 0.16.0
- PromiseKit: 6.16.2 → 8.x
- CryptoSwift: 1.4.2 → 1.10.0
- Starscream: 4.0.8 (already pinned via SPM)

### Phase 4 — Language & Toolchain

- Xcode 15 → **Xcode 16** toolchain on CI
- Swift 5.9 → **Swift 6** strict concurrency (requires `Sendable` audit across browser code)
- UIKit layout code → SwiftUI where safe to migrate

### Phase 5 — Runtime Modernization

- Webpack `package-lock.json` regeneration (commit new v3 lockfile)
- `SDWebImageSwiftUI` 2.x → 3.x (SwiftUI lifecycle API changes)
- Remove deprecated `NeevaUserInfo.shared.displayName!` force-unwraps
- Audit `@MainActor` isolation in async networking code

---

## Architecture Notes

- **Two `Space` types**: `SpacesDataQueryController.Space` (comments non-optional) vs `SpaceStore.Space` (comments optional). Views use `SpaceStore.Space`.
- **web3swift**: pinned to `e5e339b65` (fixes build issue with `6ebfd9a5`).
- **`SKIP_SWIFT_FORMAT_BUILD=1`**: swift-format submodule build skipped in CI to save ~10 min.
- **Carthage caching**: key = `hashFiles('Cartfile.resolved')`. Cache miss triggers full 40-min bootstrap; hits skip it entirely. npm build runs unconditionally before the cache gate.
