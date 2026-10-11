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
    let onCopied: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            switch model.mode {
            case .collapsed:
                PillView(store: store)
            case .deck:
                DeckView(store: store, model: model, onEdit: onEdit, onNew: onNew, onCopied: onCopied)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

/// The edge shelf. It only reacts to what you touch: the dots, then a tab, then
/// its card. It never moves on its own.
@MainActor
final class EdgePanelController {
    /// Called when the user asks to edit a note (pencil, context menu, "+").
    var onEditNote: ((UUID) -> Void)?

    let model = PanelModel()
    private let store: NoteStore
    private let panel = EdgePanel()

    /// Short pause before touching the dots opens the deck, so brushing past the
    /// edge on the way elsewhere does nothing.
    private var openIntentTask: Task<Void, Never>?
    /// Pending "mouse left, fold the deck" timer.
    private var collapseTask: Task<Void, Never>?
    /// Runs while the fold-back animation plays, then shrinks the panel.
    private var closeTask: Task<Void, Never>?
    /// Waits for the cursor to settle on a tab before its card slides out.
    private var dwellTask: Task<Void, Never>?
    private var dwellIndex: Int?
    private var openedAt = Date.distantPast

    /// True from the moment the deck is dismissed on purpose (copied, editing)
    /// until it has folded away, so stray mouse movement cannot reopen it midway.
    private var isDismissing = false
    private var dismissTask: Task<Void, Never>?
    /// After a deliberate dismissal the cursor may still be sitting on the dots.
    /// Until it leaves that zone once, touching them again is not a request to open,
    /// so a click never turns into a reopen.
    private var awaitingExit = false

    init(store: NoteStore) {
        self.store = store

        let host = TrackingHostingView(rootView: RootView(
            model: model,
            store: store,
            onEdit: { [weak self] in self?.edit($0) },
            onNew: { [weak self] in self?.newNote() },
            onCopied: { [weak self] in self?.copied() }
        ))
        host.onMouseEntered = { [weak self] in self?.mouseEntered() }
        host.onMouseExited = { [weak self] in self?.mouseExited() }
        host.onMouseMoved = { [weak self] in self?.mouseMoved($0) }
        panel.contentView = host

        model.onModeChange = { [weak self] mode in self?.apply(mode) }
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
        model.go(.deck)
        scheduleCollapse(after: .seconds(3))
    }

    func newNote() {
        let note = store.add()
        edit(note.id)
    }

    // MARK: - Deliberate dismissal

    private func edit(_ id: UUID) {
        dismissDeck(after: .zero)
        onEditNote?(id)
    }

    /// A click on a note means "use it": show the check for a beat, then get out of the way.
    private func copied() {
        dismissDeck(after: .milliseconds(750))
    }

    private func dismissDeck(after delay: Duration) {
        isDismissing = true
        // No card should pop open while the shelf is on its way out.
        cancelDwell()
        collapseTask?.cancel()
        collapseTask = nil
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.dismissTask = nil
            self.beginClose()
        }
    }

    // MARK: - Mouse over the panel

    private func mouseEntered() {
        switch model.mode {
        case .collapsed:
            beginOpenIntent()
        case .deck:
            guard !isDismissing else { return }
            cancelPendingClose()
        }
    }

    private func mouseExited() {
        switch model.mode {
        case .collapsed:
            openIntentTask?.cancel()
            openIntentTask = nil
            // Trust where the cursor really is, not the event: resizing the panel can
            // deliver an exit while the cursor has not moved.
            if !stripFrame().contains(NSEvent.mouseLocation) { awaitingExit = false }
        case .deck:
            guard !isDismissing else { return }
            cancelDwell()
            model.hover(nil)
            scheduleCollapse(after: .milliseconds(350))
        }
    }

    private func mouseMoved(_ point: CGPoint) {
        switch model.mode {
        case .collapsed:
            // Moving within the zone around the dots counts as touching them.
            if openIntentTask == nil { beginOpenIntent() }
        case .deck:
            guard !isDismissing else { return }
            deckMouseMoved(point)
        }
    }

    private func beginOpenIntent() {
        guard openIntentTask == nil, !awaitingExit else { return }
        openIntentTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, let self else { return }
            self.openIntentTask = nil
            guard self.model.mode == .collapsed, !self.awaitingExit else { return }
            self.model.go(.deck)
        }
    }

    private func deckMouseMoved(_ point: CGPoint) {
        guard let size = panel.contentView?.bounds.size else { return }
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
        let delay = max(0.4, 0.7 - sinceOpen)
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
            try? await Task.sleep(for: .milliseconds(620))
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

    private var screen: NSScreen? { NSScreen.screens.first }

    /// The dots live at a fixed spot: the vertical middle of the right edge.
    private var restY: CGFloat { screen?.visibleFrame.midY ?? 0 }

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
            let strip = stripFrame()
            // Dismissed on purpose with the cursor still over the dots: wait for it to leave.
            awaitingExit = isDismissing && strip.contains(NSEvent.mouseLocation)
            isDismissing = false
            panel.setFrame(strip, display: true)
        }
    }

    private func clampedCenter(_ y: CGFloat, height: CGFloat, in visible: NSRect) -> CGFloat {
        min(max(y, visible.minY + height / 2), visible.maxY - height / 2)
    }

    /// Just taller than the capsule, so the target is forgiving without being greedy.
    private func stripFrame() -> NSRect {
        guard let screen else { return .zero }
        let height = DashLayout.containerHeight(count: store.notes.count) + 2 * Layout.stripSlop
        let center = clampedCenter(restY, height: height, in: screen.visibleFrame)
        return NSRect(
            x: screen.frame.maxX - Layout.stripWidth,
            y: center - height / 2,
            width: Layout.stripWidth,
            height: height
        )
    }

    /// The deck is centered on the dots, so each dash grows into the tab right where it was.
    private func deckFrame() -> NSRect {
        guard let screen else { return .zero }
        let visible = screen.visibleFrame
        let height = DeckGeometry.panelHeight(count: store.notes.count, maxHeight: visible.height - 40)
        let center = clampedCenter(restY, height: height, in: visible)
        return NSRect(
            x: screen.frame.maxX - Layout.deckWidth,
            y: center - height / 2,
            width: Layout.deckWidth,
            height: height
        )
    }

    /// Both frames depend on the note count, so re-fit them when notes come and go.
    private func observeNoteCount() {
        withObservationTracking {
            _ = store.notes.count
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                switch self.model.mode {
                case .deck: self.panel.setFrame(self.deckFrame(), display: true)
                case .collapsed: self.panel.setFrame(self.stripFrame(), display: true)
                }
                self.observeNoteCount()
            }
        }
    }
}
