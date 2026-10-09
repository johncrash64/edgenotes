import CoreGraphics
import Testing

@testable import EdgeNotesCore

@Suite struct DeckGeometryTests {
    private let panel = CGSize(width: 300, height: 560)

    @Test func tabsAreFlushWithRightEdgeAndStackDownward() {
        let g = DeckGeometry(panelSize: panel, count: 4)
        for index in 0..<4 {
            #expect(g.tabRect(index).maxX == panel.width)
            #expect(g.tabRect(index).minY >= 0 && g.tabRect(index).maxY <= panel.height)
        }
        #expect(g.tabRect(1).minY - g.tabRect(0).minY == g.step)
        #expect(g.tabRect(0).minY < g.tabRect(3).minY)
    }

    @Test func stackIsVerticallyCentered() {
        let g = DeckGeometry(panelSize: panel, count: 3)
        let groupTop = g.tabRect(0).minY
        let groupBottom = g.plusRect.maxY
        #expect(abs(groupTop - (panel.height - groupBottom)) < 0.5)
    }

    @Test func stepTightensWithManyNotesButKeepsEverythingInside() {
        let tall = CGSize(width: 300, height: 900)
        let few = DeckGeometry(panelSize: tall, count: 3)
        let many = DeckGeometry(panelSize: tall, count: 30)
        #expect(many.visibleCount == 30)
        #expect(many.step < few.step)
        #expect(many.step >= DeckGeometry.minStep)
        #expect(many.tabRect(29).maxY <= tall.height)
        #expect(many.plusRect.maxY <= tall.height)
    }

    @Test func overflowShowsOnlyWhatFitsNeverOffscreen() {
        let g = DeckGeometry(panelSize: panel, count: 500)
        #expect(g.visibleCount < 500)
        #expect(g.visibleCount > 0)
        #expect(g.tabRect(g.visibleCount - 1).maxY <= panel.height)
        #expect(g.plusRect.maxY <= panel.height)
    }

    @Test func cardStaysInsidePanelEvenForFirstAndLastTab() {
        let g = DeckGeometry(panelSize: panel, count: 12)
        for index in [0, 11] {
            let card = g.cardRect(for: index)
            #expect(card.minY >= DeckGeometry.edgeMargin)
            #expect(card.maxY <= panel.height - DeckGeometry.edgeMargin)
            #expect(card.maxX == panel.width)
        }
    }

    @Test func hitTestFindsTabByBandWithoutGaps() {
        let g = DeckGeometry(panelSize: panel, count: 4)
        let x = panel.width - 10
        for index in 0..<4 {
            let rect = g.tabRect(index)
            #expect(g.hitTest(CGPoint(x: x, y: rect.minY + 1), hovered: nil) == .tab(index))
        }
        // Boundary between tab 0 and tab 1 belongs to exactly one of them.
        let boundary = g.tabRect(1).minY
        #expect(g.hitTest(CGPoint(x: x, y: boundary - 0.1), hovered: nil) == .tab(0))
        #expect(g.hitTest(CGPoint(x: x, y: boundary), hovered: nil) == .tab(1))
    }

    @Test func cardWinsOverTabsWhereTheyOverlap() {
        let g = DeckGeometry(panelSize: panel, count: 6)
        let card = g.cardRect(for: 2)
        let point = CGPoint(x: card.midX, y: card.midY)
        #expect(g.hitTest(point, hovered: 2) == .card(2))
        #expect(g.hitTest(point, hovered: nil) == .outside, "no card shown, empty space is outside")
    }

    @Test func plusAndOutsideAreDetected() {
        let g = DeckGeometry(panelSize: panel, count: 3)
        #expect(g.hitTest(CGPoint(x: g.plusRect.midX, y: g.plusRect.midY), hovered: nil) == .plus)
        #expect(g.hitTest(CGPoint(x: 10, y: 10), hovered: nil) == .outside)
    }

    @Test func emptyDeckStillHasPlus() {
        let g = DeckGeometry(panelSize: panel, count: 0)
        #expect(g.hitTest(CGPoint(x: g.plusRect.midX, y: g.plusRect.midY), hovered: nil) == .plus)
        #expect(g.hitTest(CGPoint(x: panel.width - 10, y: 5), hovered: nil) == .outside)
    }

    @Test func staleHoveredIndexIsIgnored() {
        let g = DeckGeometry(panelSize: panel, count: 2)
        #expect(g.hitTest(CGPoint(x: 100, y: 100), hovered: 7) == .outside)
    }

    @Test func panelHeightFitsStackWithoutTighteningAndFitsACard() {
        let one = DeckGeometry.panelHeight(count: 1, maxHeight: 800)
        #expect(one >= DeckGeometry.cardHeight + 2 * DeckGeometry.edgeMargin)

        let five = DeckGeometry.panelHeight(count: 5, maxHeight: 800)
        let g = DeckGeometry(panelSize: CGSize(width: 300, height: five), count: 5)
        #expect(g.step == DeckGeometry.maxStep, "a roomy panel does not tighten the tabs")
        #expect(g.visibleCount == 5)
        #expect(five > one)
    }

    @Test func panelHeightIsCapped() {
        #expect(DeckGeometry.panelHeight(count: 500, maxHeight: 700) == 700)
    }
}
