[日本語](SPEC.md) | **English**

# Draft Canvas — Full Specification

> Audience: Users (features, system requirements, licensing) and developers (architecture, domain model, external dependencies, build)
>
> Updated: 2026-06-02  
> Branch: dev

---

## Table of Contents

1. [Overview](#1-overview)
2. [User-Facing Feature Specification](#2-user-facing-feature-specification)
   - 2.10 [Restart on Settings Change](#210-restart-on-settings-change)
   - 2.11 [Task Protection on Quit](#211-task-protection-on-quit)
   - 2.12 [Sketch (Rough Drawing)](#212-sketch-rough-drawing)
   - 2.13 [Aurora Animation (Generation Placeholder)](#213-aurora-animation-generation-placeholder)
   - 2.14 [Prompt Templates](#214-prompt-templates)
   - 2.15 [Prompt History](#215-prompt-history)
3. [License & Billing](#3-license--billing)
4. [Privacy & Terms of Use](#4-privacy--terms-of-use)
5. [Architecture](#5-architecture)
6. [Domain Model](#6-domain-model)
7. [External Dependencies](#7-external-dependencies)
8. [Persistence Layout](#8-persistence-layout)
9. [Build & Distribution](#9-build--distribution)
10. [Localization](#10-localization)
11. [References](#11-references)

---

## 1. Overview

### 1.1 Product Summary

Draft Canvas is an AI image generation and editing desktop application for macOS. It generates images from text prompts and manages post-processing operations — inpainting, background removal, upscaling, and vectorization — within a per-project canvas. Image generation is performed by launching Codex CLI as a subprocess in `app-server` mode and calling OpenAI's image generation API (gpt-image pre-2.0) via JSON-RPC over stdio. All processing runs locally on the Mac, with no subscription required.

Tagline: **"Simple, powerful image editing on Mac."**

### 1.2 Target Users

- Individual users who regularly generate and manage image assets on macOS
- Creators who want to leverage AI for web, print, or social media image production
- Commercial use is permitted within the bounds of the terms of use

### 1.3 System Requirements

| Item | Requirement |
|------|-------------|
| OS | macOS 14 Sonoma or later |
| Architecture | Apple Silicon (arm64) and Intel (x86_64) |
| Required Software | Codex CLI (installed separately) |
| Internet | Required for image generation and account authentication. Background removal and vectorization work offline |
| Supported Accounts | ChatGPT Plus subscription or higher (Free plan, OpenAI API Key, and Amazon Bedrock are not supported) |

---

## 2. User-Facing Feature Specification

### 2.1 AI Image Generation

Enter a text prompt and call gpt-image via the Codex App Server to generate images.

**Parameters:**

- **Prompt**: Free-form text (Japanese and English both supported)
- **Generation language**: Controlled by the "Translate prompt to English" toggle in Settings. Default `false` (preserves input language). When enabled, the image generation brief is normalized to English before being passed to Codex. Persisted as `@AppStorage("translateToEnglish")` Bool
- **count**: Number of images to generate. UI offers 1–8
- **concurrency**: Number of parallel executions. Must be ≤ count; acts as a semaphore
- **Aspect ratio**: Choose from the following

| Value | Ratio | Typical Use |
|-------|-------|-------------|
| Auto | auto | Model decides |
| Square | 1:1 | Social media posts |
| Portrait | 3:4 | Vertical orientation |
| Story | 9:16 | Instagram / TikTok |
| Landscape | 4:3 | General horizontal |
| Widescreen | 16:9 | Desktop wallpaper / video |

- **Reference image (attachment)**: Up to one image can be attached as a visual guide for generation
- **Model selection**: Available models are fetched dynamically from the Codex App Server's `model/list` endpoint
- **Reasoning Effort**: `low` / `medium` (default) / `high`

**Job management:**

Generation jobs are managed as `GenerationJob` instances. Status transitions follow `queued → running → succeeded / failed`. On failure, an error message and detailed log are recorded.

**Rate limiting and dynamic concurrency control:**

When a rate limit (API quota exceeded) is detected during generation, the following mechanism activates automatically.

- `RateLimitClassifier` (`CodexAppServerClient.swift`) parses the JSON-RPC error response and classifies whether the error is rate-limit-related
- `actor ConcurrencyController` (`GenerationCoordinator.swift`) automatically reduces concurrency upon detecting a rate limit, and generates a `RateLimitConfirmation` to present the user with a confirmation dialog
- The affected job's `hitRateLimitDuringRun` flag is set to `true` and recorded in the log
- If the user approves the reduction, generation continues. If they cancel, remaining jobs are marked as failed and generation ends

**Codex version dependency:**

Draft Canvas delegates all image generation execution to the Codex App Server. The list of available models, image quality, resolution, and processing capability all depend on **the installed version of Codex**. This is independent of Draft Canvas updates; updating Codex alone may change the available models and generation quality. Draft Canvas controls only the prompt, `reasoningEffort`, and model selection.

**Supported account types:**

Draft Canvas is exclusively for ChatGPT subscriptions (Plus or higher). OpenAI API Key and Amazon Bedrock are not supported.

| accountKind | Support Status |
|-------------|----------------|
| `.chatgpt` + Plus or higher | Supported (all features available) |
| `.chatgpt` + Free | Not supported (image generation blocked) |
| `.apiKey` | Not supported (warning shown in AccountPopover) |
| `.amazonBedrock` | Not supported (warning shown in AccountPopover) |
| `.unauthenticated` / `.unknown` | Treated as not logged in |

**ChatGPT Free plan restriction:**

When `accountKind == .chatgpt` and `planLabel.lowercased() == "free"`, generation is blocked (`CodexAccountUsageStatus.isChatGPTFreePlan`). The check runs at the top of `startGeneration()` and sets `pendingFreeAccountBlock = true` for an early return.

UI display in 3 places:

- A persistent warning bar at the top of the PromptPanel (`exclamationmark.triangle.fill` in orange)
- A `confirmationDialog` at the time of a generation attempt (title + message, OK only)
- A warning caption inside `AccountPopover`

No upgrade CTA link — text guidance only.

**API Key / Bedrock configuration:**

When `isUnsupportedAccountKind` (`accountKind == .apiKey || .amazonBedrock`) is `true`, a warning caption is shown in AccountPopover directing the user to log in with ChatGPT. Generation is not blocked (the Codex CLI side manages execution).

### 2.2 Image Editing

Perform AI editing using a previously generated or imported image as the base.

**Full edit (Edit):**

The original image is passed as a reference image, and a new image is generated according to the user's editing instruction (e.g., "Change the sky to a sunset"). Useful parts of the original image are retained.

**Inpainting (Inpaint):**

1. Click an image to select it → click "Mask & Edit" or "Mask & Remove" in the action panel on the left side of the canvas
2. Paint the mask area with the brush tool
3. Specify the edit mode (edit / remove) and then run generation

- **edit mode**: Generates content from the instruction text in the masked area (the transparent region is passed to Codex as the area to regenerate)
- **remove mode**: Fills the masked area's object with a natural background (no instruction text needed)

Mask files and composite images are saved in the `masks/` directory (`{itemID}_mask.png` / `{itemID}_composite.png`).

**Outpainting (Outpaint):**

Extends the area outside the image with AI, naturally continuing the existing scene.

1. Click an image to select it → click "Outpaint" in the action panel on the left side of the canvas
2. `OutpaintEditorSheet` opens; specify the expansion amount (in `OutpaintInsets`) for each of the four edges using sliders
3. Choose one of two execution methods:
   - **"Expand and Generate"**: Immediately generates using the original prompt + `reasoningEffort: "low"`
   - **"Enter Prompt and Expand"**: Closes the editor, returns to the prompt panel, and generates with a custom prompt

Internal processing: `OutpaintCompositor` places the original image at the center of an expanded canvas and generates two images — a composite with transparent regions and a black-and-white mask (white = area to generate, black = area to preserve). Maximum expansion size is 2048px. Reuses the existing inpainting pipeline as `InpaintPurpose.outpaint`.

**Related files:** `Editors/Outpaint/OutpaintEditorSheet.swift` / `Editors/Outpaint/OutpaintInsets.swift` / `OutpaintCompositor.swift` / `ViewModel/DraftCanvasViewModel+Outpaint.swift`

**Generation failure classification:**

When a generation job fails, the cause is stored in `GenerationJob.failureKind: GenerationFailureKind?`.

| Kind | Display Icon | Meaning |
|------|-------------|---------|
| `.rateLimited` | `bolt.slash` | API quota exceeded / parallel failure |
| `.timeout` | `clock.badge.exclamationmark` | Timeout (`DraftCanvasError.timeout`) |
| `.other` | `exclamationmark.triangle` | Other errors |

### 2.3 Prompt Enhancement

Pressing the "Enhance" button (in PromptPanel) automatically elaborates the current prompt using AI.

- If "Translate prompt to English" is enabled in Settings, output is in English; otherwise the input language is preserved
- Adds details on composition, color, lighting, atmosphere, texture, viewpoint, and art style
- Expands to 2–4 sentences without changing the original subject or intent
- Opens a new Codex thread to retrieve the enhanced prompt (asynchronous, with mutual exclusion)

### 2.4 Post-Processing Features

Post-processing includes:

#### Background Removal

Removes the background offline using Apple's Vision Framework. The processed image is overwritten in `items/` as a PNG, and the `isBackgroundRemoved = true` flag is set. A preview sheet (`BackgroundRemovalPreviewSheet`) lets you review the result before applying.

#### Upscaling

Passes the selected image as a reference to Codex and generates a higher-resolution version.

- Prompt: uses the original prompt (for imported images, treated as `"imported asset"`)
- An overlay is shown on the original canvas card during processing
- Upon completion, a new card is added to the canvas (the original image is retained)

#### Vectorization (SVG Conversion)

Converts PNG to vector format via the vtracer-ffi library. Conversion options (precision, speckle removal, corner threshold, etc.) are managed through `VectorizationOptions`. The resulting SVG is saved as `items/{itemID}.svg` and the `hasSVG = true` flag is set. A spinner is shown on the canvas card during processing.

**VectorizationOptions default values:**

| Parameter | Value | Meaning |
|-----------|-------|---------|
| colorPrecision | 6 | Color precision |
| filterSpeckle | 4 | Speckle removal |
| cornerThreshold | 60 | Corner detection threshold |
| lengthThreshold | 4.0 | Minimum path length |
| spliceThreshold | 45 | Splice threshold |
| layerDifference | 16 | Layer difference |
| mode | 0 (spline) | Conversion mode |

#### Material Extraction

Extracts materials and textures from the selected image and saves them as new project items (`MaterialExtractor` / `MaterialExtractionSheet`).

### 2.5 Canvas Operations

| Operation | Method |
|-----------|--------|
| Zoom in / out | Pinch gesture or Ctrl + scroll |
| Zoom control | Zoom control bar at the bottom right |
| Move item | Drag |
| Copy-move item | Option + drag |
| Multi-select | Marquee selection (drag to define area) or click |
| Deselect | Click on the canvas background |
| Expanded view | Double-click a canvas card (`ExpandedImageSheet`) |
| Action panel | Clicking an image reveals a vertical row of action buttons on the left side of the canvas (`canvasActionPanel`): re-edit, mask edit, remove, outpaint, background removal, material extraction, upscale, vectorize, duplicate, reveal in Finder, delete, and export (`isAccent: true` applies filled accent styling, placed at the bottom) |
| Auto-scroll | Automatically scrolls to the new card when generation completes (`CanvasAutoScroller`) |
| Sort | Select "Oldest first" or "Newest first" from the TopBar |

### 2.6 Project Management

**Sidebar entry types:**

| Type | Description |
|------|-------------|
| Project | A standard project — a collection of generated images |
| Filtering Project | A saved search query that displays items matching the specified criteria across all projects |
| All Images | Lists all items across all projects |
| Search | Automatically transitions when text is typed in the sidebar search box. 250ms debounce |

A project's display name is auto-generated from the first 20 characters of the initial generation prompt (`ProjectNaming.summarize`). When the user renames it manually, `isAutoNamed = false` is set.

**Operations on projects:**

- Create, delete, rename
- Favorite (`isFavorite`)
- Per-project model and ReasoningEffort settings
- Move items to another project

**Tags:**

Multiple tags can be assigned to an item. Tags are aggregated in a cache (`allTagsCache`) and can be used in searches and FilteringProject queries.

### 2.7 Export

**Export formats:**

| Format | Description |
|--------|-------------|
| PNG | Lossless. Optimization options available (fast compression / maximum compression [lossy]) |
| JPEG | Quality: High (98) / Medium (80) / Low (60) |
| WebP | Via `cwebp` binary. Quality: High (90) / Medium (75) / Low (50). Metadata is automatically stripped |
| SVG | Only selectable for vectorized items |
| TIFF | LZW compression (lossless, alpha preserved). DPI embedded |
| PDF | Single-page PDF. Compression: lossless (Flate) / jpegHigh (q=0.9) / jpegMedium (q=0.7) |

**DPI:**

`ExportDPI` (72 / 150 / 300 / 600) can be specified for TIFF and PDF only. Default is 300 dpi. Applied to `TIFFXResolution` / `TIFFYResolution` and PDF MediaBox (`px / dpi * 72`).

**Related files:**

`Export/TIFFEncoder.swift` / `Export/PDFEncoder.swift` / `Export/WebPEncoder.swift` / `Export/ExportSettings.swift` / `Export/ExportOptionsSheet.swift` / `Export/ExportOptionsViewModel.swift`

**Resize:**

Resize by specifying width and height is available (`ExportSettings.resizeEnabled`).

**File naming convention:**

Format: `{ProjectName}-{2-digit sequence number}.{extension}` (e.g., `sunset-beach-01.png`). Characters invalid in filenames are replaced with `_`, and names are truncated at 64 characters.

**Batch export:**

Multiple selected items can be exported together as a ZIP archive (`ZipExportPipeline`).

**Save destination:**

A folder selection dialog appears on the first use; subsequent exports use the same folder. The setting is stored in UserDefaults as a Security-Scoped Bookmark.

### 2.8 Import

Local PNG, JPEG, and WebP files can be loaded into the canvas by drag-and-drop or via a dialog (`DraftCanvasViewModel+CanvasImport`). Imported items have `isImported = true` set, and the prompt is an empty string.

### 2.9 Notifications and Usage Counters

**Completion notifications:**

A system notification is sent when generation completes (`UserNotifications`). Notification permission is requested at launch. The completion sound can be selected in Settings (`CompletionSoundOption.glass` is the default).

**Usage counters (Codex account integration):**

Usage pills (`usagePill`) for the 5-hour window and the weekly window are displayed in the TopBar. **Displayed only when `shouldShowUsagePills == true` (`accountKind == .chatgpt`)**. Hidden for API Key, Bedrock, and unauthenticated states. Each pill shows a `prefix` ("5h" or "weekly"), a lightning bolt, a `percentLabel` (remaining percentage; "-" when not yet fetched), a remaining-capacity progress bar, and `resetText`. Icons have been removed. Data types: `primaryUsagePrefix` / `primaryUsagePercentLabel` (and secondary equivalents).

The account button in the TopBar changes icon based on account state (authenticated: `person.crop.circle` / unauthenticated: `person.crop.circle.badge.minus` / fetch failed: `person.crop.circle.badge.exclamationmark`). Clicking it opens a detail popover showing:

**Authenticated:**
- Email address + plan display (`planDisplay`, e.g., "ChatGPT Plus")
- `arrow.clockwise` account re-fetch button (restarts the Codex app-server to re-fetch information)
- Codex version in the footer
- Warning caption shown for ChatGPT Free plan

**Unauthenticated:**
- "Not logged in" + guidance to run `codex login`
- "Retry" button when fetch fails

The refresh button in the TopBar (for updating account usage) is disabled during generation (`!generatingProjectIDs.isEmpty`).

The number of images to generate is selected in the PromptPanel. The "All Images" row in the sidebar displays a Capsule showing the total item count (`AllImagesRow`).

Counters are also tracked within the session and persisted to AppStorage (`session5hCount`, `sessionWeeklyCount`).

### 2.10 Restart on Settings Change

A restart of Draft Canvas is required only when the app's display language is changed.

**Restart implementation:**

`LocalizationManager.relaunch()` launches a new instance via `NSWorkspace.shared.openApplication(at:configuration:)` with `createsNewApplicationInstance = true`, then terminates the current one with `NSApp.terminate(nil)`.

**Restart alert in SettingsView:**

| State | Button | Behavior |
|-------|--------|----------|
| No in-progress work | "Restart" | Immediately calls relaunch |
| `hasInFlightWork == true` | "Interrupt and Restart" (destructive) | Calls `cancelInFlightWorkForRelaunch()` then relaunch |

`hasInFlightWork`: Aggregates the following to determine in-flight state: `generatingProjectIDs` / `vectorizingItemIDs` / `upscalingItemIDs` / `isEnhancingPrompt` / `importProgress` / `batchExportProgress` / `exportingProjectID` / `backgroundRemovalPreview` / `materialExtractionPreview` / `upscalePreview` / `inpaintingTarget`.

`cancelInFlightWorkForRelaunch()`: Cancels all Tasks with `cancel()` → resets all progress flags → calls `saveState()`.

**Task tracking dictionary (generation):** `generationTasks: [UUID(projectID): [UUID(runID): Task<Void, Never>]]` (nested dictionary). `vectorizationTasks` / `upscalingTasks` remain `[UUID: Task<Void, Never>]`. Each Task removes itself from the dictionary in a `defer` block upon completion.

`finishRun(runID:projectID:results:)` / `cancelProjectRuns(projectID:)` centrally manage parallel execution. The stop button during generation calls `cancelProjectRuns(projectID:)` (old label "Stop All" → "Stop").

**Sketch editor and `hasInFlightWork`:** Active sketch editor sessions are not included in `hasInFlightWork`. The sketch editor does not automatically close when the restart dialog triggered by a language change appears (no UI-side warning).

### 2.11 Task Protection on Quit

If the user attempts to quit the app while work is in progress, a confirmation dialog is shown to protect the operation (`AppDelegate.applicationShouldTerminate`).

**Protected operations (`hasProtectedInFlightWork`):**

- `generatingProjectIDs` is non-empty (image generation in progress)
- `exportingProjectID != nil` (export in progress)
- `batchExportProgress != nil` (batch export in progress)

**Quit flow:**

1. No protected operations → `.terminateNow` (quit immediately)
2. Protected operations exist → set `terminationRequested = true` → `.terminateLater` (waiting for UI confirmation)
3. User clicks "Quit" → `confirmTermination()` → cancel in-progress tasks → `reply(toApplicationShouldTerminate: true)`
4. User clicks "Cancel" → `cancelTermination()` → `reply(toApplicationShouldTerminate: false)`

**Cleanup on quit (`applicationWillTerminate`):** Runs `saveState()` + `stopServer()`.

> `hasProtectedInFlightWork` includes exports, but `hasInFlightWork` (used for the restart in §2.10) is a separate property that also includes vectorization, upscaling, inpainting, and more.

### 2.12 Sketch (Rough Drawing)

Opens an NSView-based sketch editor from the `scribble.variable` button at the bottom of the prompt panel, and passes a hand-drawn rough sketch on a white background as a reference image via `AttachmentKind.sketch` for generation. Disabled during re-editing (`editSource != nil`).

**Sketch editor specification (`SketchEditor.swift`):**

| Feature | Details |
|---------|---------|
| Brush size | 5–80px slider. Change with `[` / `]` keys |
| Color presets | Black, red, blue, green, purple (`CodableColor.presets`). Switch with keys `1`–`5` |
| Eraser | Toolbar button or `e` key |
| Undo / Redo | ⌘Z / ⌘⇧Z |
| Clear | Confirmation dialog shown |
| Cancel / Done | Esc / ⌘Return |
| Zoom / Pan | Pinch / scroll |
| Minimum window | 800×620 |
| Background | Checkerboard |

**Rendering (`SketchCompositor.swift`):**

`SketchCompositor.renderPNG` interpolates circles onto a white background and renders to PNG. The long edge is fixed at 1024px. `canvasPixelSize` is calculated from `aspectRatio` (`DraftCanvasViewModel+Sketch.swift`: `openSketchEditor()`).

**Persistence:**

| File | Path | Contents |
|------|------|---------|
| Attachment PNG | `attachments/<id>_sketch.png` | Editor output image |
| Stroke JSON | `attachments/<id>_strokes.json` | Stroke data (for re-editing) |
| Post-generation reference | `masks/<itemID>_sketch.png` | Saved by `ProjectStore.saveSketchSource`. Reflected in `ProjectItem.sketchSourcePath` |

`cleanupMaskFiles` also targets `<id>_sketch.png` for deletion.

**ViewModel API (`ViewModel/DraftCanvasViewModel+Sketch.swift`):**

- `openSketchEditor()` — Calculates `canvasPixelSize` from `aspectRatio` and launches the sheet
- `openSketchEditorForReedit(_:)` — Loads existing strokes for re-editing
- `applySketch(strokes:canvasPixelSize:existingID:)` — Renders to PNG → saves → applies attachment
- `loadSketchStrokes(for:)` — Restores stroke JSON

**UI:**

- When the prompt is collapsed: shows the `scribble.variable` icon when a sketch is attached
- `ItemDetailPopover`: Displays a "Sketch" section (120px height) showing the reference sketch used during generation

**License gate:** None (treated the same as an attached image).

### 2.13 Generation Placeholder Animation

`PlaceholderAnimationView(style:seed:)` inside `GenerationProgressView` is displayed as a placeholder for in-progress generation jobs. The display style can be selected in the "Animation" option in Settings. The `Random` option uses the generation job's `seed` to assign a specific style.

**Styles:**

| Style | View |
|-------|------|
| Aurora | `AuroraPlaceholderView` |
| Grid Wave | `GridWavePlaceholderView` |
| Wireframe | `WireframeRotationPlaceholderView` |
| Particle | `ParticleFlowPlaceholderView` |
| Scanline | `ScanlineSweepPlaceholderView` |
| Mosaic | `MosaicPulsePlaceholderView` |

**Reduce Motion (`@Environment(\.accessibilityReduceMotion)`):**

| State | Behavior |
|-------|---------|
| ON | Uses a static frame at `t=0` without `TimelineView`, with a `ProgressView()` overlay |
| OFF | Animates at 30fps using `TimelineView(.animation)` |

### 2.14 Prompt Templates

A template feature to assist with prompt input. Open the template panel (`PromptTemplatePanel`) from the PromptPanel and select a template to insert its text into the prompt.

**Categories (`PromptTemplateCategory`):**

| Category | Description | Template Count |
|---------|-------------|----------------|
| `.style` (Style & Art Style) | Watercolor, oil painting, pixel art, etc. | 10 |
| `.photo` (Photography & Camera) | Portrait, macro, golden hour, etc. | 10 |
| `.lighting` (Lighting & Mood) | Cinematic, neon, moody, etc. | 10 |
| `.user` (My Templates) | Custom templates created by the user | Variable |

**Panel UI:**

- Built-in categories: Displayed in a 4-column thumbnail grid (`LazyVGrid`). Each template has a thumbnail image (`template-{category}-{number}`)
- My Templates: List view. Templates can be created, edited, and deleted

**Persistence:** Only user templates (`isBuiltIn == false`) are saved to `prompt_templates.json` (`PromptTemplateStore`). Built-in templates are defined in code (`PromptTemplate.builtIns`).

**Related files:** `Models/PromptTemplate.swift` / `Stores/PromptTemplateStore.swift` / `Views/PromptTemplatePanel.swift` / `ViewModel/DraftCanvasViewModel+Templates.swift`

### 2.15 Prompt History

Records previously used prompts for reuse. Open the history panel (`PromptHistoryPanel`) from the PromptPanel and select an entry to restore its prompt text.

**Data model (`PromptHistoryEntry`):**

| Field | Type | Description |
|-------|------|-------------|
| `id` | `UUID` | Identifier |
| `promptText` | `String` | Prompt body |
| `useCount` | `Int` | Number of times used |
| `lastUsedAt` | `Date` | Date and time last used |

**Panel UI:** Displayed as cards. A delete button appears on hover; an "Apply" button sets the prompt. A "Delete All" button appears when there are 2 or more entries.

**Persistence:** Saved to `prompt_history.json` (`PromptHistoryStore`).

**Related files:** `Models/PromptHistoryEntry.swift` / `Stores/PromptHistoryStore.swift` / `Views/PromptHistoryPanel.swift` / `ViewModel/DraftCanvasViewModel+History.swift`

---

## 3. License

Draft Canvas is open source (MIT License) and free to use. All features are available without restriction.

| Item | Details |
|------|---------|
| License | MIT |
| Price | Free |
| Commercial use | Permitted |
| Sponsorship | [GitHub Sponsors](https://github.com/sponsors/5umm3r) / [Polar](https://buy.polar.sh/polar_cl_fZgIt4TMaHLTt1ah2aYDWoI9BGoY2KEuTx5fC0G2ehc) |

---

## 4. Privacy & Terms of Use

### 4.1 Data Collected

| Data | Collection Method | Storage Location |
|-------|---------|---------|
| Crash reports | Apple's standard crash reporting | Apple servers |

### 4.2 Third-Party Disclosure

Image data and prompt contents are sent to OpenAI via the Codex App Server. The privacy policy of your ChatGPT account applies.

### 4.3 Key Terms of Use

| Item | Details |
|------|------|
| Personal use | Permitted |
| Commercial use | Permitted |
| Redistribution / modification | Subject to MIT License |
| Warranty | Provided as-is; no liability |

---

## 5. Architecture

### 5.1 Overview

```
DraftCanvasApp.swift
├── DraftCanvasViewModel (@MainActor ObservableObject)
│   ├── ViewModel/DraftCanvasViewModel+Account.swift      — Codex account & usage
│   ├── ViewModel/DraftCanvasViewModel+Attachments.swift  — Attached image management
│   ├── ViewModel/DraftCanvasViewModel+CanvasImport.swift — Image import
│   ├── ViewModel/DraftCanvasViewModel+CanvasNavigation.swift — Canvas navigation
│   ├── ViewModel/DraftCanvasViewModel+Computed.swift     — Derived properties
│   ├── ViewModel/DraftCanvasViewModel+Crop.swift         — Cropping
│   ├── ViewModel/DraftCanvasViewModel+Export.swift       — Export
│   ├── ViewModel/DraftCanvasViewModel+FilteringProjects.swift — Filtering projects
│   ├── ViewModel/DraftCanvasViewModel+Generation.swift   — Generation loop
│   ├── ViewModel/DraftCanvasViewModel+History.swift      — Prompt history
│   ├── ViewModel/DraftCanvasViewModel+ItemActions.swift  — Item actions
│   ├── ViewModel/DraftCanvasViewModel+Items.swift        — Item CRUD
│   ├── ViewModel/DraftCanvasViewModel+MaterialExtract.swift — Material extraction
│   ├── ViewModel/DraftCanvasViewModel+Outpaint.swift     — Outpainting
│   ├── ViewModel/DraftCanvasViewModel+Projects.swift     — Project CRUD
│   ├── ViewModel/DraftCanvasViewModel+PromptEnhance.swift — Prompt enhancement
│   ├── ViewModel/DraftCanvasViewModel+Sketch.swift       — Sketch drawing
│   ├── ViewModel/DraftCanvasViewModel+Templates.swift    — Prompt templates
│   ├── ViewModel/DraftCanvasViewModel+Upscale.swift      — Upscaling
│   └── ViewModel/DraftCanvasViewModel+Vectorize.swift   — Vectorization
│
├── GenerationCoordinator (Sendable)
│   └── CodexGenerationRunner : GenerationRunning
│       └── CodexAppServerClient (JSON-RPC stdio)
│
├── ProjectStore (persistence)
│   └── ~/Library/Application Support/Draft Canvas/
│
├── LocalizationManager (language switching)
└── SparkleUpdaterController (auto-update)
```

### 5.2 Screen Layout

The main window uses a three-pane layout.

```
┌─────────────────────────────────────────────────────────────────┐
│  TopBar (ContentView+TopBar.swift)                              │
│  [Account Usage] [Logs] [Settings] [Sort] [Account]             │
├──────────────┬──────────────────────────────────────────────────┤
│              │                                                  │
│  Sidebar     │  Canvas Area (ContentView+Canvas.swift)          │
│  (ContentView│  · ProjectItem card grid                         │
│  +Sidebar)   │  · Marquee selection overlay                     │
│              │  · ErrorToast                                    │
│  · Projects  │  · Generating: GenerationProgressView            │
│  · Filtering │                                                  │
│  · All Images│                                                  │
│  · Search    │                                                  │
│              ├──────────────────────────────────────────────────┤
│              │  PromptPanel (ContentView+PromptPanel.swift)     │
│              │  · Prompt input (PromptTextView)                 │
│              │  · count / concurrency                          │
│              │  · Aspect ratio                                  │
│              │  · Attached images (AttachedImageThumbnail)      │
│              │  · Enhance / Generate buttons                    │
└──────────────┴──────────────────────────────────────────────────┘
```

**Separate windows:**

| Window ID | File | Size |
|-------------|---------|-------|
| `"logs"` | `Views/LogWindow.swift` | 760 x 520 |

> OSS credits are provided in the app's standard About panel (`Credits.rtf`), regenerated from `Resources/Licenses/*.txt` via `scripts/generate-credits.py`.

Modal sheets: `TrialExpiredView` / `LicenseSheet` / `BackgroundRemovalPreviewSheet` / `UpscalePreviewSheet` / `VectorizingOverlay` / `MaterialExtractionSheet` / `InpaintingMaskEditor` / `OutpaintEditorSheet` / `ExpandedImageSheet` / `ExportOptionsSheet` / `FilteringProjectCreationSheet`

`SettingsView` is registered as a `Settings` scene and opens from the app menu under "Settings..." (language, appearance, save location, sound).

### 5.3 Feature-to-File Mapping

| Feature | Primary Files |
|------|------------|
| JSON-RPC communication | `CodexAppServerClient.swift`, `JSONRPCCodec.swift` |
| Generation coordination | `GenerationCoordinator.swift` |
| Prompt construction | `GenerationCoordinator.swift` — `PromptFactory` |
| Vectorization | `ImageVectorizer.swift`, `vtracer-ffi/` |
| Background removal | `BackgroundRemover.swift` |
| Upscaling | `ImageUpscaler.swift` |
| SVG rasterization | `SVGRasterizer.swift` |
| Export | `Export/ExportPipeline.swift`, `Export/ZipExportPipeline.swift` |
| Export settings | `Export/ExportSettings.swift`, `Export/ExportOptionsViewModel.swift` |
| Image encoding | `Export/ImageEncoder.swift`, `Export/TIFFEncoder.swift`, `Export/PDFEncoder.swift` |
| Binary execution | `Export/BinaryRunner.swift` (pngquant / oxipng) |
| Language management | `Localization/LocalizationManager.swift` |
| Thumbnails | `CanvasThumbnailStore.swift` |
| Original image store | `CanvasOriginalImageStore.swift` |
| CanvasMetrics | `CanvasMetrics.swift` |
| OSS credits | `Resources/Credits.rtf` (regenerated via `scripts/generate-credits.py`) |
| Sketch editor | `SketchEditor.swift`, `SketchCompositor.swift`, `SketchModels.swift`, `ViewModel/DraftCanvasViewModel+Sketch.swift` |
| Outpainting | `Editors/Outpaint/OutpaintEditorSheet.swift`, `Editors/Outpaint/OutpaintInsets.swift`, `OutpaintCompositor.swift`, `ViewModel/DraftCanvasViewModel+Outpaint.swift` |
| Prompt templates | `Models/PromptTemplate.swift`, `Stores/PromptTemplateStore.swift`, `Views/PromptTemplatePanel.swift`, `ViewModel/DraftCanvasViewModel+Templates.swift` |
| Prompt history | `Models/PromptHistoryEntry.swift`, `Stores/PromptHistoryStore.swift`, `Views/PromptHistoryPanel.swift`, `ViewModel/DraftCanvasViewModel+History.swift` |
| Generation placeholders | `Views/PlaceholderAnimationView.swift`, `Views/GenerationProgressView.swift` |

---

## 6. Domain Model

Source: `DraftCanvas/Models.swift`

### 6.1 Project

```swift
struct Project: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var isAutoNamed: Bool        // true = auto-generated from the first 20 characters of the prompt
    let createdAt: Date
    var updatedAt: Date
    var model: String            // Codex model ID
    var reasoningEffort: String  // "low" | "medium" | "high"
    var isFavorite: Bool
}
```

### 6.2 ProjectItem

```swift
struct ProjectItem: Identifiable, Equatable, Codable {
    let id: UUID
    var projectID: UUID
    let prompt: String
    let revisedPrompt: String?      // Revised prompt returned by Codex
    let aspectRatio: GenerationAspectRatio
    let actualAspectRatio: CGFloat?
    let createdAt: Date
    let errorMessage: String?
    var editedFromItemID: UUID?     // The source item this was edited from
    let hasSVG: Bool
    let isBackgroundRemoved: Bool
    let isCropped: Bool
    let isImported: Bool
    var tags: [String]
    var sketchSourcePath: String?   // Reference sketch used during generation (relative path: masks/<id>_sketch.png)
    let modelName: String?          // Display name of the model used for generation
    let reasoningEffort: String?    // Reasoning effort level used during generation
    let generationDuration: TimeInterval?  // Time taken to generate, in seconds
}
```

Generation metadata (`modelName` / `reasoningEffort` / `generationDuration`) is recorded when generation completes and can be viewed in `ItemDetailPopover`.

File path: `{rootDirectory}/items/{id}.png` (SVG: `{id}.svg`)

### 6.3 GenerationJob

```swift
struct GenerationJob: Identifiable, Equatable {
    let id: UUID
    let index: Int
    var prompt: String
    var aspectRatio: GenerationAspectRatio
    var status: GenerationJobStatus   // .queued / .running / .succeeded / .failed
    var imageData: Data?
    var revisedPrompt: String?
    var logs: [String]
    var errorMessage: String?
    var hitRateLimitDuringRun: Bool   // Set to true when a rate limit is detected
    var isFreeAccountBlocked: Bool   // Blocked due to Free plan restrictions
    var failureKind: GenerationFailureKind?  // Classification of the failure reason
    var runID: UUID?                 // ID of the generation run this job belongs to
    var scheduledAt: Date            // Timestamp when the job was enqueued
}
```

Completed and failed jobs are immediately removed from `jobsByProject` (via `removeJob(id:from:)`). At the start of generation, `cleanupStaleJobs(for:)` performs a bulk removal of orphaned jobs that belong to inactive runs.

### 6.4 GenerationRequest

```swift
struct GenerationRequest: Equatable {
    var prompt: String
    var count: Int               // UI maximum: 4. Clamped to 1–24 via normalizedCount (server-side validation)
    var concurrency: Int         // After normalization: 1–count
    var aspectRatio: GenerationAspectRatio
    var editSource: GenerationEditSource?
    var attachedImagePath: String?
    var attachedImageKind: AttachmentKind  // Kind of attached image (.regular / .sketch)
    var model: String
    var reasoningEffort: String
    var translateToEnglish: Bool // Whether to translate the prompt to English before generation
    var normalizedPrompt: String?  // Cache of the translated prompt
}
```

### 6.5 GenerationEditSource

```swift
struct GenerationEditSource: Equatable {
    var projectItemID: UUID
    var filePath: String
    var originalPrompt: String
    var maskFilePath: String?
    var compositeFilePath: String?
    var inpaintPurpose: InpaintPurpose   // .edit / .remove / .outpaint
    
    var isInpainting: Bool { maskFilePath != nil }
    var isOutpainting: Bool { inpaintPurpose == .outpaint && maskFilePath != nil }
}
```

### 6.6 FilteringProject

```swift
struct FilteringProject: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var searchQuery: String
    let createdAt: Date
    var updatedAt: Date
}
```

### 6.7 SidebarSelection

```swift
enum SidebarSelection: Codable, Equatable, Hashable {
    case project(UUID)
    case filtering(UUID)
    case allImages
    case search          // Not persisted (falls back to .none on launch)
```swift
enum SidebarSelection: Codable, Equatable, Hashable {
    case project(UUID)
    case filtering(UUID)
    case allImages
    case search          // Not persisted (falls back to .none on launch)
    case none
}
```

### 6.8 ProjectStore.Snapshot

The unit of persistence. Used for JSON encoding/decoding to `projects.json`.

```swift
struct Snapshot: Codable {
    var projects: [Project]
    var items: [ProjectItem]
    var filteringProjects: [FilteringProject]
    var sidebarSelection: SidebarSelection
    var expandedSections: [String: Bool]
}
```

### 6.9 CodexModel

```swift
struct CodexModel: Identifiable, Equatable {
    let id: String
    let displayName: String
    let supportedReasoningEfforts: [String]
    let defaultReasoningEffort: String
    let isDefault: Bool
}
```

The list of available models is fetched dynamically from the Codex App Server's `model/list` endpoint. Model ratings (`ModelRating`) have been deprecated.

### 6.10 CodexAccountUsageStatus

```swift
struct CodexAccountUsageStatus: Equatable {
    var accountLabel: String
    var planLabel: String
    var primaryUsagePrefix: String       // 5-hour window identifier ("5h")
    var primaryUsagePercentLabel: String // Remaining quota percentage display ("-" or "XX%")
    var secondaryUsagePrefix: String     // Weekly window identifier ("weekly")
    var secondaryUsagePercentLabel: String
    var primaryUsageRemainingFraction: Double?
    var secondaryUsageRemainingFraction: Double?
    var accountEmail: String?
    var accountKind: AccountKind         // .chatgpt / .apiKey / .amazonBedrock / .unauthenticated / .unknown
    var primaryResetText: String?        // Relative display string such as "3 hours remaining"
    var secondaryResetText: String?
    var primaryResetDate: Date?
    var secondaryResetDate: Date?

    var isChatGPTFreePlan: Bool {        // accountKind == .chatgpt && planLabel == "free"
        accountKind == .chatgpt && planLabel.lowercased() == "free"
    }
}
```

### 6.11 ExportSettings

```swift
struct ExportSettings: Equatable {
    var format: ExportFormat             // .png / .jpeg / .webp / .svg / .tiff / .pdf
    var jpegQuality: JPEGQualityPreset   // .high98 / .mid80 / .low60
    var webpQuality: WebPQualityPreset   // .high90 / .mid75 / .low50
    var pngOptimize: Bool
    var pngLevel: PNGOptimizationLevel   // .fast / .max (lossy)
    var tiffCompression: TIFFCompression // .lzw (fixed)
    var pdfCompression: PDFImageCompression // .lossless / .jpegHigh / .jpegMedium
    var dpi: ExportDPI                   // .dpi72 / .dpi150 / .dpi300 / .dpi600
    var resizeEnabled: Bool
    var resizeWidth: Int
    var resizeHeight: Int
}
```

### 6.12 EntitlementStatus

```swift
enum EntitlementStatus: Equatable {
    case trial(daysLeft: Int)
    case licensed
    case expired
}
```

### 6.13 RateLimitConfirmation

A data structure for proposing concurrency reduction to the user when a rate limit is reached. Generated by `GenerationCoordinator` and passed to the UI.

```swift
struct RateLimitConfirmation: Identifiable {
    let id: UUID
    let remainingPercent: Int   // Remaining quota ratio (0-100)
    let concurrency: Int        // Recommended concurrency after reduction
    let resume: () -> Void      // Closure called when the user approves
}
```

### 6.14 GenerationFailureKind

```swift
enum GenerationFailureKind: String, Codable {
    case rateLimited   // API quota exceeded
    case timeout       // DraftCanvasError.timeout
    case other         // All other errors
}
```

### 6.15 AttachmentKind / SketchStroke / CodableColor

Source: `DraftCanvas/SketchModels.swift`

```swift
enum AttachmentKind: String, Codable, Equatable {
    case regular   // Standard reference image
    case sketch    // Rough sketch image
}

struct SketchStroke: Equatable, Codable {
    // Stroke coordinates, color, width, eraser flag, etc.
}

struct CodableColor: Equatable, Codable {
    // Codable wrapper for colors
    static let presets: [CodableColor]  // Black, red, blue, green, purple
}
```

### 6.16 ExportFormat (extended)

```swift
enum ExportFormat: String, CaseIterable, Codable {
    case png
    case jpeg
    case webp
    case svg
    case tiff
    case pdf
}

enum WebPQualityPreset: Int, CaseIterable, Codable {
    case high90 = 90
    case mid75 = 75
    case low50 = 50
}
```

### 6.17 ExportDPI / TIFFCompression / PDFImageCompression

Source: `DraftCanvas/Export/ExportSettings.swift`

```swift
enum ExportDPI: Int, CaseIterable {
    case dpi72 = 72
    case dpi150 = 150
    case dpi300 = 300   // Default
    case dpi600 = 600
}

enum TIFFCompression: String {
    case lzw   // kCGImagePropertyTIFFCompression=5 (lossless)
}

enum PDFImageCompression: String {
    case lossless    // CGDataConsumer + Flate (default)
    case jpegHigh    // JPEG q=0.9
    case jpegMedium  // JPEG q=0.7
}
```

---

## 7. External Dependencies

### 7.1 Codex App Server

**Launch:**

```bash
# When the codex binary exists at a specific path
{node} {codex} app-server --listen stdio://

# When available on PATH
/usr/bin/env codex app-server --listen stdio://
```

`CodexAppServerClient` launches a subprocess via `Process` and uses stdin/stdout as a JSON-RPC channel.

**JSON-RPC Methods (primary):**

| Method | Direction | Purpose |
|--------|-----------|---------|
| `initialize` | -> | Launch and negotiation (`clientInfo.name = "draftcanvas"`, `capabilities.experimentalApi: true`) |
| `thread/start` | -> | Start a new conversation thread. Passes model and reasoningEffort. Returns threadID |
| `turn/start` | -> | Execute image generation by passing threadID, prompt, and reference image paths |
| `model/list` | -> | Retrieve the list of available models |
| `account/read` | -> | Retrieve account type and plan information |
| `account/rateLimits/read` | -> | Retrieve rate limit information for 5-hour and weekly windows |

**Connection Management:**

- Launch is deferred (calls `start()` on the first generation or account check)
- `startupTask` ensures `start()` is only executed once even if called concurrently
- Thread-safe design based on `DispatchQueue`

### 7.2 vtracer-ffi (SVG Vectorization)

Called from Swift via a C function interface.

- Library: `vtracer-ffi/` directory (Rust FFI)
- Bridging header: `DraftCanvas-Bridging-Header.h`
- Key functions: `vtracer_convert(ptr, len, params, outPtr, outLen)` / `vtracer_free(ptr, len)`
- Conversion runs in the background via `Task.detached(priority: .userInitiated)`

### 7.3 pngquant / oxipng / cwebp (Image Optimization Binaries)

Binaries are bundled in `DraftCanvas/Resources/bin/` (arm64 + x86_64 fat binaries).

| Tool | Version | Behavior |
|------|---------|----------|
| pngquant | 3.0.4 | Lossy PNG compression (used with `PNGOptimizationLevel.max`) |
| oxipng | 10.1.1 | Lossless PNG optimization (used with `PNGOptimizationLevel.fast`) |
| cwebp | - | WebP encoding (`WebPEncoder` invokes it with `-q` / `-metadata none`. Timeout: 60 seconds) |

Dynamic dependencies are limited to `/usr/lib/` only (libz, libiconv, libSystem). No additional installation required.
Executed as subprocesses via `BinaryRunner`.

### 7.4 Sparkle (Auto-Update)

`SparkleUpdaterController` wraps `SPUStandardUpdaterController`, enabling "Check for Updates..." from the application menu.

### 7.5 Apple Vision (Background Removal)

`BackgroundRemover.swift` uses `VNGenerateForegroundInstanceMaskRequest` to remove backgrounds entirely on-device. No network connection required. Image data never leaves the device.

### 7.6 UserNotifications

Sends a system notification when generation completes. Permission is requested at launch via `requestNotificationPermission()`.

---

## 8. Persistence Layout

### 8.1 Application Support Directory

```
~/Library/Application Support/Draft Canvas/
├── projects.json          # Metadata (ProjectStore.Snapshot)
├── prompt_templates.json  # User-created templates (PromptTemplateStore)
├── prompt_history.json    # Prompt usage history (PromptHistoryStore)
├── items/
│   ├── {itemID}.png       # Generated or imported images
│   ├── {itemID}.jpg       # When imported as JPEG
│   └── {itemID}.svg       # Vectorized SVG
├── masks/
│   ├── {itemID}_mask.png      # Mask for inpainting
│   ├── {itemID}_composite.png # Mask-composited image (reference image for Codex)
│   └── {itemID}_sketch.png    # Reference sketch saved on successful generation (ProjectStore.saveSketchSource)
└── attachments/
    ├── {attachmentID}.png         # Standard attachment image
    ├── {attachmentID}_sketch.png  # Sketch attachment image (SketchCompositor output)
    └── {attachmentID}_strokes.json # Stroke data (for re-editing)
```

### 8.2 UserDefaults

| Key | Type | Description |
|-----|------|-------------|
| `appAppearance` | String | `"light"` / `"dark"` |
| `appLanguage` | String | `"ja"` / `"en"` / `"system"` (follows OS setting) |
| `canvasSortOrder` | String | `CanvasSortOrder` rawValue |
| `completionSound` | String | `CompletionSoundOption` rawValue |
| `totalGeneratedImages` | Int | Cumulative number of generated images |
| `session5hCount` | Int | In-session count for the 5-hour window |
| `sessionWeeklyCount` | Int | In-session count for the weekly window |
| `session5hResetEpoch` | Double | Reset epoch for the 5-hour window |
| `sessionWeeklyResetEpoch` | Double | Reset epoch for the weekly window |
| `exportFormat` | String | `ExportFormat` rawValue |
| `exportJPEGQuality` | Int | `JPEGQualityPreset` rawValue |
| `exportWebPQuality` | Int | `WebPQualityPreset` rawValue |
| `exportPNGOptimize` | Bool | PNG optimization enabled/disabled |
| `exportPNGLevel` | Int | `PNGOptimizationLevel` rawValue |
| `exportResizeEnabled` | Bool | Resize enabled/disabled |
| `exportResizeWidth` | Int | Resize width |
| `exportResizeHeight` | Int | Resize height |
| `exportDPI` | Int | `ExportDPI` rawValue (72 / 150 / 300 / 600) |
| `exportTIFFCompression` | String | `TIFFCompression` rawValue |
| `exportPDFCompression` | String | `PDFImageCompression` rawValue |
| `preferredSaveFolderBookmark` | Data | Security-Scoped Bookmark |

---

## 9. Build and Distribution

### 9.1 Build Command

```bash
xcodebuild -scheme DraftCanvas -destination 'platform=macOS' SYMROOT=_build OBJROOT=_build/obj build
```

**Rules:**

- `SYMROOT` is always `_build`; `OBJROOT` is always `_build/obj`
- Do not use `-derivedDataPath`
- If build artifacts are created at any other path, delete them immediately

### 9.2 Build Output

```
_build/Debug/DraftCanvas.app
```

### 9.3 External Binary Management (pngquant / oxipng)

Binaries are managed directly in git, already bundled in `DraftCanvas/Resources/bin/` (arm64 + x86_64 fat binaries).

**Binary update procedure:**

```bash
# oxipng
cargo install oxipng --root /tmp/oxipng-arm64 --target aarch64-apple-darwin
cargo install oxipng --root /tmp/oxipng-x86  --target x86_64-apple-darwin
lipo -create /tmp/oxipng-arm64/bin/oxipng /tmp/oxipng-x86/bin/oxipng \
     -output DraftCanvas/Resources/bin/oxipng

# pngquant
git clone --depth 1 https://github.com/kornelski/pngquant.git /tmp/pngquant
cd /tmp/pngquant && git submodule update --init
cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin
lipo -create target/aarch64-apple-darwin/release/pngquant \
             target/x86_64-apple-darwin/release/pngquant \
     -output /path/to/repo/DraftCanvas/Resources/bin/pngquant

chmod +x DraftCanvas/Resources/bin/oxipng DraftCanvas/Resources/bin/pngquant
```

---

## 10. Localization

Supported languages: **Japanese (ja)** / **English (en)**

`LocalizationManager.shared` manages the language for the entire app. The initial language is selected from the OS language settings and can be changed within the app. The setting is saved under the `appLanguage` key in `UserDefaults`.

All translated strings are managed centrally in `DraftCanvas/Localization/Localizable.xcstrings`.

UI strings use `String(localized:)` directly.

`AppLanguage` has three cases: `ja` / `en` / `system` (follows OS setting). The default initial value is `.system` (follows the OS language setting at launch). It can be changed from `SettingsView` and is saved under the `appLanguage` key in `UserDefaults`. A restart is required for language changes to take effect (see §2.10).

---

## 11. References

| Document | Path |
|----------|------|
| Project configuration (for Claude Code) | `CLAUDE.md` |
| Agent rules | `AGENTS.md` |
| Landing page | `lp/index.html` |
| Privacy policy (full text) | `lp/privacy.html` |
| Terms of service (full text) | `lp/terms.html` |
| External binary management workflow | `_docs/external-binaries-workflow.md` |
| Image generation model research (2026-05-09) | `_docs/画像生成モデル調査_2026-05-09.md` |
| Domain model implementation | `DraftCanvas/Models.swift` |
| Generation logic | `DraftCanvas/GenerationCoordinator.swift` |
| Codex communication client | `DraftCanvas/CodexAppServerClient.swift` |
| ViewModel (main) | `DraftCanvas/DraftCanvasViewModel.swift` |
| ViewModel extensions | `DraftCanvas/ViewModel/` |
| Editor implementation | `DraftCanvas/Editors/` |
| Store implementation | `DraftCanvas/Stores/` |
| View implementation | `DraftCanvas/Views/` |
| License implementation | `DraftCanvas/License/` |
| Export implementation | `DraftCanvas/Export/` |
