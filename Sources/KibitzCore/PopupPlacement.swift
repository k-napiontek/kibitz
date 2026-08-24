import CoreGraphics

/// Where an anchor rect came from.
///
/// Provenance decides the placement rule. Glyph bounds are the text itself, so
/// the popup hangs under their left edge. A field or a window is a container
/// that can be far wider than what was written - Chrome reports a 1194 point
/// wide omnibox - and left-aligning to that throws the popup at an edge, so
/// containers are centred instead.
public enum AnchorSource: String, Sendable, Equatable {
    case selection
    case caret
    case textMarker
    case line
    case fieldFrame
    case window
}

/// A text position in Accessibility coordinates: the origin is the top left of
/// the primary display and y grows downwards.
public struct TextAnchor: Sendable, Equatable {
    public let rect: CGRect
    public let source: AnchorSource

    public init(rect: CGRect, source: AnchorSource) {
        self.rect = rect
        self.source = source
    }

    /// True when the rect encloses actual glyphs rather than a container.
    public var isGlyphLevel: Bool {
        switch source {
        case .selection, .caret, .textMarker, .line: true
        case .fieldFrame, .window: false
        }
    }
}

/// The displays, as AppKit describes them.
///
/// Injected rather than read from `NSScreen` so that multi-monitor placement can
/// be tested without a second monitor, which is why none of this was caught.
public struct ScreenLayout: Sendable, Equatable {

    public struct Screen: Sendable, Equatable {
        public let frame: CGRect
        /// The frame minus the menu bar and the Dock.
        public let visibleFrame: CGRect

        public init(frame: CGRect, visibleFrame: CGRect) {
            self.frame = frame
            self.visibleFrame = visibleFrame
        }
    }

    /// Index 0 is the primary display: the one AppKit puts at the origin, and
    /// the one Accessibility measures every other display against.
    public let screens: [Screen]

    public init(screens: [Screen]) {
        self.screens = screens
    }

    /// The display everything else is measured against: the one AppKit puts at
    /// the origin, which is the one carrying the menu bar.
    ///
    /// Conventionally that is `screens[0]`, but deriving it costs a line and
    /// removes an assumption that would silently flip the popup onto the wrong
    /// display if it ever failed to hold.
    public var primary: Screen? {
        screens.first { $0.frame.origin == .zero } ?? screens.first
    }
}

/// Decides where the popup goes, given where the text is.
///
/// Pure on purpose. The pointer is not an input here and cannot become one: the
/// popup used to fall back to `NSEvent.mouseLocation` whenever Accessibility
/// gave up, which put it on whichever display the mouse happened to rest on.
public enum PopupPlacement {

    /// Clearance between the text and the panel. At 6 the panel sat directly on
    /// the line it was correcting.
    public static let defaultGap: CGFloat = 14

    /// Kept between the panel and the edge of the screen.
    private static let margin: CGFloat = 8

    /// The panel's top-left corner in AppKit coordinates, or nil when there is
    /// no display to place it on - a locked screen, or every monitor unplugged.
    public static func topLeft(
        panelSize: CGSize,
        anchor: TextAnchor,
        layout: ScreenLayout,
        gap: CGFloat = defaultGap
    ) -> CGPoint? {
        guard let primary = layout.primary else { return nil }

        let rect = appKitRect(anchor.rect, primaryHeight: primary.frame.maxY)
        let visible = (screen(for: rect, in: layout) ?? primary).visibleFrame

        var point = CGPoint(
            x: anchor.isGlyphLevel ? rect.minX : rect.midX - panelSize.width / 2,
            y: anchor.source == .window
                // A window is not text to sit under: sit just inside its bottom
                // edge, so the popup still covers the app it belongs to.
                ? rect.minY + gap + panelSize.height
                : rect.minY - gap
        )

        // No room below the text: sit above it rather than be clipped.
        if anchor.source != .window, point.y - panelSize.height < visible.minY + margin {
            point.y = rect.maxY + gap + panelSize.height
        }

        return clamp(point, panelSize: panelSize, into: visible)
    }

    /// Accessibility measures from the top left of the primary display with y
    /// growing downwards; AppKit measures from its bottom left with y growing
    /// up. Flipping against the primary's height is what gives a rect on a
    /// display above or to the left of it the negative coordinates AppKit
    /// expects, rather than folding it back onto the primary.
    static func appKitRect(_ axRect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: axRect.minX,
            y: primaryHeight - axRect.maxY,
            width: axRect.width,
            height: axRect.height
        )
    }

    /// The display the text is actually on.
    ///
    /// By largest overlap, not by asking which screen contains a computed
    /// corner: that corner falls outside every display whenever the text sits
    /// near an edge, and the fallback from there used to be the screen holding
    /// the keyboard focus.
    private static func screen(for rect: CGRect, in layout: ScreenLayout) -> ScreenLayout.Screen? {
        // A caret is legitimately zero-width, and a zero-area rect intersects
        // nothing at all.
        let probe = CGRect(
            x: rect.minX, y: rect.minY,
            width: max(rect.width, 1), height: max(rect.height, 1)
        )

        var best: (screen: ScreenLayout.Screen, overlap: CGFloat)?
        for screen in layout.screens {
            let intersection = screen.frame.intersection(probe)
            guard !intersection.isNull else { continue }
            let overlap = intersection.width * intersection.height
            guard overlap > 0 else { continue }
            // Strictly greater, so a tie goes to the earlier screen, and index 0
            // is the primary.
            if best == nil || overlap > best!.overlap { best = (screen, overlap) }
        }
        if let best { return best.screen }

        // Nothing overlaps: a window half off-screen, or a display unplugged
        // between the check starting and the popup being shown.
        return layout.screens.min {
            distance(from: probe, to: $0) < distance(from: probe, to: $1)
        }
    }

    private static func distance(from rect: CGRect, to screen: ScreenLayout.Screen) -> CGFloat {
        let dx = rect.midX - screen.frame.midX
        let dy = rect.midY - screen.frame.midY
        return dx * dx + dy * dy
    }

    /// `point` is the panel's top-left, so the panel occupies `y - height` to `y`.
    private static func clamp(_ point: CGPoint, panelSize: CGSize, into visible: CGRect) -> CGPoint {
        var result = point

        let leftmost = visible.minX + margin
        let rightmost = visible.maxX - panelSize.width - margin
        result.x = rightmost >= leftmost
            ? min(max(result.x, leftmost), rightmost)
            : visible.midX - panelSize.width / 2

        let lowest = visible.minY + panelSize.height + margin
        let highest = visible.maxY - margin
        // A panel taller than the screen cannot satisfy both edges. Pin its top,
        // so the correction and its explanation are the part that stays readable.
        result.y = highest >= lowest ? min(max(result.y, lowest), highest) : highest

        return result
    }
}
