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
        // Cards and tabs draw their own shadows; a window shadow would lag the animation.
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
}

/// Hosting view that reports the mouse even while the app is inactive.
/// Points are delivered in top-left coordinates, matching `DeckGeometry`.
final class TrackingHostingView<Content: View>: NSHostingView<Content> {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onMouseMoved: ((CGPoint) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
        onMouseMoved?(topLeftPoint(for: event))
    }

    override func mouseExited(with event: NSEvent) { onMouseExited?() }
    override func mouseMoved(with event: NSEvent) { onMouseMoved?(topLeftPoint(for: event)) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func topLeftPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y)
    }
}

private struct RootView: View {
    let model: PanelModel
    let store: NoteStore
    let onNew: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            switch model.mode {
            case .collapsed:
                PillView(store: store)
            case .deck:
                DeckView(
                    store: store,
                    model: model,
                    onEdit: { model.go(.editor($0)) },
                    onNew: onNew
                )
            case .editor(let id):
                EditorView(noteID: id, store: store, onBack: { model.go(.deck) })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.mode)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

@MainActor
final class EdgePanelController {
    let model = PanelModel()
    private let store: NoteStore
    private let panel = EdgePanel()
    /// Pending "mouse left, fold the deck" timer.
    private var collapseTask: Task<Void, Never>?
    /// Runs while the fold-back animation plays, then shrinks the panel.
    private var closeTask: Task<Void, Never>?
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
        host.onMouseMoved = { [weak self] in self?.mouseMoved($0) }
        panel.contentView = host

        model.onModeChange = { [weak self] mode in self?.apply(mode) }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelResignedKey() }
        }
    }

    func show() {
        panel.setFrame(frame(for: model.mode), display: true)
        panel.orderFrontRegardless()
    }

    /// Opens the deck even when the mouse is elsewhere (status item), then
    /// closes it again if the mouse never comes over it.
    func openDeck() {
        cancelPendingClose()
        model.go(.deck)
        scheduleCollapse(after: .seconds(3))
    }

    func newNote() {
        let note = store.add()
        model.go(.editor(note.id))
    }

    // MARK: - Mouse and focus

    private func mouseEntered() {
        switch model.mode {
        case .collapsed:
            model.go(.deck)
        case .deck:
            cancelPendingClose()
        case .editor:
            break
        }
    }

    private func mouseExited() {
        guard model.mode == .deck else { return }
        model.hover(nil)
        scheduleCollapse(after: .milliseconds(350))
    }

    private func mouseMoved(_ point: CGPoint) {
        guard model.mode == .deck, let size = panel.contentView?.bounds.size else { return }
        let geometry = DeckGeometry(panelSize: size, count: store.notes.count)
        let hoveredIndex = model.hoveredID.flatMap { id in store.notes.firstIndex { $0.id == id } }

        switch geometry.hitTest(point, hovered: hoveredIndex) {
        case .tab(let index), .card(let index):
            cancelPendingClose()
            if store.notes.indices.contains(index) { model.hover(store.notes[index].id) }
        case .plus, .column:
            cancelPendingClose()
            model.hover(nil)
        case .outside:
            model.hover(nil)
            // Do not restart the timer on every mouse-move, or it would never fire.
            if collapseTask == nil { scheduleCollapse(after: .milliseconds(350)) }
        }
    }

    private func scheduleCollapse(after delay: Duration) {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.collapseTask = nil
            self.beginClose()
        }
    }

    /// Plays the fold-back animation, then shrinks the panel to the hover strip.
    private func beginClose() {
        guard model.mode == .deck else { return }
        model.hover(nil)
        model.revealed = false
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled, let self, self.model.mode == .deck else { return }
            self.closeTask = nil
            self.model.go(.collapsed)
        }
    }

    /// The mouse came back: stop any pending or running close and re-open if it had started.
    private func cancelPendingClose() {
        collapseTask?.cancel()
        collapseTask = nil
        closeTask?.cancel()
        closeTask = nil
        if model.mode == .deck, !model.revealed { model.revealed = true }
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
            model.hover(nil)
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

        // The frame changes at once; SwiftUI animates what is drawn inside it.
        panel.setFrame(frame(for: mode), display: true)

        switch mode {
        case .deck:
            // Start hidden, then flip on the next tick so the tabs animate in.
            model.revealed = false
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(30))
                guard let self, self.model.mode == .deck, self.closeTask == nil else { return }
                self.model.revealed = true
            }
        case .collapsed, .editor:
            model.revealed = false
        }
    }

    private func frame(for mode: PanelModel.Mode) -> NSRect {
        guard let screen = NSScreen.screens.first else { return .zero }
        let visible = screen.visibleFrame
        let maxHeight = visible.height - 40

        let size: NSSize
        switch mode {
        case .collapsed:
            size = NSSize(width: Layout.stripWidth, height: Layout.stripHeight)
        case .deck:
            size = NSSize(width: Layout.deckWidth, height: maxHeight)
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
}
