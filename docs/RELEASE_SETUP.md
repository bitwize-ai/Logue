# Release CI Setup

How to make `.github/workflows/release.yml` runnable. The release job builds, signs,
notarizes, and publishes a DMG + update ZIP to GitHub Releases, then opens a PR that
updates the Sparkle appcast. **No backend is involved** — updates are served entirely
from GitHub.

> **Sparkle is kept, not removed.** The app boots a `SPUStandardUpdaterController` in
> `AppDelegate` and reads its feed from this repo. As long as the repo is **public**,
> Sparkle downloads both the appcast and the release asset with **no authentication**
> (see [Repo visibility](#repo-visibility) below). Removing Sparkle from CI while it is
> still wired into the app would ship a broken auto-updater, so we don't.

---

## Repo visibility

Sparkle fetches two things at runtime, both from this repo:

| What | URL | Public repo | Private repo |
| ---- | --- | ----------- | ------------ |
| Appcast | `https://raw.githubusercontent.com/bitwize-ai/Logue/main/appcast.xml` | anonymous GET ✅ | 404 without token ❌ |
| Update asset | `https://github.com/bitwize-ai/Logue/releases/download/<tag>/Logue-<ver>.zip` | anonymous GET ✅ | 404 without token ❌ |

**Auto-update requires the repo to be public.** There is no supported way to ship a
token inside the app to read a private repo's assets — don't try. If the repo must stay
private, auto-update has to be disabled (a separate change).

---

## Required repository secrets

Set these at **GitHub → repo → Settings → Secrets and variables → Actions → New repository secret**
(`https://github.com/bitwize-ai/Logue/settings/secrets/actions`).

| Secret | What it is | Where to get it |
| ------ | ---------- | --------------- |
| `APPLE_TEAM_ID` | 10-char Apple Developer Team ID | [developer.apple.com/account](https://developer.apple.com/account) → Membership details |
| `APPLE_CERTIFICATE_BASE64` | Base64 of your **Developer ID Application** `.p12` | Export from Keychain, then base64 — see below |
| `APPLE_CERTIFICATE_PASSWORD` | Password you set when exporting the `.p12` | You choose it during export |
| `APPLE_ID` | Apple ID email used for notarization | Your Apple Developer account email |
| `APPLE_APP_PASSWORD` | App-specific password (not your login password) | [appleid.apple.com](https://appleid.apple.com) → Sign-In & Security → App-Specific Passwords |
| `SPARKLE_PRIVATE_KEY` | EdDSA private key that signs each update | Generate with Sparkle's `generate_keys` — see below |

`GITHUB_TOKEN` is **not** a secret you set — GitHub injects it automatically. But it
needs one repo setting enabled (see [PR permission](#pr-permission)).

---

### Generating each secret

#### `APPLE_CERTIFICATE_BASE64` + `APPLE_CERTIFICATE_PASSWORD`

1. In **Keychain Access**, find your **Developer ID Application: … (TEAMID)** certificate
   (with its private key). If you don't have one, create it at
   developer.apple.com → Certificates → **Developer ID Application**.
2. Right-click → **Export** → save as `certificate.p12`, set an export password.
3. Base64-encode it for the secret value:
   ```bash
   base64 -i certificate.p12 | pbcopy   # paste as APPLE_CERTIFICATE_BASE64
   ```
   Use the export password as `APPLE_CERTIFICATE_PASSWORD`.

#### `APPLE_APP_PASSWORD`

At [appleid.apple.com](https://appleid.apple.com) → **Sign-In and Security → App-Specific
Passwords → Generate**. Label it e.g. `logue-notarization`. Format looks like
`abcd-efgh-ijkl-mnop`.

#### `SPARKLE_PRIVATE_KEY` ⚠️ must regenerate

The public key currently baked into the app
(`SUPublicEDKey: qW5+1txwxxQGCE1YVV0YgU4o4IAbSFNrEGVTdhhsO7k=` in `project.yml`) belongs
to the **original** keypair. Unless you hold that private key, you must generate a fresh
pair and update the public half, or Sparkle will reject every update as unsigned.

```bash
# Get Sparkle's tools (matches the 2.9.1 used in release.yml)
curl -L -o sparkle.tar.xz \
  https://github.com/sparkle-project/Sparkle/releases/download/2.9.1/Sparkle-2.9.1.tar.xz
tar xf sparkle.tar.xz
./bin/generate_keys        # prints the PUBLIC key; stores the PRIVATE key in the Keychain
./bin/generate_keys -x private_key.pem   # export the PRIVATE key to a file
```

- Paste the **private** key (`private_key.pem` contents) as the `SPARKLE_PRIVATE_KEY`
  secret.
- Put the printed **public** key into `SUPublicEDKey` in **`project.yml`** (line ~77),
  then run `xcodegen generate` so it lands in `Info.plist`.

> The private key never goes in the repo. Only the public key (`SUPublicEDKey`) is
> committed, and it is safe to publish.

---

## PR permission

The final workflow step (`Create appcast PR`) uses the built-in `GITHUB_TOKEN` to open a
PR. By default an org repo blocks Actions from creating PRs, so this step fails even
though the release already published.

Enable it at **repo → Settings → Actions → General → Workflow permissions**:

- ✅ **Read and write permissions**
- ✅ **Allow GitHub Actions to create and approve pull requests**

(`https://github.com/bitwize-ai/Logue/settings/actions`)

---

## How to cut a release

Either:

- **Push a tag:** `git tag v1.0.0 && git push origin v1.0.0`, or
- **Manual:** repo → Actions → **Release Build** → **Run workflow** → enter version.

The run produces a signed, notarized DMG + ZIP on GitHub Releases and opens a
`chore/appcast-vX.Y.Z` PR. **Merge that PR** to publish the update feed — Sparkle clients
only see the new version once `appcast.xml` on `main` is updated.

---

## Secret checklist

- [ ] `APPLE_TEAM_ID`
- [ ] `APPLE_CERTIFICATE_BASE64`
- [ ] `APPLE_CERTIFICATE_PASSWORD`
- [ ] `APPLE_ID`
- [ ] `APPLE_APP_PASSWORD`
- [ ] `SPARKLE_PRIVATE_KEY` (with matching `SUPublicEDKey` updated in `project.yml`)
- [ ] Repo is **public** (for auto-update to reach users)
- [ ] "Allow GitHub Actions to create and approve pull requests" enabled
