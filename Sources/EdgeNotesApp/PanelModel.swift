import Foundation
import Observation

/// What the edge panel is currently showing.
@MainActor
@Observable
final class PanelModel {
    enum Mode: Equatable {
        case collapsed
        case deck
    }

    private(set) var mode: Mode = .collapsed

    /// Drives the open/close animation inside the deck: tabs slide in when true.
    var revealed = false

    /// The cursor is on the dots but has not committed yet: the capsule lights up
    /// at once so the shelf feels responsive while the intent pause filters accidents.
    var hot = false

    /// Note whose card is currently slid out of its tab.
    private(set) var hoveredID: UUID?

    @ObservationIgnored var onModeChange: ((Mode) -> Void)?

    func go(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        onModeChange?(newMode)
    }

    func hover(_ id: UUID?) {
        guard id != hoveredID else { return }
        hoveredID = id
    }
}
