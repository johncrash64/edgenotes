import AppKit
import EdgeNotesCore
import SwiftUI

/// Scroll view that answers only to the wheel and trackpad. Clicks fall through to
/// SwiftUI, so tapping the card still copies it, while scrolling works on demand.
final class WheelOnlyScrollView: NSScrollView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
    }
}

/// Read-only, scrollable rendering of a note body, with its fonts and colors.
/// It fills its frame edge to edge; the text is inset inside so it can scroll
/// right up to the card's borders.
struct RichTextPreview: NSViewRepresentable {
    let rtf: Data

    func makeNSView(context: Context) -> WheelOnlyScrollView {
        let scroll = WheelOnlyScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        // Thin overlay scroller that only shows while you scroll.
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .allowed

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        // Same fixed light appearance as the editor, so default text is dark.
        textView.appearance = NSAppearance(named: .aqua)
        // Small side inset; extra bottom room so the last line can scroll clear of the fade.
        textView.textContainerInset = NSSize(width: 10, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textStorage?.setAttributedString(RichText.attributedString(fromRTF: rtf))
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: WheelOnlyScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        let current = RichText.attributedString(fromRTF: rtf)
        if textView.attributedString() != current {
            textView.textStorage?.setAttributedString(current)
        }
    }
}
