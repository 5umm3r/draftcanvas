[日本語](CONTRIBUTING.ja.md) | **English**

# Contributing

Thank you for contributing to Draft Canvas.

## Issue

For bug reports and feature requests, please use [Issues](https://github.com/5umm3r/draftcanvas/issues).

- Bug reports: Include steps to reproduce, macOS version, and logs (can be copied from the log window)
- Feature requests: Describe the use case and expected behavior

## Pull Request

1. Create a feature branch from `dev`
2. Commit using [Conventional Commits](https://www.conventionalcommits.org/) format (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`)
3. Commit messages in Japanese
4. Add tests and confirm existing tests pass
5. Open a PR

## Build

```bash
# Build the app
xcodebuild -scheme DraftCanvas -destination 'platform=macOS' \
  SYMROOT=_build OBJROOT=_build/obj build

# Run tests
xcodebuild -scheme DraftCanvas -destination 'platform=macOS' \
  SYMROOT=_build OBJROOT=_build/obj test

# Rust FFI (only when vtracer-ffi/ changes)
cd vtracer-ffi && ./build_universal.sh
```

## Coding Conventions

- Swift / SwiftUI, MVVM pattern
- Use SF Symbols for icons
- No emoji
- Localization in xcstrings format
