[日本語](USER_GUIDE.ja.md) | **English**

# Draft Canvas — Getting Started Guide

> An introductory guide for anyone who wants to generate and edit AI images on a Mac.

---

## What is Draft Canvas?

Draft Canvas is an AI image generation and editing app for Mac.

Just type a prompt and images are generated instantly. You can edit them directly within the app — from background removal and upscaling to SVG conversion, all in one place. Open source (MIT) and free.

---

## Requirements

| Item | Details |
|------|---------|
| OS | macOS 14 Sonoma or later |
| Mac | Apple Silicon (M1 and later) and Intel both supported |
| Internet | Required for image generation and login. Background removal works offline |
| Also required | **Codex CLI** (the image generation engine). Login via Codex with a **ChatGPT Plus or higher subscription**. ChatGPT Free plan, OpenAI API Key, and Amazon Bedrock are not supported |

---

## Getting Started

### Step 1 — Install Codex CLI

Draft Canvas uses Codex CLI to generate images with AI. Install it first.

```bash
npm install -g @openai/codex
```

After installation, run `codex login` and sign in with a ChatGPT Plus or higher account.

### Step 2 — Download Draft Canvas

[**Download DraftCanvas.dmg**](https://github.com/5umm3r/draftcanvas/releases/latest/download/DraftCanvas.dmg) and copy the app to your Applications folder.

### Step 3 — Launch the App

On first launch, you will be asked to allow notifications. Allowing them lets you receive a notification when generation completes.

---

## Basic Usage

### Generating Images

1. Click the **"+"** button in the left sidebar to create a new project
2. Enter a prompt in the text area at the bottom of the screen (e.g., `a white cat drinking coffee, watercolor style`)
3. Adjust the aspect ratio and number of images as needed
4. Click the **"Generate"** button

Once generation is complete, image cards appear on the canvas.

**Tip — Prompt Enhancement:**  
After entering a prompt, press the ✨ button to have AI automatically enrich it with more detail. This often improves output quality.

**Tip — Translate prompt to English:**  
Enabling "Translate prompt to English" in Settings will translate your prompt to English before generation. This can reduce variability in results. Disabled by default.

### Editing Images

**Click to select** an image card on the canvas, and a column of circular action buttons will appear on the left side of the canvas.

| Button | What it does |
|--------|-------------|
| Re-edit | Generate a new image based on this one |
| Mask Edit | Paint a region with a brush and have AI modify or remove that area |
| Outpaint | Extend the scene beyond the image edges with AI |
| Remove Background | Remove the background offline using Apple's AI |
| Separate as Material | Extract material from the image and save it as a new item |
| Upscale | Upscale the image with AI |
| Vectorize | Convert the raster image to SVG |
| Duplicate | Duplicate the image and add it to the canvas |
| Show in Finder | Open the save location in Finder |
| Delete | Remove from the canvas |
| Export | Export in your chosen format (highlighted in accent color) |

### Mask Edit (Inpainting)

Use this when you want to change only a specific area.

1. Click to select the image → click "Mask Edit" in the left panel
2. Paint over the area you want to change with the brush
3. Choose a mode in the mask editor and generate:
   - **Edit**: Enter instructions in the prompt and click "Generate" (AI rewrites the painted area)
   - **Remove**: Click "Generate" with no prompt (AI fills the painted area with the surrounding background)

### Outpaint (Extending Beyond the Image)

Use this to expand the scene beyond the image boundaries.

1. Click to select the image → click "Outpaint" in the left panel
2. The editor opens — use the sliders to set how much to expand on each side
3. Choose how to proceed:
   - **"Expand and Generate"**: Start generation immediately using the original prompt
   - **"Enter Prompt and Expand"**: Close the editor, enter a prompt, then generate

The AI will naturally continue the existing scene into the expanded area.

### Sketch to Guide Composition

You can convey composition and layout to AI with a hand-drawn sketch — useful when a text prompt alone is not enough.

1. Click the **pencil icon** at the bottom of the prompt panel
2. The sketch editor opens — draw freely on the white canvas
3. Press **"Done" (⌘Return)** to attach it as a reference image, which will be passed as a composition hint during generation

**Sketch Editor Controls:**

| Action | Method |
|--------|--------|
| Change brush size | Slider (5–80 px) or `[` / `]` keys |
| Switch color | Color buttons in the toolbar or `1`–`5` keys (black, red, blue, green, purple) |
| Eraser | Eraser button or `e` key |
| Undo / Redo | ⌘Z / ⌘⇧Z |
| Clear | Clear button (confirmation dialog shown) |
| Cancel | Esc |
| Done | ⌘Return |
| Zoom / Pan | Pinch / Scroll |

You can click the attached sketch again to re-edit it. The reference sketch is shown in the "Sketch" section of the generation detail popover.

### Cropping Images

Trim an image to a specific area.

1. Click to select the image → click "Crop" in the left panel
2. The crop editor opens — drag to adjust the crop area
3. Click "Apply" to crop

### Importing Images

You can add local images to the canvas.

- **Drag & drop** PNG, JPEG, or WebP files directly onto the canvas
- Or use the menu to open an import dialog

Imported images are treated like generated images — you can edit, export, or use them as references for further generation.

### Exporting Images

1. Click to select the image → click "Export" in the left panel
2. Configure the format, quality, and resize options
3. Click "Export"

The first time, you will be prompted to choose a folder. Subsequent exports go to the same folder.

**Export Formats:**

| Format | Use case |
|--------|----------|
| PNG | High quality. For web and print |
| JPEG | When smaller file size is needed |
| WebP | For web. Higher compression and quality than JPEG. Quality: High (90) / Medium (75) / Low (50) |
| SVG | Only available after vectorizing. Scales without quality loss |
| TIFF | Lossless editing for print and editing software. LZW compression, DPI embedded |
| PDF | For document embedding. Choose lossless or medium/high quality JPEG compression |

For TIFF and PDF, you can select DPI from **72 / 150 / 300 / 600** (default: 300 dpi).

**Tip — Batch Export:**  
Select multiple images (marquee selection or ⌘-click), then click "Export". All selected images are exported together as a ZIP archive.

---

## Features

### AI Image Generation

| Setting | Description |
|---------|-------------|
| Prompt | Japanese or English, both work |
| Prompt language | Defaults to the input language as-is. Enable "Translate prompt to English" in Settings to translate before generation |
| Aspect ratio | Square / Portrait / Story / Landscape / Widescreen / Auto |
| Number of images | 1–8 |
| Concurrency | How many images to generate simultaneously (auto-reduced when rate limiting is detected) |
| Model | Choose from available models fetched from Codex |

### Prompt Templates

A template feature to streamline prompt entry. Open the template panel from the prompt panel and select a template to insert text into the prompt.

**Built-in categories (10 templates each):**

| Category | Examples |
|----------|---------|
| Art style | Watercolor, oil painting, pixel art, anime style, ukiyo-e, etc. |
| Photography | Portrait, macro, golden hour, film grain, etc. |
| Lighting & mood | Cinematic, neon, moody, fantasy, etc. |

Templates are displayed in a 4-column grid with thumbnails. You can also create and save your own custom templates ("My Templates").

### Prompt History

Previously used prompts are automatically recorded. Open the history panel from the prompt panel and select a past prompt to reuse it. Usage counts are also shown.

### Project Management

- Generated images are organized per project on the canvas
- Switch between multiple projects in the sidebar
- Add tags to search and organize projects
- **Filtering Projects**: Save search conditions to create cross-project views

### Settings

Open Settings from the app menu ("Draft Canvas" → "Settings..." or ⌘,).

| Setting | Description |
|---------|-------------|
| Appearance | Light / Dark / System |
| Language | Japanese / English / System. Changing language requires a restart |
| Translate prompt to English | Translates your prompt to English before generation. Default: off |
| Generation animation | Choose from 6 styles (Aurora, Grid Wave, Wireframe, Particle, Scanline, Mosaic) or Random |
| Completion sound | Sound played when generation finishes |
| Save folder | Default export destination |

### Log Window

Click "Logs" in the TopBar to open a separate log window showing Codex server communication logs. Useful for troubleshooting generation issues.

### Auto Update

Draft Canvas checks for updates automatically via Sparkle. You can also manually check from the app menu: "Draft Canvas" → "Check for Updates...".

### Usage Monitoring

Your 5-hour and weekly usage is always shown at the top of the screen, along with remaining percentage and estimated reset time.

Click the account icon to view your email address, plan, and Codex version. If not logged in, guidance for running `codex login` is shown. If you are on the ChatGPT Free plan, a warning about image generation being unavailable is displayed.

---

## FAQ

**Q. Generation fails / I get an error**  
A. Check that you are logged in to Codex. If not logged in, the account popover shows guidance to run `codex login`. Image generation is not available on the ChatGPT Free plan — Plus or higher is required.

**Q. Can I use the ChatGPT Free plan?**  
A. Image generation is not available on the Free plan. A ChatGPT Plus or higher subscription is required. OpenAI API Key and Amazon Bedrock are also not supported. Warnings are shown at the top of the prompt panel and in the account popover.

**Q. I changed a setting and was asked to restart**  
A. Changing the display language requires a restart. Click the "Restart" button in the settings alert and Draft Canvas will restart automatically. If generation or export is in progress, choose "Interrupt and Restart" (in-progress work will be discarded).

**Q. A dialog appeared when I tried to quit during generation or export**  
A. When image generation or export is in progress, the app blocks quitting and shows a confirmation dialog. Choose "Quit" to cancel the in-progress work and exit, or "Cancel" to stop the quit and continue working.

**Q. Are image quality and available models determined by the Draft Canvas version?**  
A. No. Image generation is delegated to Codex, so **available models, image quality, and resolution depend on the Codex version**. This is independent of Draft Canvas updates — updating Codex alone may change the available models and generation quality.

**Q. Does background removal work offline?**  
A. Yes. Background removal runs entirely on your Mac. No internet connection is needed.

**Q. Where are generated images saved?**  
A. They are automatically saved to `~/Library/Application Support/Draft Canvas/`. You can export them to any folder of your choice.

---

## License

Draft Canvas is open source (MIT License) and free.

| Item | Details |
|------|---------|
| Price | Free |
| License | MIT |
| Commercial use | Allowed |

If you'd like to support development, visit [GitHub Sponsors](https://github.com/sponsors/5umm3r).
