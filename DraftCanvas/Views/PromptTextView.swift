import AppKit
import SwiftUI

final class FocusableTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?
    var onSubmit: (() -> Void)?
    var onFrameChange: (() -> Void)?
    var onPasteImage: (() -> Void)?
    var onDropFileURL: ((URL) -> Void)?
    var onDropNSImage: ((NSImage) -> Void)?
    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?

    private func acceptsImageDrag(_ pb: NSPasteboard) -> Bool {
        pb.types?.contains(.fileURL) == true ||
        pb.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptsImageDrag(sender.draggingPasteboard) else {
            return super.draggingEntered(sender)
        }
        onDragEntered?()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptsImageDrag(sender.draggingPasteboard) else {
            return super.draggingUpdated(sender)
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExited?()
        super.draggingExited(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        onDragExited?()
        if let urlStr = pb.string(forType: .fileURL), let url = URL(string: urlStr) {
            onDropFileURL?(url)
            return true
        }
        if let image = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            onDropNSImage?(image)
            return true
        }
        return super.performDragOperation(sender)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFrameChange),
            name: NSView.frameDidChangeNotification,
            object: self
        )
    }

    @objc private func handleFrameChange() {
        onFrameChange?()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocusChange?(true) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onFocusChange?(false) }
        return result
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36
        let isShiftHeld = event.modifierFlags.contains(.shift)
        if isReturn && !isShiftHeld && !hasMarkedText() {
            onSubmit?()
            return
        }
        let isCommandV = event.keyCode == 9 && event.modifierFlags.contains(.command)
        if isCommandV {
            let pb = NSPasteboard.general
            let hasText = pb.string(forType: .string) != nil
            let hasImage = pb.canReadObject(forClasses: [NSImage.self], options: nil)
            if hasImage && !hasText {
                onPasteImage?()
                return
            }
        }
        super.keyDown(with: event)
    }
}

struct PromptTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var dynamicHeight: CGFloat
    var maxHeight: CGFloat
    var onSubmit: (() -> Void)?
    var onSetupReplacer: ((@escaping (String) -> Void) -> Void)?
    var onPasteImage: (() -> Void)?
    var onDropFileURL: ((URL) -> Void)?
    var onDropNSImage: ((NSImage) -> Void)?
    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?
    var focusTrigger: Binding<Bool>? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let textView = FocusableTextView()
        textView.font = NSFont.systemFont(ofSize: 18)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.onFocusChange = { focused in
            context.coordinator.isFocused = focused
        }
        textView.onSubmit = { [weak coordinator = context.coordinator] in
            coordinator?.onSubmit?()
        }
        textView.onFrameChange = { [weak textView, weak coordinator = context.coordinator] in
            guard let textView else { return }
            coordinator?.recalculateHeight(for: textView)
        }
        textView.onPasteImage = { [weak coordinator = context.coordinator] in
            coordinator?.onPasteImage?()
        }
        textView.onDropFileURL = { [weak coordinator = context.coordinator] url in
            coordinator?.onDropFileURL?(url)
        }
        textView.onDropNSImage = { [weak coordinator = context.coordinator] image in
            coordinator?.onDropNSImage?(image)
        }
        textView.onDragEntered = { [weak coordinator = context.coordinator] in
            coordinator?.onDragEntered?()
        }
        textView.onDragExited = { [weak coordinator = context.coordinator] in
            coordinator?.onDragExited?()
        }

        context.coordinator.textViewRef = textView
        onSetupReplacer?({ [weak coordinator = context.coordinator] newText in
            coordinator?.replaceTextUndoably(newText)
        })

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]

        DispatchQueue.main.async {
            context.coordinator.recalculateHeight(for: textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if !textView.hasMarkedText(), textView.string != text {
            textView.string = text
            context.coordinator.recalculateHeight(for: textView)
        }
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onPasteImage = onPasteImage
        context.coordinator.onDropFileURL = onDropFileURL
        context.coordinator.onDropNSImage = onDropNSImage
        context.coordinator.onDragEntered = onDragEntered
        context.coordinator.onDragExited = onDragExited
        context.coordinator.maxHeight = maxHeight
        scrollView.hasVerticalScroller = dynamicHeight >= maxHeight
        if focusTrigger?.wrappedValue == true {
            if let tv = scrollView.documentView as? FocusableTextView, !tv.hasMarkedText() {
                scrollView.window?.makeFirstResponder(tv)
            }
            let trigger = focusTrigger
            DispatchQueue.main.async { trigger?.wrappedValue = false }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, dynamicHeight: $dynamicHeight, maxHeight: maxHeight, onSubmit: onSubmit, onPasteImage: onPasteImage)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool
        @Binding var dynamicHeight: CGFloat
        var maxHeight: CGFloat
        var onSubmit: (() -> Void)?
        var onPasteImage: (() -> Void)?
        var onDropFileURL: ((URL) -> Void)?
        var onDropNSImage: ((NSImage) -> Void)?
        var onDragEntered: (() -> Void)?
        var onDragExited: (() -> Void)?
        weak var textViewRef: FocusableTextView?

        init(text: Binding<String>, isFocused: Binding<Bool>, dynamicHeight: Binding<CGFloat>, maxHeight: CGFloat, onSubmit: (() -> Void)?, onPasteImage: (() -> Void)?) {
            _text = text
            _isFocused = isFocused
            _dynamicHeight = dynamicHeight
            self.maxHeight = maxHeight
            self.onSubmit = onSubmit
            self.onPasteImage = onPasteImage
        }

        func replaceTextUndoably(_ newText: String) {
            guard let tv = textViewRef else { return }
            tv.selectAll(nil)
            tv.insertText(newText, replacementRange: tv.selectedRange())
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            recalculateHeight(for: textView)
            if textView.hasMarkedText() { return }
            text = textView.string
        }

        func recalculateHeight(for textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let newHeight = ceil(usedRect.height + textView.textContainerInset.height * 2)
            guard abs(newHeight - dynamicHeight) > 0.5 else { return }
            dynamicHeight = newHeight
        }
    }
}
