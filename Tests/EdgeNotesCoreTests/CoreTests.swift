import AppKit
import Foundation
import Testing

@testable import EdgeNotesCore

private func makeTempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "edgenotes-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    return url
}

private func makeBoldRedRTF() -> Data {
    let string = NSAttributedString(
        string: "Hello",
        attributes: [.font: NSFont.boldSystemFont(ofSize: 18), .foregroundColor: NSColor.red]
    )
    return RichText.rtf(from: string)
}

@Suite struct RichTextTests {
    @Test func roundTripKeepsPlainTextAndFormatting() {
        let restored = RichText.attributedString(fromRTF: makeBoldRedRTF())
        #expect(restored.string == "Hello")

        let font = restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true)
        #expect(font?.pointSize == 18)

        let color = restored.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color?.usingColorSpace(.sRGB)?.redComponent ?? 0 > 0.9)
    }

    @Test func emptyDataYieldsEmptyString() {
        #expect(RichText.attributedString(fromRTF: Data()).length == 0)
        #expect(RichText.plainText(fromRTF: Data()) == "")
    }
}

@Suite struct ClipboardTests {
    @Test func copyWritesRTFHTMLAndPlainText() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("edgenotes.test.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        NoteClipboard.copy(Note(title: "T", body: makeBoldRedRTF()), to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "Hello")
        let rtf = try #require(pasteboard.data(forType: .rtf))
        #expect(RichText.plainText(fromRTF: rtf) == "Hello")
        let html = try #require(pasteboard.data(forType: .html))
        #expect(String(decoding: html, as: UTF8.self).contains("Hello"))
    }
}

@Suite struct RepositoryTests {
    @Test func saveLoadDeleteRoundTrip() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = FileNoteRepository(directory: dir)

        let note = Note(title: "Greeting", color: .teal, body: makeBoldRedRTF(), position: 2)
        try repo.save(note)

        let loaded = try repo.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == note.id)
        #expect(loaded[0].title == "Greeting")
        #expect(loaded[0].color == .teal)
        #expect(loaded[0].body == note.body)

        try repo.delete(id: note.id)
        #expect(try repo.loadAll().isEmpty)
    }

    @Test func missingDirectoryLoadsEmpty() throws {
        let repo = FileNoteRepository(directory: makeTempDirectory())
        #expect(try repo.loadAll().isEmpty)
    }

    @Test func corruptFileIsSkippedNotFatal() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = FileNoteRepository(directory: dir)
        try repo.save(Note(title: "Good"))
        try Data("not json".utf8).write(to: dir.appending(path: "broken.json"))

        let loaded = try repo.loadAll()
        #expect(loaded.map(\.title) == ["Good"])
    }

    @Test func loadOrdersByPosition() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = FileNoteRepository(directory: dir)
        try repo.save(Note(title: "B", position: 1))
        try repo.save(Note(title: "A", position: 0))
        #expect(try repo.loadAll().map(\.title) == ["A", "B"])
    }
}

@MainActor
@Suite struct StoreTests {
    private func makeStore(delay: Duration = .milliseconds(20)) -> (NoteStore, FileNoteRepository, URL) {
        let dir = makeTempDirectory()
        let repo = FileNoteRepository(directory: dir)
        return (NoteStore(repository: repo, saveDelay: delay), repo, dir)
    }

    @Test func editsAreDebouncedToDisk() async throws {
        let (store, repo, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let note = store.add(title: "One")
        store.update(id: note.id, title: "Two")
        #expect(try repo.loadAll().isEmpty, "nothing is written before the debounce fires")

        try await Task.sleep(for: .milliseconds(200))
        #expect(try repo.loadAll().map(\.title) == ["Two"])
    }

    @Test func flushWritesImmediately() throws {
        let (store, repo, dir) = makeStore(delay: .seconds(60))
        defer { try? FileManager.default.removeItem(at: dir) }

        store.add(title: "Pending")
        store.flush()
        #expect(try repo.loadAll().map(\.title) == ["Pending"])
    }

    @Test func deleteRemovesFileAndRenumbers() async throws {
        let (store, repo, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = store.add(title: "A")
        store.add(title: "B")
        store.flush()
        store.delete(id: a.id)
        try await Task.sleep(for: .milliseconds(200))

        let loaded = try repo.loadAll()
        #expect(loaded.map(\.title) == ["B"])
        #expect(loaded[0].position == 0)
    }

    @Test func moveReordersAndPersistsPositions() async throws {
        let (store, repo, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.add(title: "A")
        store.add(title: "B")
        store.add(title: "C")
        store.move(from: IndexSet(integer: 2), to: 0)
        try await Task.sleep(for: .milliseconds(200))

        #expect(store.notes.map(\.title) == ["C", "A", "B"])
        #expect(try repo.loadAll().map(\.title) == ["C", "A", "B"])
    }

    @Test func duplicateCopiesBodyAndColor() {
        let (store, _, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = store.add(title: "Hi", color: .pink, body: makeBoldRedRTF())
        let copy = store.duplicate(id: original.id)
        #expect(copy?.title == "Hi copy")
        #expect(copy?.color == .pink)
        #expect(copy?.body == original.body)
        #expect(copy?.id != original.id)
    }

    @Test func restoreUndoesDeleteAtOriginalPosition() async throws {
        let (store, repo, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.add(title: "A")
        let b = store.add(title: "B")
        store.add(title: "C")
        let removed = try #require(store.note(id: b.id))
        store.delete(id: b.id)
        #expect(store.notes.map(\.title) == ["A", "C"])

        store.restore(removed)
        store.restore(removed)  // second call must be a no-op, not a duplicate
        try await Task.sleep(for: .milliseconds(200))

        #expect(store.notes.map(\.title) == ["A", "B", "C"])
        #expect(try repo.loadAll().map(\.title) == ["A", "B", "C"])
    }

    @Test func seedOnlyWhenEmpty() {
        let (store, _, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.seedIfEmpty()
        #expect(store.notes.count == 1)
        store.seedIfEmpty()
        #expect(store.notes.count == 1)
    }
}
