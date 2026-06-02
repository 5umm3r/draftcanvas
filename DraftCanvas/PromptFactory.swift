import Foundation

enum PromptFactory {
    static func prompt(for request: GenerationRequest, jobIndex: Int, jobPrompt: String? = nil) -> String {
        let trimmedJobPrompt = jobPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let perJobPrompt = (trimmedJobPrompt?.isEmpty == false) ? trimmedJobPrompt : nil

        if let editSource = request.editSource {
            let userInstructionLines: [String]
            if let perJobPrompt {
                userInstructionLines = ["User edit request: \(perJobPrompt)"]
            } else if let normalizedBrief = request.normalizedGenerationBrief {
                userInstructionLines = ["Generation brief: \(normalizedBrief)"]
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
                    "Aspect ratio: \(request.aspectRatio.promptDescription).",
                    "Preserve all non-transparent parts of the image exactly as they are.",
                    "Return a fully opaque image with no transparency.",
                    "Do not write code. Do not ask clarifying questions."
                ]).joined(separator: "\n")
            }

            if editSource.isInpainting && editSource.inpaintPurpose == .remove {
                return [
                    "Edit the attached reference image for a local personal image creator app.",
                    "The reference image has transparent (alpha=0) regions indicating areas to be removed.",
                    "Use the image generation capability and return exactly one edited raster image result.",
                    "Remove the object in the transparent area, naturally fill with surrounding background.",
                    request.normalizedGenerationBrief.map { "Generation brief: \($0)" }
                        ?? "Original image description: \(editSource.originalPrompt)",
                    "Aspect ratio: \(request.aspectRatio.promptDescription).",
                    "Preserve all non-transparent parts of the image exactly as they are.",
                    "Return a fully opaque image with no transparency.",
                    "Do not write code. Do not ask clarifying questions."
                ].joined(separator: "\n")
            }
            if editSource.isInpainting {
                return ([
                    "Edit the attached reference image for a local personal image creator app.",
                    "The reference image has transparent (alpha=0) regions indicating areas to be regenerated.",
                    "Use the image generation capability and return exactly one edited raster image result.",
                    "Fill in the transparent regions according to the following user instruction:",
                ] + userInstructionLines + [
                    "Aspect ratio: \(request.aspectRatio.promptDescription).",
                    "Variation number: \(jobIndex + 1).",
                    "Preserve all non-transparent parts of the image exactly as they are.",
                    "Only modify the transparent regions to match the user edit request.",
                    "Return a fully opaque image with no transparency.",
                    "Do not write code. Do not ask clarifying questions."
                ]).joined(separator: "\n")
            }
            return ([
                "Edit the attached reference image for a local personal image creator app.",
                "Use the image generation capability and return exactly one edited raster image result.",
            ] + userInstructionLines + [
                "Aspect ratio: \(request.aspectRatio.promptDescription).",
                "Variation number: \(jobIndex + 1).",
                "Preserve useful parts of the reference image unless the edit request says otherwise.",
                "A normal opaque image is acceptable.",
                "Do not write code. Do not ask clarifying questions."
            ]).joined(separator: "\n")
        }

        let promptLine = request.normalizedGenerationBrief.map { "Generation brief: \($0)" }
            ?? "User prompt: \(request.prompt)"

        if request.attachedImagePath != nil {
            if request.attachedImageKind == .sketch {
                return [
                    "Generate exactly one high-quality raster image for a local personal image creator app.",
                    "The attached image is a rough hand-drawn sketch used only as a compositional guide.",
                    "Use the sketch to understand the intended layout, placement, and rough color regions of the scene.",
                    "Do NOT reproduce the sketch literally. Do NOT carry over white areas as empty space or background.",
                    "Generate a fully detailed, polished scene that matches the user's prompt, with composition guided by the sketch.",
                    "Use the image generation capability and return the generated image result.",
                    promptLine,
                    "Aspect ratio: \(request.aspectRatio.promptDescription).",
                    "Variation number: \(jobIndex + 1).",
                    "A normal opaque image is acceptable.",
                    "Do not write code. Do not ask clarifying questions."
                ].joined(separator: "\n")
            }
            return [
                "Generate exactly one high-quality raster image for a local personal image creator app.",
                "Use the attached reference image as visual guidance.",
                "Use the image generation capability and return the generated image result.",
                promptLine,
                "Aspect ratio: \(request.aspectRatio.promptDescription).",
                "Variation number: \(jobIndex + 1).",
                "A normal opaque image is acceptable.",
                "Do not write code. Do not ask clarifying questions."
            ].joined(separator: "\n")
        }

        return [
            "Generate exactly one high-quality raster image for a local personal image creator app.",
            "Use the image generation capability and return the generated image result.",
            promptLine,
            "Aspect ratio: \(request.aspectRatio.promptDescription).",
            "Variation number: \(jobIndex + 1).",
            "A normal opaque image is acceptable.",
            "Do not write code. Do not ask clarifying questions."
        ].joined(separator: "\n")
    }

    static func upscalePrompt(
        for item: ProjectItem,
        translateToEnglish: Bool = false,
        normalizedDescription: String? = nil
    ) -> String {
        let fallbackDescription = item.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "imported asset"
            : item.prompt
        let normalized = normalizedDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = translateToEnglish && normalized?.isEmpty == false
            ? normalized!
            : fallbackDescription
        let descriptionLabel = translateToEnglish && normalized?.isEmpty == false
            ? "Image brief"
            : "Original image description"
        return [
            "Upscale the attached reference image to a significantly higher resolution.",
            "Preserve the original composition, subject, style, and color palette exactly.",
            "Enhance fine details: textures, edges, fine lines, small features.",
            "Do not add, remove, or alter any objects.",
            "\(descriptionLabel): \(description)",
            "Aspect ratio: \(item.aspectRatio.promptDescription).",
            "A normal opaque image is acceptable.",
            "Do not write code. Do not ask clarifying questions."
        ].joined(separator: "\n")
    }
}
