import Foundation
import os

/// One JSON file per note: `<directory>/<uuid>.json`.
public struct FileNoteRepository: Sendable {
    public let directory: URL

    private static let logger = Logger(subsystem: "com.johncrash64.edgenotes", category: "repository")

    public init(directory: URL) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory
            .appending(path: "EdgeNotes", directoryHint: .isDirectory)
            .appending(path: "notes", directoryHint: .isDirectory)
    }

    public func loadAll() throws -> [Note] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        let decoder = Self.makeDecoder()
        var notes: [Note] = []
        for file in files {
            do {
                notes.append(try decoder.decode(Note.self, from: Data(contentsOf: file)))
            } catch {
                // A corrupt file must not take the other notes down with it.
                Self.logger.error("Skipping unreadable note \(file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return notes.sorted { ($0.position, $0.createdAt) < ($1.position, $1.createdAt) }
    }

    public func save(_ note: Note) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.makeEncoder().encode(note)
        try data.write(to: fileURL(for: note.id), options: .atomic)
    }

    public func delete(id: UUID) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
