import EdgeNotesCore
import SwiftUI

/// Panel corner shape: rounded on the screen side only, flush with the edge.
let edgeShape = UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)

enum Layout {
    /// Collapsed panel: a small transparent strip that follows the cursor along
    /// the edge. Only the capsule of dashes inside it is drawn.
    static let stripWidth: CGFloat = 12
    static let stripHeight: CGFloat = 120
    /// How close to the screen edge the strip starts following the cursor.
    static let followDistance: CGFloat = 160
    static let maxDashes = 8
    /// Deck panel: wide enough for the tab column plus a slid-out card and its shadow.
    static let deckWidth: CGFloat = 300
}

/// Resting state: a slim, dark, translucent capsule holding one small pastel
/// dash per note. Almost invisible until you reach for the edge.
struct DashStrip: View {
    let store: NoteStore

    private let shape = UnevenRoundedRectangle(topLeadingRadius: 4.5, bottomLeadingRadius: 4.5)

    var body: some View {
        VStack(spacing: 4) {
            if store.notes.isEmpty {
                Capsule().fill(.white.opacity(0.35)).frame(width: 3.5, height: 8.5)
            }
            ForEach(store.notes.prefix(Layout.maxDashes)) { note in
                Capsule().fill(Palette.dash(note.color)).frame(width: 3.5, height: 8.5)
            }
        }
        .padding(.vertical, 5)
        .padding(.leading, 2.5)
        .padding(.trailing, 1.5)
        .background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.black.opacity(0.22))
            }
            .environment(\.colorScheme, .dark)
        }
        .overlay(shape.strokeBorder(.white.opacity(0.08)))
    }
}

/// Collapsed panel content.
struct PillView: View {
    let store: NoteStore

    var body: some View {
        DashStrip(store: store)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

struct DeckView: View {
    let store: NoteStore
    let model: PanelModel
    let onEdit: (UUID) -> Void
    let onNew: () -> Void

    @State private var copiedID: UUID?
    @State private var undoNote: Note?
    @State private var undoTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            let geometry = DeckGeometry(panelSize: proxy.size, count: store.notes.count)
            let shown = geometry.visibleCount

            ZStack(alignment: .topLeading) {
                DashStrip(store: store)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .trailing)
                    .opacity(model.revealed ? 0 : 1)
                    .animation(.easeOut(duration: 0.18), value: model.revealed)
                    .allowsHitTesting(false)

                plusButton(geometry: geometry, shown: shown)

                ForEach(Array(store.notes.prefix(shown).enumerated()), id: \.element.id) { index, note in
                    tab(note, index: index, shown: shown, rect: geometry.tabRect(index), step: geometry.step)
                }

                undoBadge(geometry: geometry)

                if let id = model.hoveredID,
                   let index = store.notes.prefix(shown).firstIndex(where: { $0.id == id }) {
                    card(store.notes[index], rect: geometry.cardRect(for: index))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            // One spring drives the card sliding out of / back into its tab.
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: model.hoveredID)
        }
    }

    // MARK: - Pieces

    /// Tabs cascade in top to bottom when opening, and fold back bottom to top.
    private func tabAnimation(index: Int, shown: Int) -> Animation {
        model.revealed
            ? .easeOut(duration: 0.26).delay(0.05 + min(Double(index) * 0.03, 0.3))
            : .easeIn(duration: 0.2).delay(min(Double(shown - 1 - index) * 0.02, 0.2))
    }

    private func tab(_ note: Note, index: Int, shown: Int, rect: CGRect, step: CGFloat) -> some View {
        // Later tabs are drawn on top, so only `step` points of each tab show,
        // except the last one which shows in full. The label must fit in that.
        let visible = index == shown - 1 ? rect.height : min(step, rect.height)
        return TabLabel(note: note, visibleHeight: visible)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .offset(x: model.revealed ? 0 : DeckGeometry.tabWidth + 10)
            // The hovered tab is replaced by its card.
            .opacity(model.revealed && model.hoveredID != note.id ? 1 : 0)
            .animation(tabAnimation(index: index, shown: shown), value: model.revealed)
            .animation(.easeOut(duration: 0.12), value: model.hoveredID)
            .allowsHitTesting(model.revealed)
            .onTapGesture { copy(note) }
            .contextMenu { menu(for: note) }
    }

    private func plusButton(geometry: DeckGeometry, shown: Int) -> some View {
        let rect = geometry.plusRect
        return Image(systemName: "plus")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: rect.width, height: rect.height)
            .background(.regularMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.primary.opacity(0.12)))
            .position(x: rect.midX, y: rect.midY)
            // Appears first when opening, disappears last when closing.
            .opacity(model.revealed ? 1 : 0)
            .animation(
                model.revealed
                    ? .easeOut(duration: 0.18)
                    : .easeIn(duration: 0.18).delay(min(Double(shown) * 0.02, 0.2)),
                value: model.revealed
            )
            .allowsHitTesting(model.revealed)
            .onTapGesture(perform: onNew)
    }

    private func card(_ note: Note, rect: CGRect) -> some View {
        NoteCard(
            note: note,
            isCopied: copiedID == note.id,
            onCopy: { copy(note) },
            onEdit: { onEdit(note.id) }
        )
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .contextMenu { menu(for: note) }
        .id(note.id)
        .zIndex(2)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    @ViewBuilder
    private func undoBadge(geometry: DeckGeometry) -> some View {
        if let undoNote {
            let rect = geometry.plusRect
            HStack(spacing: 8) {
                Text("Deleted").font(.caption).foregroundStyle(.secondary)
                Button("Undo") {
                    store.restore(undoNote)
                    self.undoNote = nil
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .frame(height: rect.height)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.12)))
            .position(x: rect.minX - 62, y: rect.midY)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func menu(for note: Note) -> some View {
        Button("Copy") { copy(note) }
        Button("Edit") { onEdit(note.id) }
        Button("Duplicate") { store.duplicate(id: note.id) }
        Divider()
        Button("Move Up") { move(note, by: -1) }
        Button("Move Down") { move(note, by: 1) }
        Divider()
        Button("Delete", role: .destructive) { delete(note) }
    }

    // MARK: - Actions

    private func copy(_ note: Note) {
        NoteClipboard.copy(note)
        copiedID = note.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copiedID == note.id { copiedID = nil }
        }
    }

    private func move(_ note: Note, by offset: Int) {
        guard let index = store.notes.firstIndex(where: { $0.id == note.id }) else { return }
        let target = index + offset
        guard store.notes.indices.contains(target) else { return }
        // `move(to:)` takes an insertion point, so moving down needs +1.
        store.move(from: IndexSet(integer: index), to: offset > 0 ? target + 1 : target)
    }

    private func delete(_ note: Note) {
        model.hover(nil)
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

/// The colored tab with its title printed sideways, like a file-folder tab.
private struct TabLabel: View {
    let note: Note
    /// Height of the part of the tab that is not covered by the next one.
    let visibleHeight: CGFloat

    /// Rough width of one uppercase character at the label font, tracking included.
    private static let charWidth: CGFloat = 6.4

    private var label: String {
        let fitting = Int((visibleHeight - 4) / Self.charWidth)
        return String(note.title.uppercased().prefix(max(1, min(fitting, 8))))
    }

    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9)
                .fill(Palette.tab(note.color))
                .shadow(color: .black.opacity(0.18), radius: 3, x: -1, y: 1)
            Text(label)
                .font(.system(size: 8.5, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(Palette.ink(note.color))
                .lineLimit(1)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                // Center the sideways text inside the visible band, not the whole tab.
                .frame(width: DeckGeometry.tabWidth, height: visibleHeight)
        }
    }
}

/// The note, slid out of its tab: sideways label, title and a rich-text preview.
private struct NoteCard: View {
    let note: Note
    let isCopied: Bool
    let onCopy: () -> Void
    let onEdit: () -> Void

    private let shape = UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10)

    var body: some View {
        HStack(spacing: 0) {
            Text(String(note.title.uppercased().prefix(10)))
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Palette.ink(note.color))
                .lineLimit(1)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 26)
                .frame(maxHeight: .infinity)
                .background(Palette.tab(note.color))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if isCopied {
                        Label("Copied", systemImage: "checkmark")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(red: 0.1, green: 0.5, blue: 0.25))
                    } else {
                        Button(action: onEdit) { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                            .help("Edit")
                    }
                }
                RichTextPreview(rtf: note.body)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .foregroundStyle(Color.black.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Palette.card(note.color))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.28), radius: 8, x: -2, y: 2)
        .contentShape(shape)
        .onTapGesture(perform: onCopy)
    }
}
