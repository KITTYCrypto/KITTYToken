# ChainScope AI iOS Sideloadly Guide

This folder contains the native SwiftUI iOS app:

`C:\Bots\ChainScope\ChainScopeBot\ios\ChainScopeAI`

Sideloadly installs an `.ipa` onto an iPhone. It does not build Swift source by itself, so the flow is:

1. Build a device `.ipa` from this Xcode project.
2. Open that `.ipa` in Sideloadly.
3. Let Sideloadly sign/install it with your Apple ID.
4. Trust the installed developer profile on the iPhone.
5. Log into ChainScope from the app and test director features.

## Fastest Path With Codemagic

Use the workflow added at the repository root:

`chainscope-ios-sideloadly-ipa`

Display name:

`ChainScope iOS - Sideloadly IPA`

Steps:

1. Push or upload this repo/source package to Codemagic.
2. In Codemagic, run `ChainScope iOS - Sideloadly IPA`.
3. Download the artifact:

   `ChainScopeAI-sideloadly-unsigned.ipa`

4. On Windows, install/open Sideloadly.
5. Connect the iPhone by USB.
6. Drag `ChainScopeAI-sideloadly-unsigned.ipa` into Sideloadly.
7. Enter the Apple ID you want to use for sideload signing.
8. Start install.
9. On iPhone, trust the developer profile:

   `Settings > General > VPN & Device Management`

10. Open `ChainScope AI`.

## Local Mac/Xcode Path

If you use a Mac instead of Codemagic:

1. Open:

   `ios/ChainScopeAI/ChainScopeAI.xcodeproj`

2. Select scheme:

   `ChainScopeAI`

3. Select an iPhone device target.
4. Set a development team if Xcode asks.
5. Build/archive for iOS device.
6. Export or package an `.ipa`.
7. Install that `.ipa` with Sideloadly.

## App Defaults

Backend URL:

`https://api.socacrypto.com`

Bundle ID:

`ai.chainscope.mobile.ios`

URL callback scheme:

`chainscope://`

The iOS app includes:

- Dashboard loading.
- Keychain-backed API key storage.
- Director access-code login.
- Coinbase Secret API Key registration.
- Solana hot-wallet registration.
- Public wallet registration.
- Wallet connection disconnect controls.
- Phantom, Solflare, and MetaMask handoff links.
- iOS push-token registration scaffold.

## First Install Test Checklist

After the app opens:

1. Confirm the dashboard loads from `https://api.socacrypto.com`.
2. Enter a director access code and confirm the director session opens.
3. Check Live/Connections.
4. Confirm active wallets and Coinbase connections match the web dashboard.
5. Test disconnect on a harmless/stale connection only.
6. Register a public Phantom/Solana wallet if needed.
7. Test a wallet signing link with a test approval before trusting live approvals.

## Important Sideloadly Notes

- A free Apple ID usually requires reinstalling/refreshing the app periodically.
- A paid Apple Developer account gives a smoother signing experience.
- Sideloaded builds are for internal testing, not App Store distribution.
- Do not paste private keys into screenshots, videos, logs, or chat.
- If the install fails, try a different bundle ID such as:

  `ai.chainscope.mobile.ios.brandon`

  Then rebuild the IPA and install again.

