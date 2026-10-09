import CoreGraphics

/// Layout of the edge deck: a column of tabs flush with the right edge, a "+"
/// button under it, and one card that slides out of the hovered tab.
///
/// All rects use a top-left origin, like SwiftUI. The same numbers drive both
/// drawing and mouse hit-testing, so what you see is what you can hover.
public struct DeckGeometry: Equatable, Sendable {
    public static let tabWidth: CGFloat = 34
    public static let tabHeight: CGFloat = 58
    public static let maxStep: CGFloat = 54
    public static let minStep: CGFloat = 16
    public static let plusSize: CGFloat = 26
    public static let plusGap: CGFloat = 12
    public static let cardWidth: CGFloat = 252
    public static let cardHeight: CGFloat = 150
    public static let edgeMargin: CGFloat = 8
    /// Extra hover room to the left of the tab column.
    public static let hoverSlop: CGFloat = 6

    public enum Hit: Equatable, Sendable {
        case tab(Int)
        case card(Int)
        case plus
        /// Inside the tab column but between items (keeps the deck open).
        case column
        case outside
    }

    public let panelSize: CGSize
    public let count: Int

    public init(panelSize: CGSize, count: Int) {
        self.panelSize = panelSize
        self.count = count
    }

    private var reservedHeight: CGFloat {
        2 * Self.edgeMargin + Self.plusGap + Self.plusSize + Self.tabHeight
    }

    /// How many tabs fit at the tightest spacing. Notes beyond this are not drawn,
    /// so a tab can never fall outside the panel.
    public var visibleCount: Int {
        let fitting = Int(((panelSize.height - reservedHeight) / Self.minStep).rounded(.down)) + 1
        return max(0, min(count, fitting))
    }

    /// Vertical distance between consecutive tabs; tabs overlap and tighten as notes pile up.
    public var step: CGFloat {
        let shown = visibleCount
        guard shown > 1 else { return Self.maxStep }
        let available = panelSize.height - reservedHeight
        return min(Self.maxStep, max(Self.minStep, available / CGFloat(shown - 1)))
    }

    private var stackHeight: CGFloat {
        visibleCount == 0 ? 0 : CGFloat(visibleCount - 1) * step + Self.tabHeight
    }

    private var groupHeight: CGFloat {
        visibleCount == 0 ? Self.plusSize : stackHeight + Self.plusGap + Self.plusSize
    }

    private var top: CGFloat {
        max(Self.edgeMargin, (panelSize.height - groupHeight) / 2)
    }

    public func tabRect(_ index: Int) -> CGRect {
        CGRect(
            x: panelSize.width - Self.tabWidth,
            y: top + CGFloat(index) * step,
            width: Self.tabWidth,
            height: Self.tabHeight
        )
    }

    public var plusRect: CGRect {
        CGRect(
            x: panelSize.width - Self.tabWidth / 2 - Self.plusSize / 2,
            y: visibleCount == 0 ? top : top + stackHeight + Self.plusGap,
            width: Self.plusSize,
            height: Self.plusSize
        )
    }

    /// The card is centered on its tab, then nudged to stay fully inside the panel.
    public func cardRect(for index: Int) -> CGRect {
        let tab = tabRect(index)
        let lowest = max(Self.edgeMargin, panelSize.height - Self.edgeMargin - Self.cardHeight)
        let y = min(max(tab.midY - Self.cardHeight / 2, Self.edgeMargin), lowest)
        return CGRect(
            x: panelSize.width - Self.cardWidth,
            y: y,
            width: Self.cardWidth,
            height: Self.cardHeight
        )
    }

    public func hitTest(_ point: CGPoint, hovered: Int?) -> Hit {
        if let hovered, hovered >= 0, hovered < visibleCount, cardRect(for: hovered).contains(point) {
            return .card(hovered)
        }
        if plusRect.insetBy(dx: -6, dy: -6).contains(point) { return .plus }

        let columnMinX = panelSize.width - Self.tabWidth - Self.hoverSlop
        guard point.x >= columnMinX, point.x <= panelSize.width else { return .outside }

        if visibleCount > 0, point.y >= top, point.y < top + stackHeight {
            // Each tab owns a horizontal band `step` tall, so there are no dead gaps.
            let index = min(visibleCount - 1, Int((point.y - top) / step))
            return .tab(index)
        }
        if point.y >= top, point.y <= top + groupHeight { return .column }
        return .outside
    }
}
