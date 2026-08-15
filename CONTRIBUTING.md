# Contributing to ABPlayerKit

Thanks for your interest in contributing!

## Ground rules

- **All changes go through a pull request.** Direct pushes to `main` are blocked; every PR requires maintainer (@AppBoong) approval and green CI before merge.
- Open an issue first for anything non-trivial so the approach can be discussed before you invest time.

## Development

- Requirements: Xcode 16+, iOS 17+ simulator.
- Run the full test suite before opening a PR:
  ```bash
  xcodebuild -scheme ABPlayerKit-Package -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
  ```
- The build must be **zero-warning**; CI treats warnings as errors.
- Lint before opening a PR. CI runs `swiftlint lint --strict`, which promotes every warning to an error:
  ```bash
  swiftlint lint --strict
  ```
  CI pins the version in [`.swiftlint-version`](.swiftlint-version) — install that exact version locally, since a different one can disagree about what is a violation.

## Conventions

- Swift 6 language mode; no `MainActor.assumeIsolated`.
- Dependency injection via initializers and configuration structs; protocols only at test seams.
- Events flow through the observer + `ABObservationToken` pattern.
- Scenario-based tests with Swift Testing (`@Suite`/`@Test`).
- Commit messages: English [Conventional Commits](https://www.conventionalcommits.org) (`feat:`, `fix:`, `docs:`, `test:`, `chore:`, `style:`).
- Public API changes must be additive within a major version and documented in DocC + README + CHANGELOG.

## Reporting security issues

Please do not open public issues for security-sensitive reports — see [SECURITY.md](SECURITY.md).
