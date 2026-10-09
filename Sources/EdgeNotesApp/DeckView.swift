import EdgeNotesCore
import SwiftUI

/// Panel corner shape: rounded on the screen side only, flush with the edge.
private let edgeShape = UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)

struct PillView: View {
    let store: NoteStore

    var body: some View {
        VStack(spacing: Layout.dashSpacing) {
            if store.notes.isEmpty {
                Capsule().fill(.secondary.opacity(0.5)).frame(width: 8, height: Layout.dashHeight)
            }
            ForEach(store.notes.prefix(Layout.maxPillDashes)) { note in
                Capsule().fill(Palette.color(note.color)).frame(width: 8, height: Layout.dashHeight)
            }
        }
        .frame(width: Layout.pillWidth, height: Layout.pillHeight(dashes: store.notes.count))
        .background(.regularMaterial, in: edgeShape)
        .overlay(edgeShape.strokeBorder(.primary.opacity(0.12)))
        // The panel is a taller, transparent strip so the hover target at the
        // screen edge is easy to hit; only the pill itself is drawn.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

struct DeckView: View {
    let store: NoteStore
    let onEdit: (UUID) -> Void
    let onNew: () -> Void

    @State private var copiedID: UUID?
    @State private var undoNote: Note?
    @State private var undoTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if store.notes.isEmpty {
                Text("No notes yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.notes) { note in
                        NoteRow(
                            note: note,
                            isCopied: copiedID == note.id,
                            onCopy: { copy(note) },
                            onEdit: { onEdit(note.id) },
                            onDuplicate: { store.duplicate(id: note.id) },
                            onDelete: { delete(note) }
                        )
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onMove { store.move(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            Divider()
            footer
        }
        .background(.regularMaterial, in: edgeShape)
        .overlay(edgeShape.strokeBorder(.primary.opacity(0.12)))
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            if let undoNote {
                Text("Deleted “\(undoNote.title)”")
                    .lineLimit(1)
                    .font(.callout)
                Spacer()
                Button("Undo") {
                    store.restore(undoNote)
                    self.undoNote = nil
                }
            } else {
                Button(action: onNew) {
                    Label("New note", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Layout.footerHeight)
    }

    private func copy(_ note: Note) {
        NoteClipboard.copy(note)
        copiedID = note.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copiedID == note.id { copiedID = nil }
        }
    }

    private func delete(_ note: Note) {
        store.delete(id: note.id)
        undoNote = note
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            undoNote = nil
        }
    }
}

private struct NoteRow: View {
    let note: Note
    let isCopied: Bool
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(Palette.color(note.color))
                .frame(width: 4, height: 22)
            Text(note.title.isEmpty ? "Untitled" : note.title)
                .lineLimit(1)
            Spacer(minLength: 4)
            if isCopied {
                Label("Copied", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Edit")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Layout.rowHeight - 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hovering ? Palette.color(note.color).opacity(0.18) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onCopy)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copy", action: onCopy)
            Button("Edit", action: onEdit)
            Button("Duplicate", action: onDuplicate)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

enum Layout {
    static let pillWidth: CGFloat = 14
    static let maxPillDashes = 8
    static let dashHeight: CGFloat = 3
    static let dashSpacing: CGFloat = 6
    /// Height of the transparent hover strip the collapsed panel occupies.
    static let hoverStripHeight: CGFloat = 160

    /// Visible pill height for a given note count (at least one dash).
    static func pillHeight(dashes count: Int) -> CGFloat {
        let dashes = CGFloat(max(1, min(count, maxPillDashes)))
        return 16 + dashes * (dashHeight + dashSpacing)
    }
    static let deckWidth: CGFloat = 264
    static let editorWidth: CGFloat = 440
    static let rowHeight: CGFloat = 40
    static let footerHeight: CGFloat = 44
}
