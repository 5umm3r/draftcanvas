[日本語](README.ja.md) | **English**

# Draft Canvas

A macOS desktop app for AI image generation and editing. Generate images from text prompts and manage inpainting, background removal, upscaling, and vectorization — all organized in per-project canvases.

## Features

- **AI Image Generation** — Generate images from text prompts (via Codex CLI + OpenAI gpt-image)
- **Inpainting / Outpainting** — Partially regenerate or expand images using mask editing
- **Background Removal** — On-device processing via the Vision API
- **Upscaling** — AI-powered high-resolution enhancement
- **Vectorization** — Convert raster images to SVG (powered by vtracer)
- **Subject Extraction** — Automatically detect and crop objects within an image
- **Cropping / Sketch Tools** — In-canvas editing tools
- **Project Management** — Organize images across multiple projects
- **Prompt Templates / History** — Save and reuse frequently used prompts

## Requirements

| Item | Requirement |
|------|-------------|
| OS | macOS 14 Sonoma or later |
| Architecture | Apple Silicon and Intel |
| Required | [Codex CLI](https://github.com/openai/codex) (install separately) |
| Account | ChatGPT Plus or higher subscription |

## Installation

### Prebuilt App

[**Download DraftCanvas.dmg**](https://github.com/5umm3r/draftcanvas/releases/latest/download/DraftCanvas.dmg) — Download the latest release directly

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

**Build Requirements:**
- Xcode 16+
- Rust toolchain (install via `rustup`)

## Usage

See [USER_GUIDE.md](USER_GUIDE.md) for detailed instructions.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## Sponsors

Draft Canvas is open source and free to use. If you'd like to support development:

- [GitHub Sponsors](https://github.com/sponsors/5umm3r)
- [Polar](https://buy.polar.sh/polar_cl_fZgIt4TMaHLTt1ah2aYDWoI9BGoY2KEuTx5fC0G2ehc)

## License

[MIT](LICENSE)
