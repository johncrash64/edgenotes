import AppKit
import EdgeNotesCore
import SwiftUI

/// Text view that ignores the mouse so SwiftUI gestures on the card still fire.
final class PassthroughTextView: NSTextView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Read-only rendering of a note body, with its fonts and colors.
struct RichTextPreview: NSViewRepresentable {
    let rtf: Data

    func makeNSView(context: Context) -> PassthroughTextView {
        let textView = PassthroughTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        // Same fixed light appearance as the editor, so default text is dark.
        textView.appearance = NSAppearance(named: .aqua)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.textStorage?.setAttributedString(RichText.attributedString(fromRTF: rtf))
        return textView
    }

    func updateNSView(_ textView: PassthroughTextView, context: Context) {
        let current = RichText.attributedString(fromRTF: rtf)
        if textView.attributedString() != current {
            textView.textStorage?.setAttributedString(current)
        }
    }
}
