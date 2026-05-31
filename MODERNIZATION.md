# Modernization Roadmap

This fork inherited an Xcode 13 / Swift 5.5 / iOS 14.0+ baseline from the Neeva iOS browser.
The goal is to revive and modernize it in a staged, CI-validated approach.

---

## ✅ Completed

### Phase 0 — CI Baseline (dev-1 → dev-9)

| PR | Branch | Summary |
|----|--------|---------|
| #5  | dev-1  | Add retry utility, fix executable bits on `bootstrap.sh`/`carthage_command.sh`, fix `Scripts/build-api-config.sh` |
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

### Phase 2 — Toolchain + SPM Modernization (dev-12 → dev-13)

| PR | Branch | Summary |
|----|--------|---------|
| #15 | dev-12 | **Xcode 16.4 + iOS 18.0** deployment target; web3swift secp256k1 Xcode 16.4 fix (fork → outlaw-dame/web3swift@xcode16-compat); SFSafeSymbols 2.1.3 → **7.0.0** (org transfer + SF Symbols 7 support) |
| #16 | dev-13 | **SwiftUI-Introspect 0.1.3 → 1.3.0** — migrate 9 files to `.introspect()` new API; PullToRefresh updated for iOS 16+ `UICollectionView`-backed List |

Key changes in Phase 2:
- CI now runs on `macos-15` (has Xcode 16.4 default AND Xcode 26.x available)
- web3swift secp256k1 C code: `(uint)` → `(unsigned int)` cast fix (ISO C99) for Xcode 16.4 / iOS 18 SDK
- `SwiftUI-Introspect` product renamed `Introspect` → `SwiftUIIntrospect` in 1.x
- iOS 16+ `List` is `UICollectionView`-backed — `introspectTableView` → `introspect(.list, ...)`
- SFSafeSymbols repo transferred `piknotech` → `SFSafeSymbols` org; version numbers track SF Symbols versions (no API breaks)

---

## 🔜 Upcoming

### Phase 3 — CryptoWallet Async/Await Migration

The CryptoWallet feature (`Client/Frontend/CryptoWallet/`) currently uses PromiseKit-style web3swift APIs
(`getBalancePromise()`, `callPromise()`, `estimateGasPromise()`, etc.) which were removed in the
skywinder/web3swift mainline (replaced with `async throws` equivalents).

The current fork `outlaw-dame/web3swift@xcode16-compat` preserves the old API. A full migration to
the modern web3swift async/await API is needed to unpin from the fork.

**Migration targets per file:**

| File | PromiseKit usage | New API |
|------|-----------------|---------|
| `WalletAccessor.swift` | `.getBalancePromise().done { }`, `.callPromise()`, `.getGasPricePromise()`, `.estimateGasPromise()` | `async/await`, eliminate DispatchQueue.global wrapping |
| `WalletConnectHandlers.swift` | Inherits web3swift call patterns | Same |
| `Web3Model.swift` | Uses `WalletAccessor` | Minimal changes |

Post-migration: Remove PromiseKit and Starscream from SPM graph (they were transitive deps of old web3swift).

### Phase 4 — Apollo iOS 0.49.0 → 2.x Migration

Apollo iOS had a **complete API rewrite** in 1.0:
- New code generation tool (`apollo-ios-cli` replacing `apollo-codegen`)
- New operation model (`GraphQLQuery`, `GraphQLMutation` protocol changes)
- `ApolloClient.fetch` API changed
- Codegen output format changed (new directory structure)

This requires migrating `Codegen/Package.swift`, all `.graphql` files' generated counterparts,
and all Apollo client call sites in the app.

| Current | Target | Notes |
|---------|--------|-------|
| apollo-ios 0.49.0 | 2.x | Major rewrite; Codegen Package.swift needs new CLI |
| SQLite.swift 0.16.0 | 0.16.0 ✅ | Already at latest (via Apollo transitive dep) |

### Phase 5 — Carthage → SPM Migration

All current Carthage deps (except `GCDWebServer`) ship `Package.swift` and can be moved to SPM:

| Dep | Cartfile version | SPM target | Notes |
|-----|-----------------|------------|-------|
| SnapKit | ~> 5.0 (5.7.1) | 5.7.1 | Drop-in replacement |
| SDWebImage | ~> 5.10 (5.21.7) | 5.21.7 | Already SPM-capable |
| SDWebImageSwiftUI | ~> 2.0 (2.2.7) | **3.x** | Minor SwiftUI lifecycle API changes |
| SwiftyJSON | ~> 5.0 (5.0.2) | 5.0.2 | Drop-in replacement |
| XCGLogger | ~> 7.0 (7.1.5) | 7.1.5 | Drop-in replacement |
| SwiftKeychainWrapper | ~> 3.2 | **4.0.1** | API changes: `KeychainWrapper.standard` still works |
| KIF | v3.12.3 | v3.12.3 | UI testing only |
| GCDWebServer | ~> 3.5.4 | keep Carthage | No Package.swift |

### Phase 6 — Swift 6 Strict Concurrency

Enable `SWIFT_STRICT_CONCURRENCY = complete` in build settings. Expected issues:
- 693 Swift files to audit for `Sendable` conformance
- `@MainActor` isolation missing on UI update callbacks
- `actor` isolation needed for shared mutable state (search, wallet, spaces)
- `Defaults` (Neeva fork) pinned to `neeva-v4.2.2` branch — needs migration to upstream sindresorhus/Defaults 9.x

Staged approach:
1. `SWIFT_STRICT_CONCURRENCY = targeted` (warnings only, safe to enable now)
2. Fix warnings file by file starting with Models and Services
3. Promote to `complete` after all warnings resolved
4. Set `SWIFT_VERSION = 6.0`

### Phase 7 — Xcode 26 / iOS 26 Support

- Move CI from `macos-15` (Xcode 16.4 default) to `macos-15` with `xcode: 26.3`
- iOS 26 SDK adds new APIs and deprecates some UIKit patterns
- SwiftUI-Introspect will need upgrade from 1.3.0 → 26.x (iOS 26 platform enum)
- SFSafeSymbols 7.0.0 already includes SF Symbols 7.0 (iOS 26) symbols ✅

---

## Architecture Notes

- **Two `Space` types**: `SpacesDataQueryController.Space` (comments non-optional) vs `SpaceStore.Space` (comments optional). Views use `SpaceStore.Space`.
- **web3swift fork**: `outlaw-dame/web3swift@xcode16-compat` (`e9fc4e44`). Identical to `e5e339b65` except `(uint)` → `(unsigned int)` C fix for Xcode 16.4. Full async/await migration tracked in Phase 3.
- **PromiseKit + Starscream**: Transitive deps of web3swift (old API). Remain in SPM graph until Phase 3 migration.
- **Defaults fork**: Pinned to `neevaco/sindresorhus-Defaults@neeva-v4.2.2`. Upstream sindresorhus/Defaults is at 9.0.8 — migration requires reviewing Neeva-specific patches on that branch.
- **SKIP_SWIFT_FORMAT_BUILD=1**: swift-format submodule build skipped in CI to save ~10 min.
- **Carthage caching**: key = `hashFiles('Cartfile.resolved')`. npm build runs unconditionally before the cache gate.
- **webpack 5**: No `package-lock.json` in repo (deleted during migration); `bootstrap.sh` handles both `npm ci` (if lockfile exists) and `npm install` fallback. Regenerating and committing the lockfile is on the roadmap.
