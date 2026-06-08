[日本語](CONTRIBUTING.md) | **English**

# Contributing

Thank you for your interest in contributing to Draft Canvas.

## Issues

Report bugs or suggest features via [Issues](https://github.com/5umm3r/draftcanvas/issues).

- Bug reports: include steps to reproduce, your macOS version, and any relevant logs (copy from the log window)
- Feature requests: describe your use case and the behavior you expect

## Pull Requests

1. Create a feature branch off `dev`
2. Commit using [Conventional Commits](https://www.conventionalcommits.org/) format (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`)
3. Commit messages should be written in Japanese
4. Add tests where appropriate and ensure existing tests pass
5. Open a pull request

## Building

```bash
# Build the app
xcodebuild -scheme DraftCanvas -destination 'platform=macOS' \
  SYMROOT=_build OBJROOT=_build/obj build

# Run tests
xcodebuild -scheme DraftCanvas -destination 'platform=macOS' \
  SYMROOT=_build OBJROOT=_build/obj test

# Rust FFI (only needed when changing vtracer-ffi/)
cd vtracer-ffi && ./build_universal.sh
```

## Coding Guidelines

- Swift / SwiftUI, MVVM pattern
- Use SF Symbols for icons
- No emojis
- Localization via xcstrings format
