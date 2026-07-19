# Sparkle Update Flow

Logue ships in-app auto-updates via [Sparkle 2](https://sparkle-project.org/),
served **entirely from GitHub — there is no backend**.

- **Appcast feed:** `https://raw.githubusercontent.com/bitwize-ai/Logue/main/appcast.xml` (the [`appcast.xml`](../appcast.xml) committed to this repo).
- **Release assets:** the update ZIP and DMG are attached to each [GitHub Release](https://github.com/bitwize-ai/Logue/releases).
- **Signing:** each update ZIP is signed with an **EdDSA (Ed25519)** key. The public key (`SUPublicEDKey`) is embedded in the app; the private key exists only as the `SPARKLE_PRIVATE_KEY` GitHub Actions secret.

```
┌─────────────┐   reads SUFeedURL    ┌──────────────────────────────┐
│  Logue.app  │ ───────────────────▶ │ raw.githubusercontent.com     │
│  (Sparkle)  │                       │   …/main/appcast.xml          │
└─────┬───────┘                       └──────────────────────────────┘
      │ newest <item> → enclosure url
      ▼
┌──────────────────────────────────────────────┐
│ github.com/bitwize-ai/Logue/releases/download │  ← downloads ZIP
│   /v<version>/Logue-<version>.zip             │  ← verifies EdDSA signature
└──────────────────────────────────────────────┘     against embedded SUPublicEDKey
```

## Info.plist keys (set in `project.yml`)

| Key | Value | Purpose |
|-----|-------|---------|
| `SUFeedURL` | `https://raw.githubusercontent.com/bitwize-ai/Logue/main/appcast.xml` | Where the app fetches the appcast |
| `SUPublicEDKey` | (base64 Ed25519 public key) | Verifies update signatures |
| `SUEnableAutomaticChecks` | `true` | Check for updates on launch |
| `SUAutomaticallyUpdate` | `false` | Prompt the user rather than silently installing |

## Release process (automated by [`.github/workflows/release.yml`](../.github/workflows/release.yml))

Triggered by pushing a `v*` tag or the manual **Run workflow** dispatch:

1. Build → deep codesign (hardened runtime) → notarize + staple the DMG.
2. Create the update **ZIP** and sign it with EdDSA using `SPARKLE_PRIVATE_KEY`.
3. Publish a **GitHub Release** with the DMG + ZIP attached (the download URL must exist before the appcast references it).
4. Run [`scripts/update_appcast.py`](../scripts/update_appcast.py) to prepend a new `<item>` whose `enclosure url` points at the GitHub Release ZIP.
5. Open a PR with the updated `appcast.xml`. **Merging that PR to `main` publishes the update** (the feed is served from `main` via `raw.githubusercontent.com`).

## Data safety

Updates only replace `Logue.app`. All user data lives in Application Support
(`~/Library/Containers/com.bitwize.logue/Data/…` for the sandboxed release) and
the on-device model cache — never inside the app bundle — so upgrading never
touches meetings, documents, models, or settings. This holds as long as the
**bundle identifier stays the same**.

## Key rotation / forking

To run your own update channel from a fork:

1. Generate a key pair with Sparkle's `generate_keys` tool (from the Sparkle release archive).
2. Put the **public** key in `SUPublicEDKey` (`project.yml`) and repoint `SUFeedURL` at your fork's `appcast.xml`.
3. Store the **private** key as the `SPARKLE_PRIVATE_KEY` GitHub Actions secret in your fork. Never commit it.
4. Update `GITHUB_REPO` in `scripts/update_appcast.py` if your fork's path differs.
