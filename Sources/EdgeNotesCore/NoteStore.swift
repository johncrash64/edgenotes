import AppKit
import Observation
import os

/// In-memory source of truth for the deck. Edits are written to disk after a
/// short debounce so typing never blocks on I/O.
@MainActor
@Observable
public final class NoteStore {
    public private(set) var notes: [Note] = []

    @ObservationIgnored private let repository: FileNoteRepository
    @ObservationIgnored private let saveDelay: Duration
    @ObservationIgnored private var pendingSaves: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let logger = Logger(subsystem: "com.johncrash64.edgenotes", category: "store")

    public init(repository: FileNoteRepository, saveDelay: Duration = .milliseconds(250)) {
        self.repository = repository
        self.saveDelay = saveDelay
    }

    public func load() {
        do {
            notes = try repository.loadAll()
        } catch {
            logger.error("Failed to load notes: \(error.localizedDescription, privacy: .public)")
            notes = []
        }
    }

    public func note(id: UUID) -> Note? {
        notes.first { $0.id == id }
    }

    @discardableResult
    public func add(title: String = "Untitled", color: NoteColor = .yellow, body: Data = Data()) -> Note {
        let note = Note(title: title, color: color, body: body, position: notes.count)
        notes.append(note)
        scheduleSave(note.id)
        return note
    }

    @discardableResult
    public func duplicate(id: UUID) -> Note? {
        guard let source = note(id: id) else { return nil }
        return add(title: "\(source.title) copy", color: source.color, body: source.body)
    }

    public func update(id: UUID, title: String? = nil, color: NoteColor? = nil, body: Data? = nil) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if let title { notes[index].title = title }
        if let color { notes[index].color = color }
        if let body { notes[index].body = body }
        notes[index].updatedAt = Date()
        scheduleSave(id)
    }

    public func delete(id: UUID) {
        pendingSaves.removeValue(forKey: id)?.cancel()
        notes.removeAll { $0.id == id }
        do {
            try repository.delete(id: id)
        } catch {
            logger.error("Failed to delete note: \(error.localizedDescription, privacy: .public)")
        }
        renumber()
    }

    /// Puts a deleted note back at its old position (undo of `delete`).
    public func restore(_ note: Note) {
        guard self.note(id: note.id) == nil else { return }
        notes.insert(note, at: min(max(note.position, 0), notes.count))
        scheduleSave(note.id)
        renumber()
    }

    public func move(from source: IndexSet, to destination: Int) {
        // Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`, reimplemented
        // so Core stays free of SwiftUI.
        let sources = source.sorted()
        let moving = sources.map { notes[$0] }
        let insertAt = destination - sources.filter { $0 < destination }.count
        for index in sources.reversed() { notes.remove(at: index) }
        notes.insert(contentsOf: moving, at: insertAt)
        renumber()
    }

    /// Writes every pending edit immediately. Call before the app quits.
    public func flush() {
        let ids = Array(pendingSaves.keys)
        for id in ids {
            pendingSaves.removeValue(forKey: id)?.cancel()
            persist(id)
        }
    }

    /// Seeds one example so a first launch is not an empty strip.
    public func seedIfEmpty() {
        guard notes.isEmpty else { return }
        let body = NSMutableAttributedString(
            string: "Hi,\n\nThanks for reaching out. ",
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        )
        body.append(NSAttributedString(
            string: "Click this note to copy it",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor.systemBlue]
        ))
        body.append(NSAttributedString(
            string: ", then paste it anywhere. Formatting comes along.\n",
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        ))
        add(title: "Welcome", color: .blue, body: RichText.rtf(from: body))
    }

    // MARK: - Private

    private func renumber() {
        for index in notes.indices where notes[index].position != index {
            notes[index].position = index
            scheduleSave(notes[index].id)
        }
    }

    private func scheduleSave(_ id: UUID) {
        pendingSaves[id]?.cancel()
        let delay = saveDelay
        pendingSaves[id] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.pendingSaves[id] = nil
            self?.persist(id)
        }
    }

    private func persist(_ id: UUID) {
        guard let note = note(id: id) else { return }
        do {
            try repository.save(note)
        } catch {
            logger.error("Failed to save note: \(error.localizedDescription, privacy: .public)")
        }
    }
}
