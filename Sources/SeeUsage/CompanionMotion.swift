import Foundation

struct CompanionMotion {
    private(set) var origin: NSPoint

    mutating func step(toward target: NSPoint, elapsed: TimeInterval, size: NSSize, screen: NSRect) -> NSPoint {
        // NSWindow rounds its origin to whole points. Retain fractional movement between frames.
        origin = Self.clamp(Self.advance(origin, toward: target, elapsed: elapsed), size: size, to: screen)
        return origin
    }

    static func clamp(_ origin: NSPoint, size: NSSize, to screen: NSRect) -> NSPoint {
        let minX = screen.minX + 12
        let minY = screen.minY + 12
        let maxX = max(minX, screen.maxX - size.width - 12)
        let maxY = max(minY, screen.maxY - size.height - 12)
        return NSPoint(x: min(max(origin.x, minX), maxX), y: min(max(origin.y, minY), maxY))
    }

    static func advance(_ origin: NSPoint, toward target: NSPoint, elapsed: TimeInterval) -> NSPoint {
        guard elapsed.isFinite, elapsed > 0 else { return origin }
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let distance = hypot(dx, dy)
        guard distance > 0 else { return origin }
        // A delayed timer after sleep must never teleport the character.
        let step = min(distance, 18 * min(elapsed, 0.2))
        return NSPoint(x: origin.x + dx / distance * step, y: origin.y + dy / distance * step)
    }
}
