import AppKit
import EdgeNotesCore
import SwiftUI

/// Borderless, non-activating panel: it never steals focus from the app you are
/// pasting into.
final class EdgePanel: NSPanel {
    override var canBecomeKey: Bool { false }
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
    let onEdit: (UUID) -> Void
    let onNew: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            switch model.mode {
            case .collapsed:
                PillView(store: store)
            case .deck:
                DeckView(store: store, model: model, onEdit: onEdit, onNew: onNew)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

@MainActor
final class EdgePanelController {
    /// Called when the user asks to edit a note (pencil, context menu, "+").
    var onEditNote: ((UUID) -> Void)?

    let model = PanelModel()
    private let store: NoteStore
    private let panel = EdgePanel()

    /// Pending "mouse left, fold the deck" timer.
    private var collapseTask: Task<Void, Never>?
    /// Runs while the fold-back animation plays, then shrinks the panel.
    private var closeTask: Task<Void, Never>?
    /// Waits for the cursor to settle on a tab before its card slides out.
    private var dwellTask: Task<Void, Never>?
    private var dwellIndex: Int?
    private var openedAt = Date.distantPast

    /// Vertical center of the strip (and, once open, of the deck), in screen
    /// coordinates (bottom-left origin).
    private var stripY: CGFloat = 0
    private var followTarget: CGFloat = 0
    private var followTimer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(store: NoteStore) {
        self.store = store

        let host = TrackingHostingView(rootView: RootView(
            model: model,
            store: store,
            onEdit: { [weak self] in self?.edit($0) },
            onNew: { [weak self] in self?.newNote() }
        ))
        host.onMouseEntered = { [weak self] in self?.mouseEntered() }
        host.onMouseExited = { [weak self] in self?.mouseExited() }
        host.onMouseMoved = { [weak self] in self?.mouseMoved($0) }
        panel.contentView = host

        model.onModeChange = { [weak self] mode in self?.apply(mode) }

        stripY = restY
        followTarget = restY
        installCursorMonitors()
        observeNoteCount()
    }

    func show() {
        panel.setFrame(stripFrame(), display: true)
        panel.orderFrontRegardless()
    }

    /// Opens the deck even when the mouse is elsewhere (status item), then
    /// closes it again if the mouse never comes over it.
    func openDeck() {
        cancelPendingClose()
        stripY = restY
        model.go(.deck)
        scheduleCollapse(after: .seconds(3))
    }

    func newNote() {
        let note = store.add()
        edit(note.id)
    }

    private func edit(_ id: UUID) {
        beginClose()
        onEditNote?(id)
    }

    // MARK: - Strip follows the cursor

    private var screen: NSScreen? { NSScreen.screens.first }

    private var restY: CGFloat { screen?.visibleFrame.midY ?? 0 }

    /// A global monitor sees the cursor over any app without needing any permission.
    private func installCursorMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.cursorMoved() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            MainActor.assumeIsolated { self?.cursorMoved() }
            return event
        }
    }

    /// Near the right edge the strip glides to the cursor's height; away from it, back to the middle.
    private func cursorMoved() {
        guard model.mode == .collapsed, let screen else { return }
        let location = NSEvent.mouseLocation
        let nearEdge = screen.frame.contains(location)
            && location.x >= screen.frame.maxX - Layout.followDistance
        followTarget = nearEdge ? location.y : restY
        startFollowing()
    }

    private func startFollowing() {
        guard followTimer == nil else { return }
        followTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followTick() }
        }
    }

    private func followTick() {
        guard model.mode == .collapsed else { stopFollowing(); return }
        let delta = followTarget - stripY
        if abs(delta) < 0.5 {
            stripY = followTarget
            stopFollowing()
        } else {
            stripY += delta * 0.22
        }
        panel.setFrame(stripFrame(), display: true)
    }

    private func stopFollowing() {
        followTimer?.invalidate()
        followTimer = nil
    }

    // MARK: - Mouse over the panel

    private func mouseEntered() {
        switch model.mode {
        case .collapsed:
            stopFollowing()
            model.go(.deck)
        case .deck:
            cancelPendingClose()
        }
    }

    private func mouseExited() {
        guard model.mode == .deck else { return }
        cancelDwell()
        model.hover(nil)
        scheduleCollapse(after: .milliseconds(350))
    }

    private func mouseMoved(_ point: CGPoint) {
        guard model.mode == .deck, let size = panel.contentView?.bounds.size else { return }
        let geometry = DeckGeometry(panelSize: size, count: store.notes.count)
        let hoveredIndex = model.hoveredID.flatMap { id in store.notes.firstIndex { $0.id == id } }

        switch geometry.hitTest(point, hovered: hoveredIndex) {
        case .tab(let index):
            cancelPendingClose()
            guard store.notes.indices.contains(index) else { break }
            let id = store.notes[index].id
            if model.hoveredID != nil {
                // A card is already out: it follows the cursor from tab to tab.
                cancelDwell()
                model.hover(id)
            } else if dwellIndex != index {
                // Still peeking at the titles: wait for the cursor to settle first.
                startDwell(index: index, id: id)
            }
        case .card:
            cancelPendingClose()
            cancelDwell()
        case .plus, .column:
            cancelPendingClose()
            cancelDwell()
            model.hover(nil)
        case .outside:
            cancelDwell()
            model.hover(nil)
            // Do not restart the timer on every mouse-move, or it would never fire.
            if collapseTask == nil { scheduleCollapse(after: .milliseconds(350)) }
        }
    }

    /// The card slides out only after the tabs have settled *and* the cursor has rested on one.
    private func startDwell(index: Int, id: UUID) {
        dwellTask?.cancel()
        dwellIndex = index
        let sinceOpen = Date().timeIntervalSince(openedAt)
        let delay = max(0.32, 0.6 - sinceOpen)
        dwellTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.dwellIndex == index, self.model.mode == .deck else { return }
            self.dwellIndex = nil
            self.model.hover(id)
        }
    }

    private func cancelDwell() {
        dwellTask?.cancel()
        dwellTask = nil
        dwellIndex = nil
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

    /// Plays the fold-back animation, then shrinks the panel to the strip.
    private func beginClose() {
        guard model.mode == .deck else { return }
        cancelDwell()
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

    // MARK: - Geometry

    private func apply(_ mode: PanelModel.Mode) {
        switch mode {
        case .deck:
            openedAt = Date()
            // The frame changes at once; SwiftUI animates what is drawn inside it.
            panel.setFrame(deckFrame(), display: true)
            // Start hidden, then flip on the next tick so the tabs animate in.
            model.revealed = false
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(30))
                guard let self, self.model.mode == .deck, self.closeTask == nil else { return }
                self.model.revealed = true
            }
        case .collapsed:
            model.revealed = false
            panel.setFrame(stripFrame(), display: true)
            cursorMoved()
        }
    }

    private func clampedCenter(_ y: CGFloat, height: CGFloat, in visible: NSRect) -> CGFloat {
        min(max(y, visible.minY + height / 2), visible.maxY - height / 2)
    }

    private func stripFrame() -> NSRect {
        guard let screen else { return .zero }
        let height = Layout.stripHeight
        let center = clampedCenter(stripY, height: height, in: screen.visibleFrame)
        return NSRect(
            x: screen.frame.maxX - Layout.stripWidth,
            y: center - height / 2,
            width: Layout.stripWidth,
            height: height
        )
    }

    /// The deck is centered on where the strip was, so tabs appear right under the cursor.
    private func deckFrame() -> NSRect {
        guard let screen else { return .zero }
        let visible = screen.visibleFrame
        let height = DeckGeometry.panelHeight(count: store.notes.count, maxHeight: visible.height - 40)
        let center = clampedCenter(stripY, height: height, in: visible)
        return NSRect(
            x: screen.frame.maxX - Layout.deckWidth,
            y: center - height / 2,
            width: Layout.deckWidth,
            height: height
        )
    }

    /// The deck's height depends on the note count, so re-fit it when notes come and go.
    private func observeNoteCount() {
        withObservationTracking {
            _ = store.notes.count
        } onChange: { [weak self] in
            Task { @MainActor in
                if self?.model.mode == .deck, let frame = self?.deckFrame() {
                    self?.panel.setFrame(frame, display: true)
                }
                self?.observeNoteCount()
            }
        }
    }
}
