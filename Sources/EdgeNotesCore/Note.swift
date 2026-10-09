import Foundation

/// Accent color of a note. Kept UI-agnostic so Core never imports SwiftUI.
public enum NoteColor: String, Codable, CaseIterable, Sendable {
    case yellow, orange, red, pink, purple, blue, teal, green, gray

    /// sRGB components in 0...1.
    public var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .yellow: (1.00, 0.80, 0.20)
        case .orange: (1.00, 0.58, 0.20)
        case .red: (0.95, 0.33, 0.33)
        case .pink: (0.95, 0.45, 0.70)
        case .purple: (0.62, 0.45, 0.90)
        case .blue: (0.30, 0.55, 0.95)
        case .teal: (0.20, 0.72, 0.72)
        case .green: (0.35, 0.75, 0.40)
        case .gray: (0.60, 0.60, 0.62)
        }
    }
}

/// A text template. `body` is RTF so formatting survives a round trip to disk.
public struct Note: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var color: NoteColor
    public var body: Data
    public var position: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "Untitled",
        color: NoteColor = .yellow,
        body: Data = Data(),
        position: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.color = color
        self.body = body
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
