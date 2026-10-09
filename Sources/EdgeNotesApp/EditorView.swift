import AppKit
import EdgeNotesCore
import SwiftUI

struct EditorView: View {
    let noteID: UUID
    let store: NoteStore
    let onBack: () -> Void

    @State private var controller = RichTextController()
    @State private var justCopied = false

    private static let curatedFamilies = [
        "Helvetica Neue", "Avenir Next", "Georgia", "Times New Roman", "Menlo", "Courier New",
    ]
    private static let sizes: [CGFloat] = [10, 12, 14, 16, 18, 24, 32, 48]

    var body: some View {
        if let note = store.note(id: noteID) {
            VStack(spacing: 0) {
                header(note)
                Divider()
                formattingBar
                Divider()
                RichTextEditor(
                    initialRTF: note.body,
                    paper: Palette.paper(for: note.color),
                    controller: controller,
                    onChange: { store.update(id: noteID, body: $0) }
                )
                .id(noteID)
            }
            .background(.regularMaterial, in: edgeShape)
            .overlay(edgeShape.strokeBorder(.primary.opacity(0.12)))
        }
    }

    private var edgeShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
    }

    // MARK: - Header

    private func header(_ note: Note) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: onBack) { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                    .help("Back to notes")
                TextField("Title", text: Binding(
                    get: { note.title },
                    set: { store.update(id: noteID, title: $0) }
                ))
                .textFieldStyle(.plain)
                .font(.headline)
                Button {
                    NoteClipboard.copy(note)
                    justCopied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        justCopied = false
                    }
                } label: {
                    Label(justCopied ? "Copied" : "Copy", systemImage: justCopied ? "checkmark" : "doc.on.doc")
                }
                .help("Copy with formatting")
            }
            HStack(spacing: 6) {
                ForEach(NoteColor.allCases, id: \.self) { color in
                    Circle()
                        .fill(Palette.color(color))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.primary, lineWidth: note.color == color ? 2 : 0).padding(-3))
                        .onTapGesture { store.update(id: noteID, color: color) }
                        .help(color.rawValue.capitalized)
                }
                Spacer()
            }
            .padding(.leading, 4)
        }
        .padding(12)
    }

    // MARK: - Formatting

    private var formattingBar: some View {
        HStack(spacing: 4) {
            Menu {
                Button("System") { controller.setFamily(nil) }
                ForEach(Self.curatedFamilies, id: \.self) { family in
                    Button(family) { controller.setFamily(family) }
                }
                Divider()
                Menu("All Fonts") {
                    ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { family in
                        Button(family) { controller.setFamily(family) }
                    }
                }
            } label: {
                Image(systemName: "textformat")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Font")

            Menu {
                ForEach(Self.sizes, id: \.self) { size in
                    Button("\(Int(size)) pt") { controller.setSize(size) }
                }
            } label: {
                Image(systemName: "textformat.size")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Size")

            Divider().frame(height: 16)

            Button { controller.toggleBold() } label: { Image(systemName: "bold") }
                .help("Bold")
            Button { controller.toggleItalic() } label: { Image(systemName: "italic") }
                .help("Italic")
            Button { controller.toggleUnderline() } label: { Image(systemName: "underline") }
                .help("Underline")

            Divider().frame(height: 16)

            ForEach(Array(Palette.textSwatches.enumerated()), id: \.offset) { _, swatch in
                Button { controller.setColor(swatch.color) } label: {
                    if let color = swatch.color {
                        Circle().fill(Color(nsColor: color)).frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "circle.slash").frame(width: 14, height: 14)
                    }
                }
                .help("Text color: \(swatch.name)")
            }
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .frame(height: 34)
    }
}
