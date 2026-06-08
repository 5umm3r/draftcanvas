[日本語](README.md) | **English**

# Draft Canvas

A desktop app for generating and editing AI images on Mac. Generate images from text prompts, then manage inpainting, background removal, upscaling, and vectorization — all within a project-based canvas.

## Features

- **AI Image Generation** — Generate images from text prompts (via Codex CLI + OpenAI gpt-image)
- **Inpainting / Outpainting** — Partially regenerate or extend images using mask editing
- **Background Removal** — On-device processing powered by Vision API
- **Upscaling** — AI-powered high-resolution enhancement
- **Vectorization** — Convert raster images to SVG (vtracer)
- **Subject Extraction** — Auto-detect and crop objects within an image
- **Crop / Sketch** — Editing tools directly on the canvas
- **Project Management** — Organize images across multiple projects
- **Prompt Templates / History** — Save and reuse frequently used prompts

## Requirements

| Item | Requirement |
|------|-------------|
| OS | macOS 14 Sonoma or later |
| Architecture | Apple Silicon / Intel (Universal) |
| Required | [Codex CLI](https://github.com/openai/codex) (install separately) |
| Account | ChatGPT Plus subscription or higher |

## Installation

### Pre-built App

Download the latest `.dmg` from [Releases](https://github.com/5umm3r/draftcanvas/releases).

### Build from Source

```bash
# Clone the repository
git clone https://github.com/5umm3r/draftcanvas.git
cd draftcanvas

# Build the Rust FFI library (first time only)
cd vtracer-ffi
./build_universal.sh
cd ..

# Build the app
xcodebuild -scheme DraftCanvas -destination 'platform=macOS' \
  SYMROOT=_build OBJROOT=_build/obj build
```

**Build requirements:**
- Xcode 16+
- Rust toolchain (install via `rustup`)

## Usage

See [USER_GUIDE.md](USER_GUIDE.md) for detailed instructions.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## Sponsorship

Draft Canvas is open source and free to use. If you'd like to support development:

- [GitHub Sponsors](https://github.com/sponsors/5umm3r)
- [Polar](https://polar.sh/spade3)

## License

[MIT](LICENSE)
