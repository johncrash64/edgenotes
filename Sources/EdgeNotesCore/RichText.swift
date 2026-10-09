import AppKit

/// RTF <-> NSAttributedString helpers. RTF is the storage format because every
/// Mac text app understands it, so what we store is what gets pasted.
public enum RichText {
    public static func attributedString(fromRTF data: Data) -> NSAttributedString {
        guard !data.isEmpty,
              let string = NSAttributedString(rtf: data, documentAttributes: nil)
        else { return NSAttributedString() }
        return string
    }

    public static func rtf(from string: NSAttributedString) -> Data {
        let range = NSRange(location: 0, length: string.length)
        return string.rtf(from: range, documentAttributes: [:]) ?? Data()
    }

    public static func plainText(fromRTF data: Data) -> String {
        attributedString(fromRTF: data).string
    }

    /// HTML flavor for web apps (Gmail, Slack, Notion) that ignore RTF.
    public static func html(from string: NSAttributedString) -> Data? {
        let range = NSRange(location: 0, length: string.length)
        return try? string.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        )
    }
}
