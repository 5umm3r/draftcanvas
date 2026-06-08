[日本語](USER_GUIDE.md) | **English**

# Draft Canvas — Getting Started Guide

> An introductory guide for anyone who wants to generate and edit AI images on a Mac.

---

## What is Draft Canvas?

Draft Canvas is an AI image generation and editing app for Mac.

Just type a prompt and images are generated instantly. You can edit them directly inside the app — remove backgrounds, upscale resolution, and convert to SVG, all in one place. Open source (MIT) and free.

---

## System Requirements

| Item | Details |
|------|---------|
| OS | macOS 14 Sonoma or later |
| Mac | Apple Silicon (M1 or later) and Intel both supported |
| Internet | Required for image generation and login. Background removal works offline |
| Also required | **Codex CLI** (the image generation engine). You must log in via Codex with a **ChatGPT Plus or higher subscription**. ChatGPT Free plan, OpenAI API Key, and Amazon Bedrock are not supported |

---

## Getting Started

### Step 1 — Install Codex CLI

Draft Canvas uses Codex CLI to generate images with AI. Install it first.

```bash
npm install -g @openai/codex
```

After installation, run `codex login` and sign in with a ChatGPT Plus or higher account.

### Step 2 — Download Draft Canvas

Get the latest `.dmg` from the [Releases](https://github.com/5umm3r/draftcanvas/releases) page and copy the app to your Applications folder.

### Step 3 — Launch the App

On first launch, you will be asked to allow notifications. Allowing them lets you receive a notification when image generation completes.

---

## Basic Usage

### Generating Images

1. Click the **"+"** button in the left sidebar to create a new project
2. Enter a prompt in the text area at the bottom of the screen (e.g., `a white cat drinking coffee, watercolor style`)
3. Adjust the aspect ratio and number of images to generate as needed
4. Click the **"Generate"** button

When generation is complete, image cards appear on the canvas.

**Tip — Prompt Enhancement:**  
After entering a prompt, click the ✨ button to have AI automatically fill in more detailed descriptions. This often improves the quality of results.

**Tip — Translate prompt to English:**  
Enabling "Translate prompt to English" in Settings will translate your input into English before generating. This can reduce variation in results. Disabled by default.

### Editing Images

**Click to select** an image card on the canvas, and a column of circular action buttons will appear on the left side of the canvas.

| Button | What it does |
|--------|-------------|
| Re-edit | Generate a new image based on this one |
| Mask Edit | Paint a region with a brush, then have AI modify or remove that area |
| Outpaint | Extend the image outward with AI to naturally continue the scene |
| Remove Background | Remove the background offline using Apple AI |
| Extract as Material | Extract content from the image and save it as a new item |
| Upscale | Upscale resolution with AI |
| Vectorize | Convert the raster image to SVG |
| Duplicate | Duplicate the image and add it to the canvas |
| Show in Finder | Open the file's location in Finder |
| Delete | Remove from the canvas |
| Export | Save in your chosen format (highlighted in accent color) |

### Mask Editing (Inpainting)

Use this when you want to change only a specific part of an image.

1. Click to select the image, then click "Mask Edit" in the left panel
2. Paint over the area you want to change with the brush
3. Select a mode in the mask editor and generate:
   - **Edit**: Enter instructions in the prompt and click "Generate" (AI rewrites the painted area)
   - **Remove**: Just click "Generate" (AI fills the painted area with background content naturally)

### Outpainting (Extending the Image)

Use this when you want to expand the scene beyond the edges of an image.

1. Click to select the image, then click "Outpaint" in the left panel
2. The editor opens — use the sliders to set how much to expand in each direction (top, bottom, left, right)
3. Choose how to proceed:
   - **"Expand and Generate"**: Start generating immediately using the original prompt
   - **"Enter Prompt and Expand"**: Close the editor, enter a new prompt, then generate

The generated image will naturally continue the existing scene.

### Sketching a Rough Layout

When a prompt alone is not enough to convey the composition or layout you have in mind, you can communicate it to AI with a hand-drawn sketch.

1. Click the **pencil icon** at the bottom of the prompt panel
2. The sketch editor opens. Draw freely on the white canvas
3. Press **"Done" (Command-Return)** to attach it as a reference image, which is passed to the AI as a composition hint during generation

**Sketch Editor Controls:**

| Action | How |
|--------|-----|
| Change brush size | Slider (5–80 px) or `[` / `]` keys |
| Switch color | Color buttons in the toolbar or keys `1`–`5` (black, red, blue, green, purple) |
| Eraser | Eraser button or `e` key |
| Undo / Redo | Command-Z / Command-Shift-Z |
| Clear | Clear button (shows a confirmation dialog) |
| Cancel | Esc |
| Done | Command-Return |
| Zoom / Pan | Pinch / Scroll |

You can click an attached sketch again to re-edit it. The sketch appears as a "Rough" section in the generation detail popover.

### Exporting Images

1. Click to select the image, then click "Export" in the left panel
2. Configure the format, quality, and resize settings
3. Click "Export"

The first time you export, a folder selection dialog appears. Subsequent exports save to the same folder.

**Export Formats:**

| Format | Best for |
|--------|---------|
| PNG | High quality. Web and print |
| JPEG | Smaller file sizes |
| WebP | Web use. Higher compression and quality than JPEG. Quality: High (90) / Medium (75) / Low (50) |
| SVG | Only available after vectorizing. Scales without quality loss |
| TIFF | Lossless editing in print and design software. LZW compression, DPI embedded |
| PDF | Embedding in documents. Choose lossless or medium/high quality JPEG compression |

For TIFF and PDF, you can select DPI from **72 / 150 / 300 / 600** (default: 300 dpi).

---

## Features

### AI Image Generation

| Setting | Description |
|---------|-------------|
| Prompt | Japanese or English both work |
| Prompt language | By default, the input language is used as-is. Enable "Translate prompt to English" in Settings to translate before generating |
| Aspect ratio | Square / Portrait / Story / Landscape / Widescreen / Auto |
| Number of images | 1–8 |
| Parallelism | How many images to generate simultaneously (automatically reduced when rate limiting is detected) |
| Model | Select from available models retrieved from Codex |

### Prompt Templates

A template feature to speed up prompt entry. Open the template panel from the prompt panel, select a template, and its text is inserted into the prompt field.

**Built-in categories (10 templates each):**

| Category | Examples |
|----------|---------|
| Art style | Watercolor, oil painting, pixel art, anime, ukiyo-e, and more |
| Photography & camera | Portrait, macro, golden hour, film grain, and more |
| Lighting & mood | Cinematic, neon, moody, fantasy, and more |

Templates are displayed in a 4-column grid with thumbnails. You can also create and save your own custom templates ("My Templates").

### Prompt History

Previously used prompts are recorded automatically. Open the history panel from the prompt panel to reuse past prompts. Usage counts are displayed as well.

### Project Management

- Generated images are organized by project on the canvas
- Switch between multiple projects from the sidebar
- Add tags to search and organize projects
- **Filtered Projects**: Save search criteria to create cross-project views

### Checking Usage

Your 5-hour and weekly usage is always shown at the top of the screen. You can see your remaining percentage and estimated reset time.

Click the account icon to view your email address, plan, and Codex version. If you are not logged in, guidance for running `codex login` is shown. If you are on the ChatGPT Free plan, a warning that image generation is unavailable is displayed.

---

## FAQ

**Q. Generation fails / I get an error**  
A. Check that you are logged in to Codex. If not logged in, the account popover will show guidance to run `codex login`. Image generation is not available on the ChatGPT Free plan — Plus or higher is required.

**Q. Can I use it with the ChatGPT Free plan?**  
A. Image generation is not available. A ChatGPT Plus or higher subscription is required. OpenAI API Key and Amazon Bedrock are also not supported. Warnings are shown at the top of the prompt panel and in the account popover.

**Q. I changed a setting and was asked to restart**  
A. Changing the display language requires a restart. Click the "Restart" button in the alert on the Settings screen to automatically restart Draft Canvas. If generation or export is in progress, choose "Interrupt and Restart" (in-progress work will be discarded).

**Q. A dialog appeared when I tried to quit while generation or export was in progress**  
A. When image generation or export is in progress, the app blocks quitting and shows a confirmation dialog. Choose "Quit" to cancel the work and exit, or "Cancel" to stop the quit and continue working.

**Q. Are image quality and available models determined by the Draft Canvas version?**  
A. No. Because image generation is delegated to Codex, **the available models, image quality, and resolution depend on the Codex version**. This is independent of Draft Canvas updates — updating Codex alone may change which models are available and the quality of results.

**Q. Can background removal be used offline?**  
A. Yes. Background removal runs entirely on your Mac. No internet connection is required.

**Q. Where are generated images saved?**  
A. They are automatically saved inside `~/Library/Application Support/Draft Canvas/`. Use Export to save them to any folder of your choice.

---

## License

Draft Canvas is open source (MIT License) and free.

| Item | Details |
|------|---------|
| Price | Free |
| License | MIT |
| Commercial use | Allowed |

If you would like to support development, visit [GitHub Sponsors](https://github.com/sponsors/5umm3r).
