import Foundation

enum PromptFactory {
    // Codex CLI 0.144 以降、image_gen.imagegen ツールが deny_unknown_fields で
    // size/quality 等を拒否 → モデルが慣性で size を付与すると生成失敗する。
    // プロンプト先頭に強い制約を明記し、size 誤送信を抑止
    private static let toolConstraint = """
    STRICT TOOL SCHEMA: The image_gen.imagegen tool arguments accept ONLY these three JSON fields — { "prompt": string, "referenced_image_paths"?: string[], "num_last_images_to_include"?: number }. The tool uses deny_unknown_fields; adding ANY other key (size, quality, width, height, resolution, dimensions, aspect_ratio, style, format, model, background, transparent, etc.) will cause the call to fail immediately with a schema error. Encode all composition, orientation, size and style intent as natural language INSIDE the prompt string. Never emit a size or width/height parameter under any circumstances.
    """

    private static let rasterConstraint = """
    Generate the output using the image_gen tool as a real raster illustration.
    Do NOT substitute with SVG, HTML, CSS, or canvas drawings, and do NOT internally build a vector composition and then rasterize it. Draw as a genuine illustration/photograph with real texture, shading, and highlights.
    Do not include any letters, logos, or watermarks unless the user prompt explicitly requests them.
    """

    static func prompt(for request: GenerationRequest, jobIndex: Int, jobPrompt: String? = nil) -> String {
        return "\(toolConstraint)\n\n\(promptBody(for: request, jobIndex: jobIndex, jobPrompt: jobPrompt))"
    }

    private static func trailingConstraints(for request: GenerationRequest) -> [String] {
        switch request.outputStyle {
        case .raster:
            return [rasterConstraint, toolConstraint]
        case .vector:
            return [toolConstraint]
        }
    }

    private static func promptBody(for request: GenerationRequest, jobIndex: Int, jobPrompt: String? = nil) -> String {
        let trimmedJobPrompt = jobPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let perJobPrompt = (trimmedJobPrompt?.isEmpty == false) ? trimmedJobPrompt : nil

        if let editSource = request.editSource {
            let userInstructionLines: [String]
            if let perJobPrompt {
                userInstructionLines = ["User edit request: \(perJobPrompt)"]
            } else {
                userInstructionLines = [
                    "Original prompt: \(editSource.originalPrompt)",
                    "User edit request: \(request.prompt)"
                ]
            }

            if editSource.isInpainting && editSource.inpaintPurpose == .outpaint {
                let hasUserPrompt = !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && request.prompt != editSource.originalPrompt
                let fillInstruction: String
                if hasUserPrompt {
                    fillInstruction = "Fill the transparent edge regions according to the following user instruction:"
                } else {
                    fillInstruction = "Naturally extend the image background into the transparent edge regions, seamlessly continuing the existing scene."
                }
                return ([
                    "Edit the attached reference image for a local personal image creator app.",
                    "The reference image has transparent (alpha=0) regions at the edges indicating areas to be extended.",
                    "Use the image generation capability and return exactly one edited raster image result.",
                    fillInstruction,
                ] + (hasUserPrompt ? userInstructionLines : [
                    "Original image description: \(editSource.originalPrompt)"
                ]) + [
                    "Compose the image with \(request.aspectRatio.promptDescription).",
                    "Preserve all non-transparent parts of the image exactly as they are.",
                    "Return a fully opaque image with no transparency.",
                    "Do not write code. Do not ask clarifying questions.",
                ] + trailingConstraints(for: request)).joined(separator: "\n")
            }

            if editSource.isInpainting && editSource.inpaintPurpose == .remove {
                return ([
                    "Edit the attached reference image for a local personal image creator app.",
                    "The reference image has transparent (alpha=0) regions indicating areas to be removed.",
                    "Use the image generation capability and return exactly one edited raster image result.",
                    "Remove the object in the transparent area, naturally fill with surrounding background.",
                    "Original image description: \(editSource.originalPrompt)",
                    "Compose the image with \(request.aspectRatio.promptDescription).",
                    "Preserve all non-transparent parts of the image exactly as they are.",
                    "Return a fully opaque image with no transparency.",
                    "Do not write code. Do not ask clarifying questions.",
                ] + trailingConstraints(for: request)).joined(separator: "\n")
            }
            if editSource.isInpainting {
                return ([
                    "Edit the attached reference image for a local personal image creator app.",
                    "The reference image has transparent (alpha=0) regions indicating areas to be regenerated.",
                    "Use the image generation capability and return exactly one edited raster image result.",
                    "Fill in the transparent regions according to the following user instruction:",
                ] + userInstructionLines + [
                    "Compose the image with \(request.aspectRatio.promptDescription).",
                    "Variation number: \(jobIndex + 1).",
                    "Preserve all non-transparent parts of the image exactly as they are.",
                    "Only modify the transparent regions to match the user edit request.",
                    "Return a fully opaque image with no transparency.",
                    "Do not write code. Do not ask clarifying questions.",
                ] + trailingConstraints(for: request)).joined(separator: "\n")
            }
            return ([
                "Edit the attached reference image for a local personal image creator app.",
                "Use the image generation capability and return exactly one edited raster image result.",
            ] + userInstructionLines + [
                "Compose the image with \(request.aspectRatio.promptDescription).",
                "Variation number: \(jobIndex + 1).",
                "Preserve useful parts of the reference image unless the edit request says otherwise.",
                "A normal opaque image is acceptable.",
                "Do not write code. Do not ask clarifying questions.",
            ] + trailingConstraints(for: request)).joined(separator: "\n")
        }

        let promptLine = "User prompt: \(request.prompt)"

        if request.attachedImagePath != nil {
            if request.attachedImageKind == .sketch {
                return ([
                    "Generate exactly one high-quality raster image for a local personal image creator app.",
                    "The attached image is a rough hand-drawn sketch used only as a compositional guide.",
                    "Use the sketch to understand the intended layout, placement, and rough color regions of the scene.",
                    "Do NOT reproduce the sketch literally. Do NOT carry over white areas as empty space or background.",
                    "Generate a fully detailed, polished scene that matches the user's prompt, with composition guided by the sketch.",
                    "Use the image generation capability and return the generated image result.",
                    promptLine,
                    "Compose the image with \(request.aspectRatio.promptDescription).",
                    "Variation number: \(jobIndex + 1).",
                    "A normal opaque image is acceptable.",
                    "Do not write code. Do not ask clarifying questions.",
                ] + trailingConstraints(for: request)).joined(separator: "\n")
            }
            return ([
                "Generate exactly one high-quality raster image for a local personal image creator app.",
                "Use the attached reference image as visual guidance.",
                "Use the image generation capability and return the generated image result.",
                promptLine,
                "Compose the image with \(request.aspectRatio.promptDescription).",
                "Variation number: \(jobIndex + 1).",
                "A normal opaque image is acceptable.",
                "Do not write code. Do not ask clarifying questions.",
            ] + trailingConstraints(for: request)).joined(separator: "\n")
        }

        return ([
            "Generate exactly one high-quality raster image for a local personal image creator app.",
            "Use the image generation capability and return the generated image result.",
            promptLine,
            "Compose the image with \(request.aspectRatio.promptDescription).",
            "Variation number: \(jobIndex + 1).",
            "A normal opaque image is acceptable.",
            "Do not write code. Do not ask clarifying questions.",
        ] + trailingConstraints(for: request)).joined(separator: "\n")
    }

}
