import AppKit

/// Bridges SwiftUI toolbar buttons to the NSTextView selection.
@MainActor
public final class RichTextController {
    public init() {}

    public weak var textView: NSTextView?

    public static let defaultFont = NSFont.systemFont(ofSize: 14)

    public func toggleBold() { toggle(.boldFontMask) }
    public func toggleItalic() { toggle(.italicFontMask) }

    public func setFamily(_ family: String?) {
        let manager = NSFontManager.shared
        modifyFonts { font in
            if let family {
                return manager.convert(font, toFamily: family)
            }
            // The system font has no stable family name; rebuild it and carry traits over.
            var system = NSFont.systemFont(ofSize: font.pointSize)
            let traits = manager.traits(of: font)
            if traits.contains(.boldFontMask) { system = manager.convert(system, toHaveTrait: .boldFontMask) }
            if traits.contains(.italicFontMask) { system = manager.convert(system, toHaveTrait: .italicFontMask) }
            return system
        }
    }

    public func setSize(_ size: CGFloat) {
        modifyFonts { NSFontManager.shared.convert($0, toSize: size) }
    }

    public func toggleUnderline() {
        guard let textView else { return }
        let range = textView.selectedRange()
        let current = (attribute(.underlineStyle, in: textView) as? Int) ?? 0
        let next: Int? = current == 0 ? NSUnderlineStyle.single.rawValue : nil
        setAttribute(.underlineStyle, value: next, in: textView, range: range)
    }

    /// `nil` removes the color so the destination app's default applies.
    public func setColor(_ color: NSColor?) {
        guard let textView else { return }
        setAttribute(.foregroundColor, value: color, in: textView, range: textView.selectedRange())
    }

    // MARK: - Private

    private func toggle(_ trait: NSFontTraitMask) {
        guard let textView else { return }
        let manager = NSFontManager.shared
        let current = (attribute(.font, in: textView) as? NSFont) ?? Self.defaultFont
        let isActive = manager.traits(of: current).contains(trait)
        modifyFonts { font in
            isActive
                ? manager.convert(font, toNotHaveTrait: trait)
                : manager.convert(font, toHaveTrait: trait)
        }
    }

    /// Attribute at the selection start, or in the typing attributes when the caret is collapsed.
    private func attribute(_ key: NSAttributedString.Key, in textView: NSTextView) -> Any? {
        let range = textView.selectedRange()
        if range.length == 0 { return textView.typingAttributes[key] }
        return textView.textStorage?.attribute(key, at: range.location, effectiveRange: nil)
    }

    private func modifyFonts(_ transform: (NSFont) -> NSFont) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()

        if range.length == 0 {
            var attributes = textView.typingAttributes
            let font = (attributes[.font] as? NSFont) ?? Self.defaultFont
            attributes[.font] = transform(font)
            textView.typingAttributes = attributes
            return
        }

        var runs: [(NSRange, NSFont)] = []
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            runs.append((subrange, (value as? NSFont) ?? Self.defaultFont))
        }
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        for (subrange, font) in runs {
            storage.addAttribute(.font, value: transform(font), range: subrange)
        }
        storage.endEditing()
        textView.didChangeText()
        textView.window?.makeFirstResponder(textView)
    }

    private func setAttribute(_ key: NSAttributedString.Key, value: Any?, in textView: NSTextView, range: NSRange) {
        guard let storage = textView.textStorage else { return }

        if range.length == 0 {
            var attributes = textView.typingAttributes
            attributes[key] = value  // assigning nil removes the key
            textView.typingAttributes = attributes
            return
        }

        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        if let value {
            storage.addAttribute(key, value: value, range: range)
        } else {
            storage.removeAttribute(key, range: range)
        }
        storage.endEditing()
        textView.didChangeText()
        textView.window?.makeFirstResponder(textView)
    }
}
