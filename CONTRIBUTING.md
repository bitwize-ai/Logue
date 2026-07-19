# Contributing to Logue

Thanks for your interest in improving Logue! Logue is a privacy-first, on-device AI
meeting-notes and writing assistant for macOS. This guide covers how to get set up and
the standards every pull request is expected to meet.

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE),
and that you will follow our [Code of Conduct](CODE_OF_CONDUCT.md). To report a security
vulnerability, please follow the [Security Policy](SECURITY.md) rather than opening a public issue.

## Getting Started

See [`docs/dev-setup.md`](docs/dev-setup.md) for full setup instructions. In short:

```bash
# Clone with submodules — the vendored dependencies live in Vendor/
git clone --recurse-submodules https://github.com/bitwize-ai/Logue.git
cd Logue

# One-time: download the Metal toolchain (required by MLX)
xcodebuild -downloadComponent MetalToolchain

# Install tooling and generate the Xcode project
brew install xcodegen swiftformat swiftlint
xcodegen generate
make install-hooks   # SwiftFormat + SwiftLint pre-commit / pre-push hooks

# Build
xcodebuild build -project Logue.xcodeproj -scheme Logue -destination 'platform=macOS'
```

> Run `xcodegen generate` after adding or removing `.swift` files, or after editing `project.yml`.

If you already cloned without `--recurse-submodules`, run
`git submodule update --init --recursive`.

## Development Workflow

1. Fork the repo and create a feature branch off `main`.
2. Make your change, keeping commits focused and descriptive.
3. Ensure the project builds and lints cleanly (hooks run automatically).
4. Add or update tests where it makes sense (see below).
5. Open a pull request against `main` describing the change and how you verified it.

## Code Standards

These rules are enforced in review and by pre-commit hooks. Please follow them when
writing code.

### SwiftLint / SwiftFormat

Write code that passes SwiftLint **without suppressions** — a `swiftlint:disable`
comment is a smell; fix the underlying issue instead. Key rules:

- **No force unwrapping (`!`)** — use `guard let`, `if let`, or `?? default`.
- **No force casting (`as!`)** — use `as?` with a guard.
- **Function body ≤ 60 lines**, **cyclomatic complexity ≤ 15**, **file length ≤ 800 lines** —
  split large types into `Foo.swift` (core) + `Foo+Feature.swift` extension files.
- **Line length ≤ 150 chars** (warning), ≤ 200 (error).
- Descriptive identifier names, 2–60 chars, no `_` prefix on non-private members.

A few narrowly-scoped suppressions are acceptable **with a comment explaining why** —
e.g. `force_unwrapping` on a compile-time-constant `URL(string:)!` in seed data,
`force_cast` on CoreFoundation bridging after a `CFGetTypeID()` check, `file_length` on
pure static-data files.

### Security

- **Wrap all user content in XML delimiters** when injecting into LLM prompts
  (`<transcript>…</transcript>`, `<content>…</content>`, etc.). No exceptions.
- **Sanitize user-provided strings** before embedding them in prompts — truncate length
  and strip control characters.
- **Validate the context window before every LLM call** and truncate input to fit.
- **Never use `[0]` on a `FileManager` URL array** — use `.first ?? URL.temporaryDirectory`.
- **Require HTTPS** for any user-supplied endpoint (except `localhost`/`127.0.0.1`).
- **Log URLs with `url.host` only** — never log `url.absoluteString`.

### Concurrency & Thread Safety

- All LLM inference **must** route through `LLMEngine.complete()` / `completeStream()` —
  never call the underlying session directly. This preserves the `inferenceGate`
  serialization that prevents session races.
- Swift actors are reentrant — don't assume actor methods run atomically across `await`
  points. Re-check state after any `await`.
- Document every `@unchecked Sendable` and `nonisolated(unsafe)` usage with what
  guarantees safety.
- Use `[weak self]` in `Task` closures unless `self` is a singleton and the task is
  trivially short.

### Error Handling

- **No silent `try?`** for real work (file I/O, network, decoding). Use `do/catch` with
  logging. (`try? await Task.sleep(...)` is the one accepted exception.)
- Use `withRetry()` / `withRetryOptional()` from `RetryHelper.swift` rather than manual
  retry loops.
- Log LLM JSON decode failures with the error and a truncated raw response.

For the complete, always-current ruleset the project builds against, see
[`CLAUDE.md`](CLAUDE.md).

## Testing

Tests use the **Swift Testing** framework (`@Suite`, `@Test`, `#expect` — not XCTest) and
live in [`LogueTests/`](LogueTests). The LLM integration suites run real on-device
inference against a local MLX model:

```bash
xcodebuild test -project Logue.xcodeproj -scheme Logue \
  -destination 'platform=macOS' -only-testing:LogueTests/<SuiteName>
```

## Reporting Issues

Found a bug or have a feature idea? Please
[open an issue](https://github.com/bitwize-ai/Logue/issues) with as much detail as you
can — steps to reproduce, macOS version, and Mac model help a lot.

## Project Governance & Releases

Logue is open source and community contributions are very welcome, but the project
is **maintained by [Bitwize](https://bitwize.ai)**, who own the roadmap and the
release process:

- **Anyone can contribute.** Fork the repo, open a pull request against `main`, and a
  maintainer will review it. Please keep PRs focused and follow the standards above.
- **Bitwize reviews and merges.** Only maintainers merge to `main`. Approval from a
  maintainer is required; `main` is protected and CI (build + lint) must pass.
- **Bitwize cuts releases.** Signed, notarized builds are produced only by Bitwize.
  Contributors never need signing certificates or Sparkle keys to build, test, or
  submit changes — those live solely in the maintainers' GitHub Actions secrets.
- **Versioning** follows [Semantic Versioning](https://semver.org). Releases are cut
  from a `vX.Y.Z` tag; the automated workflow builds, notarizes, publishes a GitHub
  Release, and opens the `appcast.xml` update PR. Merging that PR ships the in-app
  update. See [`docs/dev-setup.md`](docs/dev-setup.md#releasing) and
  [`docs/SPARKLE_UPDATE_FLOW.md`](docs/SPARKLE_UPDATE_FLOW.md) for the full flow.

If you're proposing a large or architectural change, please open an issue to discuss
it first so we can align before you invest the effort.

## Questions

For anything else, reach us at [support@bitwize.ai](mailto:support@bitwize.ai).
