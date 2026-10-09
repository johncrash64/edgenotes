import AppKit

/// Puts a note on the pasteboard in every flavor a destination might want:
/// RTF for native Mac apps, HTML for web apps, plain text as the fallback.
public enum NoteClipboard {
    public static func copy(_ note: Note, to pasteboard: NSPasteboard = .general) {
        let attributed = RichText.attributedString(fromRTF: note.body)
        pasteboard.clearContents()
        pasteboard.setData(RichText.rtf(from: attributed), forType: .rtf)
        if let html = RichText.html(from: attributed) {
            pasteboard.setData(html, forType: .html)
        }
        pasteboard.setString(attributed.string, forType: .string)
    }
}
