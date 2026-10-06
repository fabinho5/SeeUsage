import AppKit
import Observation
import SwiftUI

enum CompanionPhase { case idle, checking, hurt, celebrating }

@MainActor @Observable
final class CompanionState {
    var look: CompanionLook = .unavailable
    var phase: CompanionPhase = .idle
    var damagePercent = 0.0
    var remainingPercent: Double?
    var reactionStartedAt = Date()
    var facingLeft = false
    var isHovered = false
    var isDragging = false
}

@MainActor
enum CompanionArtwork {
    static let names = ["idle", "blink", "worn", "critical", "hurt", "celebrate"]
    private static var images: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage {
        if let cached = images[name] { return cached }
        // The app bundle ships these directly; swift run uses the SwiftPM resource bundle.
        let appURL = Bundle.main.resourceURL?.appendingPathComponent("Companion/lume-\(name).png")
        let url = appURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            ?? Bundle.module.url(forResource: "lume-\(name)", withExtension: "png", subdirectory: "Companion")
        let image = url.flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Lume")!
        images[name] = image
        return image
    }
}

struct CompanionView: View {
    @Bindable var state: CompanionState
    @Bindable private var settings = SettingsStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            artwork(at: timeline.date)
        }
        .frame(width: CompanionManager.panelSize.width, height: CompanionManager.panelSize.height)
        .contentShape(Rectangle())
        .onHover { state.isHovered = $0 }
        .gesture(DragGesture(minimumDistance: 3)
            .onChanged { _ in CompanionManager.shared.drag() }
            .onEnded { _ in CompanionManager.shared.finishDragging() })
        .contextMenu {
            Button("Check quotas now") { CompanionManager.shared.checkNow() }
                .disabled(state.phase == .checking)
            Toggle("Move around the screen", isOn: $settings.companionWanders)
            Divider()
            Button("Hide Lume") { CompanionManager.shared.hide() }
        }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lume, SeeUsage companion")
        .accessibilityValue(helpText)
        .accessibilityAction(named: "Check quotas") { CompanionManager.shared.checkNow() }
    }

    private func artwork(at date: Date) -> some View {
        let elapsed = max(0, date.timeIntervalSince(state.reactionStartedAt))
        let time = date.timeIntervalSinceReferenceDate
        let blink = state.phase == .idle && state.look == .healthy
            && time.truncatingRemainder(dividingBy: 5.8) < 0.16
        let sprite: String
        switch state.phase {
        case .hurt: sprite = "hurt"
        case .celebrating: sprite = "celebrate"
        case .idle, .checking:
            switch state.look {
            case .healthy, .unavailable: sprite = blink ? "blink" : "idle"
            case .worn: sprite = "worn"
            case .critical: sprite = "critical"
            }
        }
        let bob = reduceMotion ? 0 : sin(time * 2) * 2.5
        let jump = !reduceMotion && state.phase == .celebrating ? abs(sin(elapsed * 8)) * 7 : 0
        let shake = !reduceMotion && state.phase == .hurt
            ? sin(elapsed * 48) * min(10, 2 + state.damagePercent * 0.5) * exp(-elapsed * 2.5) : 0
        let tilt = !reduceMotion && state.phase == .celebrating ? sin(elapsed * 7) * 7 : 0

        return ZStack(alignment: .top) {
            Image(nsImage: CompanionArtwork.image(sprite))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 96, height: 96)
                .scaleEffect(x: state.facingLeft ? -1 : 1, y: 1)
                .rotationEffect(.degrees(tilt))
                .saturation(state.look == .unavailable ? 0.25 : 1)
                .opacity(state.look == .unavailable ? 0.75 : 1)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 2)
                .offset(x: shake, y: 22 + bob - jump)
            if state.phase == .hurt {
                Text("−\(state.damagePercent.formatted(.number.precision(.fractionLength(0...1))))%")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color(red: 1, green: 0.44, blue: 0.32))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
                    .offset(y: reduceMotion ? 4 : 12 - elapsed * 8)
                    .opacity(reduceMotion ? 1 : max(0, 1 - elapsed / 1.6))
            }
            if state.phase == .checking {
                Circle().stroke(Color.orange.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [3, 7]))
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(reduceMotion ? 0 : time * 100))
                    .offset(x: 35, y: 23)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: CompanionManager.panelSize.width, height: CompanionManager.panelSize.height)
    }

    private var helpText: String {
        switch state.phase {
        case .checking: return "Checking quotas…"
        case .hurt: return "Quota decreased by \(state.damagePercent.formatted(.number.precision(.fractionLength(0...1)))) percentage points."
        case .celebrating: return "No quota lost. Nice!"
        case .idle:
            if let remaining = state.remainingPercent {
                return "Lowest quota: \(Int(remaining.rounded()))%. Drag Lume to move; right-click for options."
            }
            return "Waiting for fresh quota data. Drag Lume to move; right-click for options."
        }
    }
}
