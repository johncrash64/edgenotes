import Foundation
import Observation

/// What the edge panel is currently showing.
@MainActor
@Observable
final class PanelModel {
    enum Mode: Equatable {
        case collapsed
        case deck
        case editor(UUID)
    }

    private(set) var mode: Mode = .collapsed

    @ObservationIgnored var onModeChange: ((Mode) -> Void)?

    func go(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        onModeChange?(newMode)
    }
}
