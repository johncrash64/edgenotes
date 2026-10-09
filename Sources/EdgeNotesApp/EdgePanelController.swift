import AppKit
import EdgeNotesCore
import SwiftUI

/// Borderless, non-activating panel: it never steals focus from the app you are
/// pasting into, but can still become key so the editor receives typing.
final class EdgePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
}

/// Hosting view that reports mouse enter/exit even while the app is inactive.
final class TrackingHostingView<Content: View>: NSHostingView<Content> {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onMouseEntered?() }
    override func mouseExited(with event: NSEvent) { onMouseExited?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct RootView: View {
    let model: PanelModel
    let store: NoteStore
    let onNew: () -> Void

    var body: some View {
        Group {
            switch model.mode {
            case .collapsed:
                PillView(store: store)
            case .deck:
                DeckView(store: store, onEdit: { model.go(.editor($0)) }, onNew: onNew)
            case .editor(let id):
                EditorView(noteID: id, store: store, onBack: { model.go(.deck) })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

@MainActor
final class EdgePanelController {
    let model = PanelModel()
    private let store: NoteStore
    private let panel = EdgePanel()
    private var collapseTask: Task<Void, Never>?
    private var resignObserver: NSObjectProtocol?
    private var isEditing = false

    init(store: NoteStore) {
        self.store = store

        let host = TrackingHostingView(rootView: RootView(
            model: model,
            store: store,
            onNew: { [weak self] in self?.newNote() }
        ))
        host.onMouseEntered = { [weak self] in self?.mouseEntered() }
        host.onMouseExited = { [weak self] in self?.mouseExited() }
        panel.contentView = host

        model.onModeChange = { [weak self] mode in self?.apply(mode) }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelResignedKey() }
        }

        observeNoteCount()
    }

    func show() {
        panel.setFrame(frame(for: model.mode), display: true)
        panel.orderFrontRegardless()
    }

    /// Opens the deck even when the mouse is elsewhere (status item), then
    /// closes it again if the mouse never comes over it.
    func openDeck() {
        model.go(.deck)
        scheduleCollapse(after: .seconds(3))
    }

    func newNote() {
        let note = store.add()
        model.go(.editor(note.id))
    }

    // MARK: - Mouse and focus

    private func mouseEntered() {
        collapseTask?.cancel()
        if model.mode == .collapsed { model.go(.deck) }
    }

    private func mouseExited() {
        scheduleCollapse(after: .milliseconds(350))
    }

    private func scheduleCollapse(after delay: Duration) {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.model.mode == .deck else { return }
            self.model.go(.collapsed)
        }
    }

    private func panelResignedKey() {
        guard case .editor = model.mode else { return }
        // A menu in the toolbar can bounce key status; only collapse if focus truly left.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, case .editor = self.model.mode, !self.panel.isKeyWindow else { return }
            self.store.flush()
            self.model.go(.collapsed)
        }
    }

    // MARK: - Geometry

    private func apply(_ mode: PanelModel.Mode) {
        let wasEditing = isEditing
        isEditing = { if case .editor = mode { true } else { false } }()

        if isEditing {
            // Typing needs a real key window. Hovering and copying never activate
            // the app (so your paste target keeps focus); editing does, like any window.
            panel.makeKeyAndOrderFront(nil)
            // `activate()` alone is cooperative on macOS 14+ and does not take focus
            // from another app; the user just asked for this window, so force it.
            NSApp.activate(ignoringOtherApps: true)
        } else if wasEditing {
            // Hand focus back to the app the user was working in.
            NSApp.deactivate()
        }
        setFrame(frame(for: mode), animated: true)
    }

    private func refreshFrame() {
        setFrame(frame(for: model.mode), animated: false)
    }

    private func setFrame(_ frame: NSRect, animated: Bool) {
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().setFrame(frame, display: true)
            } completionHandler: { [panel] in
                MainActor.assumeIsolated { panel.invalidateShadow() }
            }
        } else {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
        }
    }

    private func frame(for mode: PanelModel.Mode) -> NSRect {
        guard let screen = NSScreen.screens.first else { return .zero }
        let visible = screen.visibleFrame
        let maxHeight = visible.height - 40
        let count = store.notes.count

        let size: NSSize
        switch mode {
        case .collapsed:
            size = NSSize(width: Layout.pillWidth, height: Layout.hoverStripHeight)
        case .deck:
            let rows = CGFloat(max(count, 2))
            size = NSSize(
                width: Layout.deckWidth,
                height: min(maxHeight, rows * Layout.rowHeight + Layout.footerHeight + 12)
            )
        case .editor:
            size = NSSize(width: Layout.editorWidth, height: min(maxHeight, 560))
        }
        return NSRect(
            x: screen.frame.maxX - size.width,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// The pill and the deck are sized from the note count, so re-fit when it changes.
    private func observeNoteCount() {
        withObservationTracking {
            _ = store.notes.count
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshFrame()
                self?.observeNoteCount()
            }
        }
    }
}
