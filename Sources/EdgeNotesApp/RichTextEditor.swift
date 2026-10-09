import AppKit
import EdgeNotesCore
import SwiftUI

/// Resolves ⌘B / ⌘I / ⌘U itself: the app has no visible menu bar to carry them.
final class FormattingTextView: NSTextView {
    weak var controller: RichTextController?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, let controller {
            switch event.charactersIgnoringModifiers {
            case "b": MainActor.assumeIsolated { controller.toggleBold() }; return true
            case "i": MainActor.assumeIsolated { controller.toggleItalic() }; return true
            case "u": MainActor.assumeIsolated { controller.toggleUnderline() }; return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct RichTextEditor: NSViewRepresentable {
    let initialRTF: Data
    let paper: NSColor
    let controller: RichTextController
    let onChange: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let textView = FormattingTextView(frame: .zero)
        textView.controller = controller
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView

        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        // Templates often hold code or literal quotes; never "fix" them.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        // Fixed light appearance: stored colors must mean the same in every destination.
        textView.appearance = NSAppearance(named: .aqua)
        textView.drawsBackground = true
        textView.backgroundColor = paper

        textView.textStorage?.setAttributedString(RichText.attributedString(fromRTF: initialRTF))
        textView.typingAttributes = [.font: RichTextController.defaultFont]
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        controller.textView = textView
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        (scroll.documentView as? NSTextView)?.backgroundColor = paper
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (Data) -> Void

        init(onChange: @escaping (Data) -> Void) {
            self.onChange = onChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let storage = textView.textStorage else { return }
            onChange(RichText.rtf(from: storage))
        }
    }
}
