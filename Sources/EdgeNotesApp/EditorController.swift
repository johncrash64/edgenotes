import AppKit
import EdgeNotesCore
import SwiftUI

/// Borderless floating window for the editor. Unlike the edge panel it takes
/// keyboard focus, because you type in it.
final class EditorPanel: NSPanel {
    var onCloseShortcut: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        // The card draws its own shadow so it can animate with it.
        hasShadow = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "w" {
            onCloseShortcut?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Owns the editor window for one note at a time.
@MainActor
final class EditorController {
    private let store: NoteStore
    private var panel: EditorPanel?
    private var model: EditorModel?
    private var resignObserver: NSObjectProtocol?
    private var isClosing = false
    /// The app you were working in when the editor opened, so closing returns you to it.
    private var previousApp: NSRunningApplication?

    init(store: NoteStore) {
        self.store = store
    }

    func open(noteID: UUID) {
        guard store.note(id: noteID) != nil else { return }
        if let panel, model?.noteID == noteID, !isClosing {
            bringToFront(panel)
            return
        }
        teardown()

        // Remember where you came from, unless that is us (e.g. replacing one editor with another).
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }

        let model = EditorModel(noteID: noteID)
        let controller = RichTextController()
        controller.onStateChange = { [weak model] state in model?.format = state }

        let view = EditorView(
            store: store,
            model: model,
            controller: controller,
            onClose: { [weak self] in self?.close() },
            onDelete: { [weak self] in self?.deleteNote() }
        )
        let margin = EditorView.margin * 2
        let size = NSSize(
            width: EditorView.cardSize.width + margin,
            height: EditorView.cardSize.height + margin
        )
        let panel = EditorPanel(size: size)
        panel.contentView = NSHostingView(rootView: view)
        panel.onCloseShortcut = { [weak self] in self?.close() }
        if let screen = NSScreen.screens.first {
            let visible = screen.visibleFrame
            panel.setFrame(
                NSRect(
                    x: visible.midX - size.width / 2,
                    y: visible.midY - size.height / 2 + 16,
                    width: size.width,
                    height: size.height
                ),
                display: true
            )
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelResignedKey() }
        }

        self.panel = panel
        self.model = model
        bringToFront(panel)
        // Flip on the next tick so the pop-in animates instead of appearing already open.
        DispatchQueue.main.async { model.appeared = true }
    }

    /// - Parameter restoreFocus: give the focus back to the app you came from. Not
    ///   wanted when the editor closes because you clicked another app: you already chose.
    func close(restoreFocus: Bool = true) {
        guard let panel, let model, !isClosing else { return }
        isClosing = true
        store.flush()
        model.appeared = false
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard let self, self.panel === panel else { return }
            self.teardown()
            if restoreFocus { self.returnFocus() }
            self.previousApp = nil
        }
    }

    // MARK: - Private

    private func bringToFront(_ panel: EditorPanel) {
        panel.makeKeyAndOrderFront(nil)
        // `activate()` alone is cooperative on macOS 14+ and does not take focus
        // from another app; the user just asked for this window, so force it.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// `NSApp.deactivate()` alone leaves us frontmost on macOS 14, so name the app to
    /// hand activation to.
    private func returnFocus() {
        if let app = previousApp, !app.isTerminated {
            NSApp.yieldActivation(to: app)
            app.activate()
        } else {
            NSApp.deactivate()
        }
    }

    private func deleteNote() {
        guard let id = model?.noteID else { return }
        store.delete(id: id)
        close()
    }

    private func panelResignedKey() {
        guard let panel, let model, !isClosing, !model.pinned else { return }
        // A menu in the toolbar can bounce key status; only close if focus truly left.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, self.panel === panel, !panel.isKeyWindow, !model.pinned else { return }
            self.close(restoreFocus: false)
        }
    }

    private func teardown() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
        isClosing = false
    }
}
