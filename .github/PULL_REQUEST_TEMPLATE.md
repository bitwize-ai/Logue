<!--
Thanks for contributing to Logue! Please fill out the sections below.
See CONTRIBUTING.md for the standards enforced on every PR.
-->

## Summary

<!-- What does this PR change, and why? Link any related issue: "Closes #123". -->

## How was this verified?

<!-- Describe how you tested the change: built the app, ran which tests, manual steps. -->

- [ ] Builds cleanly (`xcodebuild build -project Logue.xcodeproj -scheme Logue -destination 'platform=macOS'`)
- [ ] Lints cleanly (`make lint`) — no new `swiftlint:disable` without justification
- [ ] Added/updated tests where it makes sense
- [ ] Ran `xcodegen generate` if I added/removed `.swift` files or changed `project.yml`

## Checklist

- [ ] My change keeps all AI inference and data processing **on-device** (no new network calls to third-party services without discussion).
- [ ] I did not commit secrets, API keys, or personal data.
- [ ] I read [CONTRIBUTING.md](../CONTRIBUTING.md) and followed the security/concurrency standards.

## Notes for reviewers

<!-- Anything the maintainers should pay special attention to. -->
