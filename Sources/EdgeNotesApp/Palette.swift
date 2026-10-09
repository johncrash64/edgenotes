import AppKit
import EdgeNotesCore
import SwiftUI

enum Palette {
    static func nsColor(_ color: NoteColor) -> NSColor {
        let c = color.rgb
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    static func color(_ color: NoteColor) -> Color {
        Color(nsColor: nsColor(color))
    }

    /// Light "paper" tinted by the note color. The editor is always light so the
    /// stored text colors are the ones the destination app will receive.
    static func paper(for color: NoteColor) -> NSColor {
        nsColor(color).blended(withFraction: 0.90, of: .white) ?? .white
    }

    /// Text color swatches. `nil` removes the attribute so the destination
    /// app's own default color applies.
    static let textSwatches: [(name: String, color: NSColor?)] = [
        ("Automatic", nil),
        ("Black", .black),
        ("Gray", .darkGray),
        ("Red", NSColor(srgbRed: 0.85, green: 0.15, blue: 0.15, alpha: 1)),
        ("Orange", NSColor(srgbRed: 0.90, green: 0.50, blue: 0.05, alpha: 1)),
        ("Green", NSColor(srgbRed: 0.10, green: 0.55, blue: 0.25, alpha: 1)),
        ("Blue", NSColor(srgbRed: 0.10, green: 0.35, blue: 0.85, alpha: 1)),
        ("Purple", NSColor(srgbRed: 0.55, green: 0.25, blue: 0.80, alpha: 1)),
    ]
}
