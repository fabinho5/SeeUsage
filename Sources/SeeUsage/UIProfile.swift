import AppKit
import SwiftUI

/// Appearance only. Account state and quota calculations are shared across profiles.
public enum UIProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case compact
    case classic

    public var id: String { rawValue }
    public var title: String { self == .compact ? "Compact" : "Classic" }
    public var description: String {
        self == .compact
            ? "Current layout: smaller text, tighter spacing, and hints on one line."
            : "Original layout: larger text and bars, with resets and hints below."
    }

    var popoverSize: NSSize {
        self == .compact ? NSSize(width: 400, height: 550) : NSSize(width: 360, height: 470)
    }
    var contentSpacing: CGFloat { self == .compact ? 5 : 14 }
    var contentHorizontalPadding: CGFloat { self == .compact ? 14 : 16 }
    var contentVerticalPadding: CGFloat { self == .compact ? 8 : 12 }
    var sectionSpacing: CGFloat { self == .compact ? 5 : 9 }
    var sectionVerticalPadding: CGFloat { self == .compact ? 2 : 4 }
    var rowSpacing: CGFloat { self == .compact ? 2 : 5 }
    var barHeight: CGFloat { self == .compact ? 4 : 8 }
    var headerVerticalPadding: CGFloat { self == .compact ? 9 : 14 }
    var footerVerticalPadding: CGFloat { self == .compact ? 7 : 10 }
    var controlSize: ControlSize { self == .compact ? .small : .regular }
    var titleFont: Font { self == .compact ? .system(size: 13, weight: .semibold) : .headline }
    var accountFont: Font { self == .compact ? .system(size: 12.5, weight: .semibold) : .headline }
    var quotaFont: Font { self == .compact ? .system(size: 11.5, weight: .medium) : .subheadline }
    var detailFont: Font { self == .compact ? .system(size: 10) : .caption }
    var actionFont: Font { self == .compact ? .system(size: 10.5) : .body }
}
