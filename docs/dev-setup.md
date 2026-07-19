# Developer Setup

## Prerequisites

- **macOS 26.0+**
- **Xcode 26.0+** (ships the macOS 26 SDK required by `SpeechTranscriber`; with command-line tools installed)
- **XcodeGen** — install via Homebrew:
  ```bash
  brew install xcodegen
  ```

## Getting Started

### 1. Clone the repo (with submodules)

The vendored dependencies under `Vendor/` are git submodules, so clone recursively:

```bash
git clone --recurse-submodules https://github.com/bitwize-ai/Logue.git
cd Logue
```

If you already cloned without `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

### 2. Download the Metal toolchain

MLX inference requires the Metal toolchain component (one-time download):

```bash
xcodebuild -downloadComponent MetalToolchain
```

### 3. Generate the Xcode project

Logue uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj` from `project.yml`. Run this after cloning and whenever you add/remove source files:

```bash
xcodegen generate
```

### 4. Open in Xcode

```bash
open Logue.xcodeproj
```

Select the **Logue** scheme and build (`Cmd+B`) or run (`Cmd+R`).

### 5. Build from the command line (optional)

```bash
xcodebuild -project Logue.xcodeproj -scheme Logue -configuration Debug build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Linting & Git Hooks

The project uses **SwiftFormat** and **SwiftLint** to enforce code style. Running `make setup` automatically installs git hooks that check your code before commits and pushes.

```bash
# Install tools
brew install swiftformat swiftlint

# Install hooks (also runs as part of make setup)
make install-hooks
```

- **Pre-commit hook**: runs `swiftformat --lint` and `swiftlint lint --strict` on staged `.swift` files
- **Pre-push hook**: runs a full lint check on `Logue/`

To manually format or lint:

```bash
make format   # auto-fix formatting
make lint     # check for lint issues
```

## Auto-Updates (Sparkle)

Logue uses [Sparkle 2](https://sparkle-project.org/) for in-app updates, served
**entirely from GitHub — no backend**. The appcast lives in the repo
([`appcast.xml`](../appcast.xml)) and update assets are attached to GitHub
Releases. Full details, the release process, and key-rotation/forking steps are
in [SPARKLE_UPDATE_FLOW.md](SPARKLE_UPDATE_FLOW.md).

Keys: the **public** key (`SUPublicEDKey`) lives in `project.yml` and is embedded
in `Info.plist` on `xcodegen generate`. The **private** key exists only as the
`SPARKLE_PRIVATE_KEY` GitHub Actions secret — never commit it.

## Vendor Dependencies

Vendored SPM packages live in `Vendor/` (git submodules — see `.gitmodules`):

| Package | Description |
|---------|-------------|
| `LangGraph-Swift` | LangGraph agent framework (product: `LangGraph`) |
| `swift-markdown` | Markdown parsing (product: `Markdown`) |

Remote SPM dependencies (resolved by Xcode, pinned in `project.yml`):

| Package | Products | Description |
|---------|----------|-------------|
| `mlx-swift-lm` | `MLXLLM`, `MLXLMCommon` | On-device MLX LLM inference |
| `swift-transformers-mlx` | `MLXLMTransformers` | Tokenizers / model plumbing for MLX |
| `swift-hf-api-mlx` | `MLXLMHFAPI` | Hugging Face model download / hub cache |
| `FluidAudio` | `FluidAudio` | Speaker diarization, VAD |
| `Sparkle` | `Sparkle` | In-app auto-update |
| `Textual` | `Textual` | Rich text |

## Troubleshooting

**`xcodegen` not found** — Install with `brew install xcodegen`.

**Build fails with missing module** — Clean SPM cache and re-resolve:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
xcodegen generate
```

**Sparkle "Update signature is invalid"** — the `SUPublicEDKey` in `project.yml` doesn't match the private key used to sign the ZIP. See [SPARKLE_UPDATE_FLOW.md](SPARKLE_UPDATE_FLOW.md).

## Releasing

Releases are built, signed, notarized, and published to **GitHub Releases** by
[`.github/workflows/release.yml`](../.github/workflows/release.yml), which runs on
a **GitHub-hosted `macos-15` runner** (no self-hosted machine required). It then
opens a PR updating [`appcast.xml`](../appcast.xml); merging that PR publishes the
Sparkle update. See [SPARKLE_UPDATE_FLOW.md](SPARKLE_UPDATE_FLOW.md) for the full flow.

### Required repository secrets

Set these under **Settings → Secrets and variables → Actions** (forkers set their own):

| Secret | Purpose |
|--------|---------|
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_CERTIFICATE_BASE64` | base64 of your "Developer ID Application" `.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | password for that `.p12` |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_APP_PASSWORD` | app-specific password for that Apple ID |
| `SPARKLE_PRIVATE_KEY` | EdDSA private key used to sign update ZIPs |

### Triggering a release

```bash
# Option A: push a version tag
git tag v1.0.0
git push origin v1.0.0

# Option B: manual dispatch
gh workflow run release.yml -f version=1.0.0
```

Or use the GitHub UI: **Actions → Release Build → Run workflow**.

> Prefer a self-hosted runner (e.g. to avoid Actions minutes or use a warm cache)?
> Change `runs-on: macos-15` in `release.yml` back to `self-hosted`.
