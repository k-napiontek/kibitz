import CoreGraphics
import Testing
@testable import KibitzCore

/// Multi-monitor geometry, checked without a second monitor.
///
/// Every case here was impossible to write while the maths lived in a private
/// method of the app executable, which is how the popup came to open on the
/// display holding the mouse rather than the one holding the text.
@Suite("PopupPlacement")
struct PopupPlacementTests {

    /// The external 1080p panel this was developed against. AppKit puts the
    /// primary screen at the origin, so its height is also the y axis that
    /// Accessibility coordinates are flipped against.
    private let primary = ScreenLayout.Screen(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055)
    )

    private let panel = CGSize(width: 440, height: 120)

    private func screen(_ frame: CGRect) -> ScreenLayout.Screen {
        ScreenLayout.Screen(frame: frame, visibleFrame: frame)
    }

    // MARK: - The common case

    @Test("a caret anchor puts the popup just below the line")
    func caretAnchorSitsBelowTheLine() {
        let anchor = TextAnchor(rect: CGRect(x: 500, y: 400, width: 1, height: 19), source: .caret)

        let point = PopupPlacement.topLeft(
            panelSize: panel, anchor: anchor, layout: ScreenLayout(screens: [primary])
        )

        // The line's bottom is 419 in Accessibility coordinates, so 661 in
        // AppKit's, and the panel hangs 14 points under it.
        #expect(point == CGPoint(x: 500, y: 647))
    }

    // MARK: - Multiple displays

    @Test("an anchor on a screen left of the primary stays on that screen")
    func anchorOnALeftHandScreenStaysThere() {
        let left = screen(CGRect(x: -1512, y: 0, width: 1512, height: 982))
        let anchor = TextAnchor(rect: CGRect(x: -1000, y: 561, width: 1, height: 19), source: .caret)

        let point = PopupPlacement.topLeft(
            panelSize: panel, anchor: anchor, layout: ScreenLayout(screens: [primary, left])
        )

        #expect(point == CGPoint(x: -1000, y: 486))
    }

    @Test("an anchor on a screen above the primary stays on that screen")
    func anchorOnAScreenAboveStaysThere() {
        let above = screen(CGRect(x: 0, y: 1080, width: 1512, height: 982))
        // Accessibility y goes negative for anything above the primary display.
        let anchor = TextAnchor(rect: CGRect(x: 300, y: -439, width: 1, height: 19), source: .caret)

        let point = PopupPlacement.topLeft(
            panelSize: panel, anchor: anchor, layout: ScreenLayout(screens: [primary, above])
        )

        #expect(point == CGPoint(x: 300, y: 1486))
    }

    @Test("a secondary screen taller than the primary is converted correctly")
    func aTallerSecondaryScreenIsConvertedCorrectly() {
        let portrait = screen(CGRect(x: 1920, y: 0, width: 1440, height: 2560))
        let anchor = TextAnchor(rect: CGRect(x: 2100, y: -939, width: 1, height: 19), source: .caret)

        let point = PopupPlacement.topLeft(
            panelSize: panel, anchor: anchor, layout: ScreenLayout(screens: [primary, portrait])
        )

        #expect(point == CGPoint(x: 2100, y: 1986))
    }

    @Test("an anchor straddling two screens picks the one it overlaps most")
    func aStraddlingAnchorPicksTheLargerOverlap() {
        let right = screen(CGRect(x: 1920, y: 0, width: 1512, height: 982))
        // 120 points of this sit on the primary and 480 on the right screen.
        let anchor = TextAnchor(rect: CGRect(x: 1800, y: 556, width: 600, height: 24), source: .fieldFrame)

        let point = PopupPlacement.topLeft(
            panelSize: panel, anchor: anchor, layout: ScreenLayout(screens: [primary, right])
        )

        #expect(point == CGPoint(x: 1928, y: 486))
    }

    @Test("the flip uses the screen at the origin even when it is not first in the list")
    func theOriginScreenIsTheOneFlippedAgainst() {
        let above = screen(CGRect(x: 0, y: 1080, width: 1512, height: 982))
        let anchor = TextAnchor(rect: CGRect(x: 500, y: 400, width: 1, height: 19), source: .caret)

        // The primary is listed second. Flipping against whatever comes first
        // would put this caret 982 points too high, on the wrong display.
        let point = PopupPlacement.topLeft(
            panelSize: panel, anchor: anchor, layout: ScreenLayout(screens: [above, primary])
        )

        #expect(point == CGPoint(x: 500, y: 647))
    }

    @Test("an anchor that intersects no screen picks the nearest one")
    func anOffScreenAnchorPicksTheNearestScreen() {
        let right = screen(CGRect(x: 1920, y: 0, width: 1512, height: 982))
        let anchor = TextAnchor(rect: CGRect(x: 5000, y: 561, width: 1, height: 19), source: .caret)

        let point = PopupPlacement.topLeft(
            panelSize: panel, anchor: anchor, layout: ScreenLayout(screens: [primary, right])
        )

        #expect(point == CGPoint(x: 2984, y: 486))
    }

    @Test("an empty screen list produces no placement")
    func noScreensProducesNoPlacement() {
        let anchor = TextAnchor(rect: CGRect(x: 500, y: 400, width: 1, height: 19), source: .caret)

        let point = PopupPlacement.topLeft(
            panelSize: panel, anchor: anchor, layout: ScreenLayout(screens: [])
        )

        #expect(point == nil)
    }

    // MARK: - Staying on screen

    @Test("an anchor near the bottom of a screen flips the popup above the text")
    func aLowAnchorFlipsThePopupAbove() {
        let docked = ScreenLayout.Screen(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 70, width: 1920, height: 985)
        )
        let anchor = TextAnchor(rect: CGRect(x: 600, y: 961, width: 1, height: 19), source: .caret)

        let point = PopupPlacement.topLeft(
            panelSize: panel, anchor: anchor, layout: ScreenLayout(screens: [docked])
        )

        // The text occupies 100 to 119 in AppKit coordinates. The panel's bottom
        // edge lands above that rather than being clipped by the Dock.
        #expect(point == CGPoint(x: 600, y: 253))
        #expect((point?.y ?? 0) - panel.height > 119)
    }

    @Test("an anchor at the right edge is clamped inside the visible frame")
    func aRightEdgeAnchorIsClamped() {
        let anchor = TextAnchor(rect: CGRect(x: 1800, y: 400, width: 1, height: 19), source: .caret)

        let point = PopupPlacement.topLeft(
            panelSize: panel, anchor: anchor, layout: ScreenLayout(screens: [primary])
        )

        #expect(point == CGPoint(x: 1472, y: 647))
    }

    @Test("a panel taller than the visible frame is not placed off the top")
    func anOversizedPanelIsPinnedToTheTop() {
        let small = ScreenLayout.Screen(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 580)
        )
        let anchor = TextAnchor(rect: CGRect(x: 100, y: 100, width: 1, height: 19), source: .caret)

        let point = PopupPlacement.topLeft(
            panelSize: CGSize(width: 440, height: 700), anchor: anchor,
            layout: ScreenLayout(screens: [small])
        )

        #expect(point == CGPoint(x: 100, y: 572))
    }

    // MARK: - Provenance changes the rule

    @Test("a field frame far wider than the panel centres the popup on the text")
    func aWideFieldFrameIsCentred() {
        // Chrome's omnibox, as captured in the diagnostics log. Left-aligning to
        // its minX threw the popup at the far-left edge of the window.
        let anchor = TextAnchor(rect: CGRect(x: 158, y: 82, width: 1194, height: 24), source: .fieldFrame)

        let point = PopupPlacement.topLeft(
            panelSize: panel, anchor: anchor, layout: ScreenLayout(screens: [primary])
        )

        #expect(point == CGPoint(x: 535, y: 960))
    }

    @Test("a fractional centre is rounded to whole points")
    func aFractionalCentreIsRounded() {
        // Chrome's omnibox is an odd number of points wide, so centring lands on
        // a half point. AppKit snaps that itself when placing the panel, which
        // makes the computed origin and the placed frame disagree in the log and
        // costs the invariant those lines exist to prove.
        let anchor = TextAnchor(rect: CGRect(x: 171, y: 82, width: 1181, height: 24), source: .fieldFrame)

        let point = PopupPlacement.topLeft(
            panelSize: panel, anchor: anchor, layout: ScreenLayout(screens: [primary])
        )

        #expect(point == CGPoint(x: 542, y: 960))
    }

    @Test("a window anchor sits inside the bottom of that window")
    func aWindowAnchorSitsInsideTheWindow() {
        let anchor = TextAnchor(rect: CGRect(x: 100, y: 100, width: 800, height: 600), source: .window)

        let point = PopupPlacement.topLeft(
            panelSize: panel, anchor: anchor, layout: ScreenLayout(screens: [primary])
        )

        // The window spans 380 to 980 in AppKit coordinates. The panel sits just
        // inside its bottom edge, centred, rather than below the whole window.
        #expect(point == CGPoint(x: 280, y: 514))
    }
}
