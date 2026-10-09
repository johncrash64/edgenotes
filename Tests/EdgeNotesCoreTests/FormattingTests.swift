import AppKit
import Testing

@testable import EdgeNotesCore

@MainActor
@Suite struct FormattingTests {
    private func makeEditor(_ text: String = "Hello world") -> (NSTextView, RichTextController) {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        textView.isRichText = true
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: text, attributes: [.font: RichTextController.defaultFont]
        ))
        let controller = RichTextController()
        controller.textView = textView
        return (textView, controller)
    }

    private func font(_ textView: NSTextView, at index: Int) -> NSFont? {
        textView.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont
    }

    private func isBold(_ font: NSFont?) -> Bool {
        font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false
    }

    @Test func boldAppliesOnlyToSelectionAndTogglesOff() {
        let (textView, controller) = makeEditor()
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        controller.toggleBold()
        #expect(isBold(font(textView, at: 0)))
        #expect(!isBold(font(textView, at: 6)), "text outside the selection stays regular")

        controller.toggleBold()
        #expect(!isBold(font(textView, at: 0)))
    }

    @Test func italicAppliesToSelection() {
        let (textView, controller) = makeEditor()
        textView.setSelectedRange(NSRange(location: 6, length: 5))
        controller.toggleItalic()
        let traits = font(textView, at: 6).map { NSFontManager.shared.traits(of: $0) }
        #expect(traits?.contains(.italicFontMask) == true)
    }

    @Test func sizeAndFamilyChange() {
        let (textView, controller) = makeEditor()
        textView.setSelectedRange(NSRange(location: 0, length: 11))

        controller.setSize(32)
        #expect(font(textView, at: 3)?.pointSize == 32)

        controller.setFamily("Menlo")
        #expect(font(textView, at: 3)?.familyName == "Menlo")
        #expect(font(textView, at: 3)?.pointSize == 32, "changing family keeps the size")
    }

    @Test func familyChangeKeepsBold() {
        let (textView, controller) = makeEditor()
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        controller.toggleBold()
        controller.setFamily("Georgia")
        #expect(font(textView, at: 0)?.familyName == "Georgia")
        #expect(isBold(font(textView, at: 0)))
    }

    @Test func colorSetsAndAutomaticRemoves() {
        let (textView, controller) = makeEditor()
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        controller.setColor(.red)
        let color = textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == .red)

        controller.setColor(nil)
        #expect(textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil)
    }

    @Test func underlineToggles() {
        let (textView, controller) = makeEditor()
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        controller.toggleUnderline()
        #expect(textView.textStorage?.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int == 1)
        controller.toggleUnderline()
        #expect(textView.textStorage?.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil)
    }

    @Test func collapsedCaretChangesTypingAttributesOnly() {
        let (textView, controller) = makeEditor()
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        textView.typingAttributes = [.font: RichTextController.defaultFont]

        controller.toggleBold()
        #expect(isBold(textView.typingAttributes[.font] as? NSFont))
        #expect(!isBold(font(textView, at: 0)), "existing text is untouched")
    }

    @Test func formattingSurvivesRTFRoundTrip() throws {
        let (textView, controller) = makeEditor()
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        controller.toggleBold()
        controller.setColor(.red)

        let storage = try #require(textView.textStorage)
        let restored = RichText.attributedString(fromRTF: RichText.rtf(from: storage))
        #expect(restored.string == "Hello world")
        #expect(isBold(restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont))
        #expect(!isBold(restored.attribute(.font, at: 7, effectiveRange: nil) as? NSFont))
        let red = restored.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(red?.usingColorSpace(.sRGB)?.redComponent ?? 0 > 0.9)
    }

    @Test func stateReflectsSelectionAndNotifies() {
        let (textView, controller) = makeEditor()
        var seen: [RichTextController.FormatState] = []
        controller.onStateChange = { seen.append($0) }

        textView.setSelectedRange(NSRange(location: 0, length: 5))
        controller.toggleBold()
        controller.setColor(.red)
        #expect(controller.state.bold)
        #expect(controller.state.color == .red)
        #expect(!seen.isEmpty)

        textView.setSelectedRange(NSRange(location: 6, length: 5))
        controller.refreshState()
        #expect(!controller.state.bold, "a different selection reports its own formatting")
        #expect(controller.state.color == nil)
        #expect(controller.state.family == "System")
        #expect(controller.state.size == 14)
    }
}
