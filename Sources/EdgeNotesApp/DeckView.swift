import EdgeNotesCore
import SwiftUI

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

/// Where the resting dashes sit. Shared by the collapsed strip and the deck so the
/// hand-over between the two panels is invisible, and so each dash can grow
/// into its own tab.
enum DashLayout {
    static let dashWidth: CGFloat = 3.5
    static let dashHeight: CGFloat = 8.5
    static let spacing: CGFloat = 4
    static let paddingVertical: CGFloat = 5
    static let paddingLeading: CGFloat = 2.5
    static let paddingTrailing: CGFloat = 1.5

    private static func shown(_ count: Int) -> Int { max(1, min(count, Layout.maxDashes)) }

    /// The dark capsule behind the dashes, flush right and vertically centered.
    static func containerRect(count: Int, in size: CGSize) -> CGRect {
        let n = CGFloat(shown(count))
        let width = paddingLeading + dashWidth + paddingTrailing
        let height = n * dashHeight + (n - 1) * spacing + 2 * paddingVertical
        return CGRect(x: size.width - width, y: (size.height - height) / 2, width: width, height: height)
    }

    /// Dash `index`. Notes past the last visible dash stack on it (and are hidden).
    static func dashRect(index: Int, count: Int, in size: CGSize) -> CGRect {
        let container = containerRect(count: count, in: size)
        let slot = CGFloat(min(index, shown(count) - 1))
        return CGRect(
            x: container.minX + paddingLeading,
            y: container.minY + paddingVertical + slot * (dashHeight + spacing),
            width: dashWidth,
            height: dashHeight
        )
    }
}

/// The slim, dark, translucent capsule dashes rest in.
private struct StripBackdrop: View {
    private let shape = UnevenRoundedRectangle(topLeadingRadius: 4.5, bottomLeadingRadius: 4.5)

    var body: some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color.black.opacity(0.22))
        }
        .environment(\.colorScheme, .dark)
        .overlay(shape.strokeBorder(.white.opacity(0.08)))
    }
}

/// Collapsed panel content: the capsule and one pastel dash per note.
struct PillView: View {
    let store: NoteStore

    var body: some View {
        GeometryReader { proxy in
            let count = store.notes.count
            let container = DashLayout.containerRect(count: count, in: proxy.size)
            let first = DashLayout.dashRect(index: 0, count: count, in: proxy.size)
            ZStack(alignment: .topLeading) {
                StripBackdrop()
                    .frame(width: container.width, height: container.height)
                    .offset(x: container.minX, y: container.minY)
                if count == 0 {
                    Capsule()
                        .fill(.white.opacity(0.35))
                        .frame(width: DashLayout.dashWidth, height: DashLayout.dashHeight)
                        .offset(x: first.minX, y: first.minY)
                }
                ForEach(Array(store.notes.prefix(Layout.maxDashes).enumerated()), id: \.element.id) { index, note in
                    let rect = DashLayout.dashRect(index: index, count: count, in: proxy.size)
                    Capsule()
                        .fill(Palette.dash(note.color))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }
}

/// The three shapes one note takes as the deck opens: dash -> tab -> card.
private enum Phase {
    case dash, tab, card
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
            let total = store.notes.count
            let container = DashLayout.containerRect(count: total, in: proxy.size)

            ZStack(alignment: .topLeading) {
                // The resting capsule gives way as its dashes become tabs.
                StripBackdrop()
                    .frame(width: container.width, height: container.height)
                    .offset(x: container.minX, y: container.minY)
                    .opacity(model.revealed ? 0 : 1)
                    .animation(
                        model.revealed ? .easeOut(duration: 0.14) : .easeIn(duration: 0.2).delay(0.25),
                        value: model.revealed
                    )
                    .allowsHitTesting(false)

                plusButton(geometry: geometry, shown: shown)

                ForEach(Array(store.notes.prefix(shown).enumerated()), id: \.element.id) { index, note in
                    let phase: Phase = !model.revealed ? .dash : (model.hoveredID == note.id ? .card : .tab)
                    NoteSurface(
                        note: note,
                        phase: phase,
                        dashRect: DashLayout.dashRect(index: index, count: total, in: proxy.size),
                        tabRect: geometry.tabRect(index),
                        cardRect: geometry.cardRect(for: index),
                        tabVisibleHeight: index == shown - 1 ? DeckGeometry.tabHeight : min(geometry.step, DeckGeometry.tabHeight),
                        hidden: phase == .dash && index >= Layout.maxDashes,
                        isCopied: copiedID == note.id,
                        onCopy: { copy(note) },
                        onEdit: { onEdit(note.id) }
                    )
                    .zIndex(phase == .card ? 100 : Double(index))
                    // Which change is animating picks the motion: opening cascades, hovering springs.
                    .animation(openAnimation(index: index, shown: shown), value: model.revealed)
                    .animation(.spring(response: 0.36, dampingFraction: 0.84), value: model.hoveredID)
                    .allowsHitTesting(phase != .dash)
                    .contextMenu { menu(for: note) }
                }

                undoBadge(geometry: geometry)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    // MARK: - Pieces

    /// Dashes grow into tabs top to bottom when opening, and fold back bottom to top.
    private func openAnimation(index: Int, shown: Int) -> Animation {
        model.revealed
            ? .spring(response: 0.42, dampingFraction: 0.8).delay(min(Double(index) * 0.03, 0.25))
            : .spring(response: 0.34, dampingFraction: 0.92).delay(min(Double(shown - 1 - index) * 0.02, 0.2))
    }

    private func plusButton(geometry: DeckGeometry, shown: Int) -> some View {
        let rect = geometry.plusRect
        return Image(systemName: "plus")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: rect.width, height: rect.height)
            .background(.regularMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.primary.opacity(0.12)))
            .offset(x: rect.minX, y: rect.minY)
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
            .fixedSize()
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.12)))
            .offset(x: rect.minX - 124, y: rect.minY)
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

/// One note, one surface: the same shape is a dash, grows into a tab, and
/// grows again into a card. Position, size, corners, color and shadow all
/// interpolate; only the contents (label, text) are revealed inside it.
private struct NoteSurface: View {
    let note: Note
    let phase: Phase
    let dashRect: CGRect
    let tabRect: CGRect
    let cardRect: CGRect
    /// Height of the part of the tab not covered by the next one.
    let tabVisibleHeight: CGFloat
    let hidden: Bool
    let isCopied: Bool
    let onCopy: () -> Void
    let onEdit: () -> Void

    /// Width of the sideways-label strip on the left of the card.
    private static let stripWidth: CGFloat = 26
    /// Rough width of one uppercase character at the label font, tracking included.
    private static let charWidth: CGFloat = 6.4

    private var rect: CGRect {
        switch phase {
        case .dash: dashRect
        case .tab: tabRect
        case .card: cardRect
        }
    }

    private var radii: RectangleCornerRadii {
        switch phase {
        case .dash: .init(topLeading: 1.75, bottomLeading: 1.75, bottomTrailing: 1.75, topTrailing: 1.75)
        case .tab: .init(topLeading: 9, bottomLeading: 9, bottomTrailing: 0, topTrailing: 0)
        case .card: .init(topLeading: 10, bottomLeading: 10, bottomTrailing: 0, topTrailing: 0)
        }
    }

    private var fill: Color {
        switch phase {
        case .dash: Palette.dash(note.color)
        case .tab: Palette.tab(note.color)
        case .card: Palette.card(note.color)
        }
    }

    private var label: String {
        let fitting = Int((tabVisibleHeight - 4) / Self.charWidth)
        return String(note.title.uppercased().prefix(max(1, min(fitting, 8))))
    }

    var body: some View {
        let shape = UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(fill)

            // The label strip of the card is the tab's own color.
            Rectangle()
                .fill(Palette.tab(note.color))
                .frame(width: Self.stripWidth)
                .opacity(phase == .card ? 1 : 0)

            Text(label)
                .font(.system(size: 8.5, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(Palette.ink(note.color))
                .lineLimit(1)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                // Centered in the tab's visible band, then in the card's strip.
                .position(
                    x: phase == .card ? Self.stripWidth / 2 : DeckGeometry.tabWidth / 2,
                    y: phase == .card ? cardRect.height / 2 : tabVisibleHeight / 2
                )
                .opacity(phase == .dash ? 0 : 1)

            if phase == .card {
                cardBody
                    .transition(.opacity.animation(.easeOut(duration: 0.18).delay(0.1)))
            }
        }
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .clipShape(shape)
        .shadow(
            color: .black.opacity(phase == .card ? 0.28 : (phase == .tab ? 0.18 : 0)),
            radius: phase == .card ? 8 : 3,
            x: phase == .card ? -2 : -1,
            y: phase == .card ? 2 : 1
        )
        .contentShape(shape)
        .onTapGesture(perform: onCopy)
        .offset(x: rect.minX, y: rect.minY)
        .opacity(hidden ? 0 : 1)
    }

    /// Title, pencil and rich-text preview. Laid out at the card's full size and
    /// clipped by the surface, so it is uncovered as the card grows.
    private var cardBody: some View {
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
        .frame(
            width: DeckGeometry.cardWidth - Self.stripWidth,
            height: DeckGeometry.cardHeight,
            alignment: .topLeading
        )
        .offset(x: Self.stripWidth)
    }
}
