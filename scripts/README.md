# Logue Release Build Guide

Complete guide to set up code signing, notarization, and build a distributable DMG.

## Prerequisites

- macOS with Apple Silicon
- Xcode installed (with macOS 26 SDK)
- [Apple Developer Program membership](https://developer.apple.com/programs/) ($99/year)

## 1. Install Build Tools

```bash
brew install xcodegen create-dmg
xcodebuild -downloadComponent MetalToolchain
```

## 2. Create a Developer ID Certificate

You need a **Developer ID Application** certificate to sign apps distributed outside the Mac App Store.

### 2a. Generate a Certificate Signing Request (CSR)

1. Open **Keychain Access** (Applications > Utilities)
2. Menu: **Keychain Access > Certificate Assistant > Request a Certificate from a Certificate Authority**
3. Fill in:
   - **User Email Address**: your Apple ID email
   - **Common Name**: your name or company name
   - **Request is**: select **Saved to disk**
4. Click **Continue** and save the `.certSigningRequest` file

### 2b. Create the Certificate on Apple Developer Portal

1. Go to [Apple Developer > Certificates](https://developer.apple.com/account/resources/certificates/list)
2. Click the **+** button
3. Under **Software**, select **Developer ID Application**
4. Click **Continue**
5. Upload the `.certSigningRequest` file from step 2a
6. Click **Continue**, then **Download** the `.cer` file

### 2c. Install the Certificate

1. Double-click the downloaded `.cer` file — it opens in Keychain Access
2. It will be installed in your **login** keychain

### 2d. Verify Installation

```bash
security find-identity -v -p codesigning | grep "Developer ID"
```

You should see output like:

```
1) ABCDEF123456... "Developer ID Application: Your Name (XXXXXXXXXX)"
```

The 10-character code in parentheses is your **Team ID**.

## 3. Set Up Notarization Credentials

Apple notarization requires an app-specific password (not your regular Apple ID password).

### 3a. Create an App-Specific Password

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign in, go to **Sign-In and Security > App-Specific Passwords**
3. Click **Generate an app-specific password**
4. Label it `Logue Notarize`
5. Copy the generated password (format: `xxxx-xxxx-xxxx-xxxx`)

### 3b. Store Credentials in Keychain

```bash
xcrun notarytool store-credentials "Logue-Notarize" \
    --apple-id "your@email.com" \
    --team-id "XXXXXXXXXX" \
    --password "xxxx-xxxx-xxxx-xxxx"
```

Replace:
- `your@email.com` with your Apple ID
- `XXXXXXXXXX` with your Team ID from step 2d
- `xxxx-xxxx-xxxx-xxxx` with the app-specific password from step 3a

### 3c. Verify Stored Credentials

```bash
xcrun notarytool history --keychain-profile "Logue-Notarize"
```

This should authenticate successfully (empty history is fine for a new account).

## 4. Build the Release

### Quick Test (skip notarization)

```bash
./scripts/build_release.sh --skip-notarize
```

### Full Release Build

```bash
./scripts/build_release.sh
```

### With Explicit Options

```bash
./scripts/build_release.sh \
    --version 1.0.0 \
    --build 1 \
    --team-id XXXXXXXXXX \
    --keychain-profile "Logue-Notarize"
```

### Script Options

| Flag | Description | Default |
|------|-------------|---------|
| `--version X.Y.Z` | App version number | Read from `project.yml` |
| `--build N` | Build number | Read from `project.yml` |
| `--team-id XXXXXXXXXX` | Apple Team ID | Auto-detected from Keychain |
| `--keychain-profile NAME` | Notarization credential profile | `Logue-Notarize` |
| `--skip-notarize` | Skip notarization step | Off |

## 5. Build Output

After a successful build, you'll find:

```
build/
  Logue.xcarchive        # Xcode archive
  export/
    Logue.app             # Signed app bundle
  Logue-1.0.0.dmg        # Final distributable DMG (signed + notarized)
```

## 6. What the Build Script Does

1. Checks prerequisites (xcodegen, create-dmg, certificate)
2. Generates Xcode project from `project.yml`
3. Resolves Swift Package Manager dependencies
4. Archives the app (Release, arm64)
5. Exports the archive with Developer ID signing
6. Deep-signs the app bundle with hardened runtime + entitlements
7. Creates a styled DMG (drag-to-Applications installer)
8. Signs the DMG
9. Submits to Apple for notarization and waits for approval
10. Staples the notarization ticket to the DMG

## 7. CI/CD (GitHub Actions)

The release workflow at `.github/workflows/release.yml` automates the full pipeline. Push a version tag to trigger it:

```bash
git tag v1.0.0
git push origin v1.0.0
```

### Required GitHub Secrets

Set these in **Settings > Secrets and variables > Actions**:

| Secret | How to Get It |
|--------|---------------|
| `APPLE_CERTIFICATE_BASE64` | Export cert from Keychain as .p12, then `base64 -i cert.p12 \| pbcopy` |
| `APPLE_CERTIFICATE_PASSWORD` | Password you set when exporting the .p12 |
| `APPLE_TEAM_ID` | 10-char Team ID from step 2d |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_APP_PASSWORD` | App-specific password from step 3a |

### Export Certificate as .p12 for CI

1. Open **Keychain Access**
2. Find your **Developer ID Application** certificate
3. Expand it to see the private key
4. Select **both** the certificate and the private key
5. Right-click > **Export 2 items...**
6. Save as `.p12`, set a strong password
7. Base64-encode it:

```bash
base64 -i certificate.p12 | pbcopy
```

8. Paste as the `APPLE_CERTIFICATE_BASE64` secret in GitHub

## 8. Sparkle Auto-Update Setup

Logue uses [Sparkle 2](https://sparkle-project.org/) for automatic updates. Sparkle checks an `appcast.xml` feed, downloads the update ZIP, verifies its EdDSA signature, and installs it — all with built-in native UI.

### How It Works

1. CI builds and codesigns the app, creates a ZIP
2. CI signs the ZIP with an EdDSA private key (Sparkle's `sign_update`)
3. CI publishes the ZIP + DMG to **GitHub Releases** and updates `appcast.xml` in the repo
4. The app reads the appcast from `raw.githubusercontent.com` and downloads ZIPs straight from GitHub Releases — no backend
5. Sparkle in the app downloads the update and prompts the user to restart

### Generate EdDSA Key Pair (One-Time)

Download Sparkle and run the key generator:

```bash
# Download Sparkle release
SPARKLE_VERSION="2.9.1"
curl -L -o /tmp/sparkle.tar.xz \
  "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
mkdir -p /tmp/sparkle-tools
tar xf /tmp/sparkle.tar.xz -C /tmp/sparkle-tools

# Generate key pair
/tmp/sparkle-tools/bin/generate_keys
```

This prints:

```
A]  Public key to embed in your app's Info.plist as SUPublicEDKey:
    <base64 public key>

B]  Private key saved to ~/Library/Sparkle/ed25519.key
    Back up this file! You'll need it to sign future updates.
```

### Configure the Keys

> ⚠️ **Never commit the private key.** This is a public repo. Keep the private key
> in your password manager / `~/Library/Sparkle/ed25519.key` backup only.

1. **Public key** goes in `project.yml` (`SUPublicEDKey`) — embedded in `Info.plist` on `xcodegen generate`.
2. **Private key** must be added as a GitHub Actions secret:
   - Go to repo **Settings > Secrets and variables > Actions**
   - Create secret `SPARKLE_PRIVATE_KEY` with the private key value.
3. **If keys are regenerated**, update both `project.yml` (`SUPublicEDKey`) and the GitHub secret.

### Required GitHub Secrets (Updated)

| Secret | Description |
|--------|-------------|
| `APPLE_CERTIFICATE_BASE64` | Developer ID cert (see section 7) |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the .p12 |
| `APPLE_TEAM_ID` | 10-char Apple Team ID |
| `APPLE_ID` | Apple ID email |
| `APPLE_APP_PASSWORD` | App-specific password for notarization |
| `SPARKLE_PRIVATE_KEY` | EdDSA private key from `generate_keys` |

### Testing the Update Flow Locally

1. Build the app with a low version (e.g. `0.0.1`)
2. Create a test `appcast.xml` with a higher version pointing to a local/remote ZIP
3. Set `SUFeedURL` to point to your test appcast (via env override or debug build)
4. Launch the app — Sparkle will detect the "update" and show its install dialog

### Appcast Management

The `appcast.xml` in the repo root is updated automatically by CI on every release. To manually add an entry:

```bash
python3 scripts/update_appcast.py \
  --version 1.2.0 \
  --build 42 \
  --signature "BASE64_SIGNATURE" \
  --length 12345678 \
  --min-os 26.0 \
  --notes "Bug fixes and performance improvements"
```

---

## Troubleshooting

### "No Developer ID Application certificate found"
Your certificate isn't installed. Follow step 2 above.

### Notarization fails with "invalid credentials"
Re-run `xcrun notarytool store-credentials` with the correct app-specific password. Regular Apple ID passwords don't work.

### Build fails with "Unable to find module dependency"
Clean the package cache and retry:
```bash
rm -rf build/SourcePackages
./scripts/build_release.sh --skip-notarize
```

### DMG icon positioning looks off
Add a custom background image at `scripts/dmg_background.png` (660x400px). Without it, the DMG uses the default macOS style.

### Sparkle: "Update signature is invalid"
The EdDSA signature doesn't match the public key in the app. Ensure:
- `SUPublicEDKey` in `project.yml` matches the private key used to sign
- The `SPARKLE_PRIVATE_KEY` GitHub secret is correct and not truncated
- You haven't regenerated keys without updating both the secret and Info.plist

### Sparkle: No update prompt appears
- Verify `SUFeedURL` is reachable (try `curl https://raw.githubusercontent.com/bitwize-ai/Logue/main/appcast.xml`)
- Check the appcast has an `<item>` with a version higher than the running app
- Ensure the enclosure `url` points at an existing GitHub Release asset
- Sparkle only checks once per session by default — restart the app to re-check
