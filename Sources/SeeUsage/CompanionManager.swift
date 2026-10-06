import AppKit
import SwiftUI

@MainActor
final class CompanionManager {
    static let shared = CompanionManager()
    static let panelSize = NSSize(width: 112, height: 132)

    let state = CompanionState()
    private var panel: NSPanel?
    private var refreshLoop: CompanionRefreshLoop?
    private var manualCheck: Task<Void, Never>?
    private var reactionTask: Task<Void, Never>?
    private var motionTimer: Timer?
    private var tracker = CompanionQuotaTracker()
    private var target: NSPoint?
    private var motion: CompanionMotion?
    private var lastMotionTime = ProcessInfo.processInfo.systemUptime
    private var pauseUntil = 0.0
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var observers: [NSObjectProtocol] = []
    private static let positionKey = "app.seeusage.companionPosition"

    private init() {
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("app.seeusage.companionSettingsChanged"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applySettings() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.constrainToScreen() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkNow() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applySettings() }
        })
    }

    func applySettings() {
        guard SettingsStore.shared.companionEnabled else { stop(); return }
        if panel == nil { createPanel() }
        panel?.orderFrontRegardless()
        if refreshLoop == nil {
            refreshLoop = CompanionRefreshLoop { [weak self] in await self?.refreshQuotas() }
        }
        guard SettingsStore.shared.companionWanders,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            motionTimer?.invalidate()
            motionTimer = nil
            return
        }
        if motionTimer == nil {
            lastMotionTime = ProcessInfo.processInfo.systemUptime
            motionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.moveOneFrame() }
            }
        }
    }

    func hide() {
        SettingsStore.shared.companionEnabled = false
        stop()
    }

    func stop() {
        refreshLoop?.stop()
        refreshLoop = nil
        manualCheck?.cancel()
        manualCheck = nil
        reactionTask?.cancel()
        reactionTask = nil
        motionTimer?.invalidate()
        motionTimer = nil
        savePosition()
        panel?.orderOut(nil)
        state.phase = .idle
        state.isDragging = false
        state.isHovered = false
        dragStart = nil
        target = nil
        motion = nil
        tracker = CompanionQuotaTracker()
    }

    func checkNow() {
        guard SettingsStore.shared.companionEnabled, state.phase != .checking else { return }
        manualCheck?.cancel()
        manualCheck = Task { [weak self] in await self?.refreshQuotas() }
    }

    private func createPanel() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let saved = UserDefaults.standard.string(forKey: Self.positionKey).map(NSPointFromString)
        let defaultOrigin = NSPoint(x: screen.maxX - Self.panelSize.width - 48, y: screen.minY + 80)
        let origin = saved ?? defaultOrigin
        let p = NSPanel(contentRect: NSRect(origin: origin, size: Self.panelSize),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = NSHostingView(rootView: CompanionView(state: state))
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.acceptsMouseMovedEvents = true
        panel = p
        constrainToScreen()
    }

    private func refreshQuotas() async {
        guard SettingsStore.shared.companionEnabled, state.phase != .checking, !Task.isCancelled else { return }
        reactionTask?.cancel()
        state.phase = .checking
        let store = UsageStore.shared
        await store.refresh()
        guard !Task.isCancelled, SettingsStore.shared.companionEnabled else { return }
        store.loadClaudeUsageCache()
        let readings = CompanionQuotaReading.collect(profiles: SettingsStore.shared.orderedDisplayProfiles,
            snapshots: store.snapshots, claudeUsage: store.claudeUsageSnapshot)
        let update = tracker.update(readings)
        state.look = update.look
        state.remainingPercent = update.remainingPercent
        state.reactionStartedAt = Date()
        switch update.reaction {
        case .none: state.phase = .idle
        case .damage(let lost):
            state.damagePercent = lost
            state.phase = .hurt
            pauseUntil = ProcessInfo.processInfo.systemUptime + 1.6
            finishReaction(after: .seconds(1.6))
        case .celebrate:
            state.phase = .celebrating
            pauseUntil = ProcessInfo.processInfo.systemUptime + 2.4
            finishReaction(after: .seconds(2.4))
        }
    }

    private func finishReaction(after duration: Duration) {
        reactionTask = Task { [weak self] in
            do { try await Task.sleep(for: duration) }
            catch { return }
            self?.state.phase = .idle
        }
    }

    func drag() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (mouse, panel.frame.origin) }
        guard let start = dragStart else { return }
        state.isDragging = true
        panel.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x,
                                     y: start.origin.y + mouse.y - start.mouse.y))
    }

    func finishDragging() {
        dragStart = nil
        state.isDragging = false
        pauseUntil = ProcessInfo.processInfo.systemUptime + 3
        constrainToScreen()
        savePosition()
    }

    private var currentScreen: NSRect? {
        guard let panel else { return NSScreen.main?.visibleFrame }
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        return (NSScreen.screens.first { $0.visibleFrame.contains(center) } ?? NSScreen.main)?.visibleFrame
    }

    private func constrainToScreen() {
        guard let panel, let screen = currentScreen else { return }
        let origin = CompanionMotion.clamp(panel.frame.origin, size: Self.panelSize, to: screen)
        motion = CompanionMotion(origin: origin)
        panel.setFrameOrigin(origin)
        target = nil
    }

    private func moveOneFrame() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastMotionTime
        lastMotionTime = now
        guard let panel, panel.isVisible, SettingsStore.shared.companionWanders,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              !state.isHovered, !state.isDragging, state.phase != .checking, now >= pauseUntil,
              let screen = currentScreen else { return }
        if motion == nil { motion = CompanionMotion(origin: panel.frame.origin) }
        let origin = motion?.origin ?? panel.frame.origin
        if target == nil {
            target = CompanionMotion.clamp(NSPoint(x: Double.random(in: screen.minX...screen.maxX),
                                                   y: Double.random(in: screen.minY...screen.maxY)),
                                           size: Self.panelSize, to: screen)
        }
        guard let target else { return }
        if hypot(target.x - origin.x, target.y - origin.y) < 2 {
            self.target = nil
            pauseUntil = now + Double.random(in: 2...5)
            savePosition()
            return
        }
        let facingLeft = target.x < origin.x
        if state.facingLeft != facingLeft { state.facingLeft = facingLeft }
        if let next = motion?.step(toward: target, elapsed: elapsed, size: Self.panelSize, screen: screen) {
            panel.setFrameOrigin(next)
        }
    }

    private func savePosition() {
        guard let panel else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.positionKey)
    }
}
