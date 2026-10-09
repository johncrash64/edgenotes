import AppKit
import EdgeNotesCore
import SwiftUI

@MainActor
@Observable
final class EditorModel {
    let noteID: UUID
    /// A pinned editor stays open when you click elsewhere.
    var pinned = false
    /// Drives the pop-in / pop-out animation.
    var appeared = false
    var format = RichTextController.FormatState()

    init(noteID: UUID) {
        self.noteID = noteID
    }
}

/// The note editor: a pastel sheet in its own centered window.
struct EditorView: View {
    static let cardSize = CGSize(width: 440, height: 500)
    /// Transparent room around the card for its shadow.
    static let margin: CGFloat = 28

    let store: NoteStore
    let model: EditorModel
    let controller: RichTextController
    let onClose: () -> Void
    let onDelete: () -> Void

    @State private var justCopied = false
    @State private var confirmingDelete = false

    private static let sizes: [CGFloat] = [10, 12, 14, 16, 18, 24, 32, 48]

    /// Font families offered up front, in groups. Only those installed are shown.
    private static let fontGroups: [(title: String, families: [String])] = {
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        let groups: [(String, [String])] = [
            ("Handwriting", ["Noteworthy", "Bradley Hand", "Marker Felt"]),
            ("Sans", ["Helvetica Neue", "Avenir Next"]),
            ("Serif", ["Georgia", "Times New Roman"]),
            ("Mono", ["Menlo", "Courier New"]),
        ]
        return groups.map { ($0.0, $0.1.filter(installed.contains)) }.filter { !$0.1.isEmpty }
    }()

    var body: some View {
        if let note = store.note(id: model.noteID) {
            card(note)
                .padding(Self.margin)
                // Pastel paper is light in both appearances.
                .environment(\.colorScheme, .light)
        }
    }

    // MARK: - Card

    private func card(_ note: Note) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(spacing: 0) {
            header(note)
            hairline
            formattingBar
            bodyArea(note)
            hairline
            footer(note)
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .foregroundStyle(Color.black.opacity(0.78))
        .background {
            ZStack {
                shape.fill(Palette.card(note.color))
                shape.fill(LinearGradient(
                    colors: [.white.opacity(0.38), .white.opacity(0)],
                    startPoint: .top,
                    endPoint: .center
                ))
            }
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(LinearGradient(
                colors: [.white.opacity(0.75), .black.opacity(0.10)],
                startPoint: .top,
                endPoint: .bottom
            ))
        )
        .shadow(color: .black.opacity(0.30), radius: 26, y: 12)
        .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
        // Pop in: a little smaller and blurred, springing to full size.
        .scaleEffect(model.appeared ? 1 : 0.93)
        .opacity(model.appeared ? 1 : 0)
        .blur(radius: model.appeared ? 0 : 8)
        .animation(.spring(response: 0.36, dampingFraction: 0.8), value: model.appeared)
    }

    private var hairline: some View {
        Rectangle().fill(Color.black.opacity(0.07)).frame(height: 1)
    }

    // MARK: - Header

    private func header(_ note: Note) -> some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                ZStack {
                    Circle().fill(Color(red: 1.0, green: 0.38, blue: 0.35))
                    Image(systemName: "xmark")
                        .font(.system(size: 6, weight: .heavy))
                        .foregroundStyle(.black.opacity(0.5))
                }
                .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .help("Close (⌘W)")

            TextField("Untitled", text: Binding(
                get: { note.title },
                set: { store.update(id: model.noteID, title: $0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 16, weight: .semibold, design: .rounded))

            Spacer(minLength: 0)

            savedStatus(note)

            Button { model.pinned.toggle() } label: {
                Image(systemName: model.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .medium))
                    .rotationEffect(.degrees(model.pinned ? 0 : 45))
                    .foregroundStyle(model.pinned ? Palette.ink(note.color) : Color.black.opacity(0.4))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(model.pinned ? "Unpin" : "Keep open when you click elsewhere")
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    /// "Saving…" for a moment after each edit, then "Saved".
    private func savedStatus(_ note: Note) -> some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { context in
            let saving = context.date.timeIntervalSince(note.updatedAt) < 0.7
            HStack(spacing: 5) {
                Circle()
                    .fill(saving ? Color.orange : Color(red: 0.2, green: 0.65, blue: 0.35))
                    .frame(width: 6, height: 6)
                Text(saving ? "Saving…" : "Saved")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.45))
            }
        }
    }

    // MARK: - Formatting bar

    private var formattingBar: some View {
        HStack(spacing: 3) {
            fontMenu
            sizeMenu
            divider
            FormatToggle(symbol: "bold", active: model.format.bold, help: "Bold (⌘B)") { controller.toggleBold() }
            FormatToggle(symbol: "italic", active: model.format.italic, help: "Italic (⌘I)") { controller.toggleItalic() }
            FormatToggle(symbol: "underline", active: model.format.underline, help: "Underline (⌘U)") { controller.toggleUnderline() }
            divider
            ForEach(Array(Palette.textSwatches.enumerated()), id: \.offset) { _, swatch in
                swatchButton(swatch)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 42)
    }

    private var divider: some View {
        Rectangle().fill(Color.black.opacity(0.12)).frame(width: 1, height: 16).padding(.horizontal, 2)
    }

    private var fontMenu: some View {
        Menu {
            Button("System") { controller.setFamily(nil) }
            ForEach(Self.fontGroups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.families, id: \.self) { family in
                        Button(family) { controller.setFamily(family) }
                    }
                }
            }
            Divider()
            Menu("All Fonts") {
                ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { family in
                    Button(family) { controller.setFamily(family) }
                }
            }
        } label: {
            Chip {
                Text(model.format.family)
                    .lineLimit(1)
                    .frame(maxWidth: 74, alignment: .leading)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Font")
    }

    private var sizeMenu: some View {
        Menu {
            ForEach(Self.sizes, id: \.self) { size in
                Button("\(Int(size)) pt") { controller.setSize(size) }
            }
        } label: {
            Chip { Text("\(Int(model.format.size))").monospacedDigit() }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Size")
    }

    private func swatchButton(_ swatch: (name: String, color: NSColor?)) -> some View {
        let selected = Self.sameColor(swatch.color, model.format.color)
        return Button { controller.setColor(swatch.color) } label: {
            ZStack {
                if let color = swatch.color {
                    Circle().fill(Color(nsColor: color))
                } else {
                    Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1)
                    Image(systemName: "slash.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.black.opacity(0.45))
                }
            }
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.7), lineWidth: 1.5).padding(-2.5).opacity(selected ? 1 : 0))
            .padding(2.5)
        }
        .buttonStyle(.plain)
        .help("Text color: \(swatch.name)")
    }

    /// `nil` is "automatic"; otherwise compare in sRGB with a small tolerance.
    private static func sameColor(_ a: NSColor?, _ b: NSColor?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (a?, b?):
            guard let a = a.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else { return false }
            return abs(a.redComponent - b.redComponent) < 0.02
                && abs(a.greenComponent - b.greenComponent) < 0.02
                && abs(a.blueComponent - b.blueComponent) < 0.02
        default:
            return false
        }
    }

    // MARK: - Body

    private func bodyArea(_ note: Note) -> some View {
        RichTextEditor(
            initialRTF: note.body,
            paper: Palette.paper(for: note.color),
            controller: controller,
            onChange: { store.update(id: model.noteID, body: $0) }
        )
        .id(model.noteID)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.black.opacity(0.07)))
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Footer

    private func footer(_ note: Note) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(NoteColor.allCases, id: \.self) { color in
                    Button { store.update(id: model.noteID, color: color) } label: {
                        Circle()
                            .fill(Palette.color(color))
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle()
                                    .strokeBorder(Palette.ink(color), lineWidth: 2)
                                    .padding(-3)
                                    .opacity(note.color == color ? 1 : 0)
                            )
                            .padding(3.5)
                    }
                    .buttonStyle(.plain)
                    .help(color.rawValue.capitalized)
                }
            }
            Spacer(minLength: 4)
            deleteButton.fixedSize()
            copyButton(note).fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    private var deleteButton: some View {
        Button {
            if confirmingDelete {
                onDelete()
            } else {
                confirmingDelete = true
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    confirmingDelete = false
                }
            }
        } label: {
            Text(confirmingDelete ? "Confirm delete" : "Delete")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(confirmingDelete ? Color.white : Color(red: 0.75, green: 0.15, blue: 0.15))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    Capsule().fill(confirmingDelete
                        ? Color(red: 0.8, green: 0.18, blue: 0.18)
                        : Color(red: 0.8, green: 0.18, blue: 0.18).opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: confirmingDelete)
    }

    private func copyButton(_ note: Note) -> some View {
        Button {
            NoteClipboard.copy(note)
            justCopied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                justCopied = false
            }
        } label: {
            Label(justCopied ? "Copied" : "Copy", systemImage: justCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(Capsule().fill(Palette.ink(note.color)))
        }
        .buttonStyle(.plain)
        .help("Copy with formatting")
    }
}

/// Small rounded control surface used by the toolbar menus.
private struct Chip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 5) {
            content
                .font(.system(size: 12, weight: .medium))
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.4))
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black.opacity(0.06)))
    }
}

private struct FormatToggle: View {
    let symbol: String
    let active: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.black.opacity(active ? 0.16 : 0))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
