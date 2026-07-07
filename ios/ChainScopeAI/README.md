# ChainScope AI iOS

Native SwiftUI iOS client for ChainScope AI.

## What This First iOS Build Includes

- Private and public ChainScope dashboard loading.
- Keychain-backed storage for the dashboard API key and director session token.
- Director Portal access-code session flow.
- Live-trade connection list and disconnect actions.
- Public self-custody wallet registration for Solana and ETH/EVM.
- Coinbase Secret API Key registration using the same backend endpoint as Android.
- Solana executor wallet registration using the same backend endpoint as Android.
- Native Phantom/MetaMask approval handoff through `chainscope://` return links.
- APNs registration scaffold that posts iOS device tokens to `/api/mobile/push-token`.

## Build Requirements

- macOS with Xcode 16 or newer.
- Apple Developer account with an app identifier for `ai.chainscope.mobile.ios` or an updated bundle identifier.
- Push Notifications capability enabled if APNs delivery is needed.

## Build

Open `ChainScopeAI.xcodeproj` in Xcode, select the `ChainScopeAI` scheme, choose a development team, then build for an iPhone device.

This repository was prepared on Windows, so the source package is ready but an `.ipa` cannot be signed locally without macOS/Xcode or a cloud Mac runner.

## Sideloadly

For Sideloadly testing, use:

`SIDELOADLY.md`

Sideloadly needs an `.ipa`, not raw Swift source. The repository root `codemagic.yaml` includes a `ChainScope iOS - Sideloadly IPA` workflow that builds `ChainScopeAI-sideloadly-unsigned.ipa` for Sideloadly to sign and install.

## Codemagic

The repository root includes `codemagic.yaml`.

Run `ChainScope iOS - Unsigned Build Check` first. After Apple signing is configured in Codemagic, run `ChainScope iOS - App Store Connect Upload`.

The signed workflow expects the App Store Connect integration name:

`chainscope-apple`

## Backend

The app defaults to:

`https://api.socacrypto.com`

Private mode uses `X-ChainScope-Key`. Director-scoped actions also use `X-ChainScope-Director-Token` after a successful Director Portal session.
