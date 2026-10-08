import AppKit
import SwiftUI

@MainActor
public final class FloatingHUDManager: NSObject, NSWindowDelegate {
    public static let shared = FloatingHUDManager()

    private var panel: NSPanel?
    private var measuredBarContent: (key: FloatingBarLayout.SizeKey, size: NSSize)?
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private static let framePrefKey = "app.seeusage.floatingHUDFrame"

    private override init() {
        super.init()
        setupDistributedObserver()
    }

    private func setupDistributedObserver() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("app.seeusage.toggleHUD"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.toggle()
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("app.seeusage.showHUD"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.show()
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("app.seeusage.hideHUD"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("app.seeusage.hudSettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applySettings()
            }
        }

        for name in [Notification.Name.usageStoreDidUpdate, NSApplication.didChangeScreenParametersNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.applySettings() }
            }
        }
    }

    public var isVisible: Bool {
        panel?.isVisible == true
    }

    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    public func show() {
        SettingsStore.shared.hudEnabled = true

        if let p = panel {
            applySettings()
            p.orderFrontRegardless()
            return
        }

        createAndShowPanel()
    }

    public func hide() {
        dragStart = nil
        SettingsStore.shared.hudEnabled = false
        savePanelPosition()
        panel?.orderOut(nil)
    }

    func dragBar() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (mouse, panel.frame.origin) }
        guard let start = dragStart else { return }
        panel.setFrameOrigin(NSPoint(
            x: start.origin.x + mouse.x - start.mouse.x,
            y: start.origin.y + mouse.y - start.mouse.y
        ))
    }

    func finishDraggingBar() {
        dragStart = nil
        savePanelPosition()
    }

    private func createAndShowPanel() {
        let hostingController = FloatingGlassHostingController()

        let p = NSPanel(
            contentRect: calculateInitialFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        p.contentViewController = hostingController
        p.isFloatingPanel = true
        p.level = SettingsStore.shared.hudAlwaysOnTop ? .floating : .normal
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.delegate = self
        p.hidesOnDeactivate = false

        self.panel = p
        (p.contentViewController as? FloatingGlassHostingController)?.updateAppearance()
        applyContentSize(to: p)
        p.orderFrontRegardless()
    }

    public func applySettings() {
        guard let p = panel else {
            if SettingsStore.shared.hudEnabled {
                createAndShowPanel()
            }
            return
        }

        if !SettingsStore.shared.hudEnabled {
            p.orderOut(nil)
            return
        }

        (p.contentViewController as? FloatingGlassHostingController)?.updateAppearance()
        applyContentSize(to: p)
        p.level = SettingsStore.shared.hudAlwaysOnTop ? .floating : .normal
        if !p.isVisible {
            p.orderFrontRegardless()
        }
    }

    func updateBarContentSize(_ size: NSSize, for key: FloatingBarLayout.SizeKey) {
        let settings = SettingsStore.shared
        guard settings.hudCompactMode,
              key == FloatingBarLayout.SizeKey(items: barItems, orientation: settings.hudBarOrientation,
                                               quotas: settings.hudBarQuotas) else { return }
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        let measured = NSSize(width: ceil(size.width), height: ceil(size.height))
        guard measuredBarContent?.key != key || measuredBarContent?.size != measured else { return }
        measuredBarContent = (key, measured)
        applySettings()
    }

    private func calculateInitialFrame() -> NSRect {
        if let saved = UserDefaults.standard.string(forKey: Self.framePrefKey) {
            let rect = NSRectFromString(saved)
            if rect.width > 0 && rect.height > 0 {
                // Verify rect is on an available screen
                let isVisibleOnScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(rect) }
                if isVisibleOnScreen {
                    return rect
                }
            }
        }

        // Default to top-right of main screen
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1200, height: 800)
        let size = desiredContentSize
        let defaultWidth = size.width
        let defaultHeight = size.height
        let x = screenRect.maxX - defaultWidth - 24
        let y = screenRect.maxY - defaultHeight - 24

        return NSRect(x: x, y: y, width: defaultWidth, height: defaultHeight)
    }

    private var barItems: [FloatingQuotaItem] {
        let settings = SettingsStore.shared
        let store = UsageStore.shared
        return FloatingQuotaItem.items(
            profiles: settings.orderedDisplayProfiles,
            snapshots: store.snapshots,
            claudeUsage: store.claudeUsageSnapshot,
            refreshIntervalMinutes: settings.refreshIntervalMinutes,
            quotas: settings.hudBarQuotas,
            hiddenItems: settings.hudBarHiddenItems,
            displayNames: settings.profilePresentation.displayNames
        )
    }

    private var desiredContentSize: NSSize {
        let settings = SettingsStore.shared
        if settings.hudCompactMode {
            let items = barItems
            let screen = panel.flatMap { panel in
                NSScreen.screens.first { $0.visibleFrame.intersects(panel.frame) }
            } ?? NSScreen.main
            let key = FloatingBarLayout.SizeKey(items: items, orientation: settings.hudBarOrientation, quotas: settings.hudBarQuotas)
            if let measured = measuredBarContent, measured.key == key {
                return FloatingBarLayout.fittedSize(measured.size,
                    availableWidth: screen?.visibleFrame.width ?? 1200,
                    availableHeight: screen?.visibleFrame.height ?? 800)
            }
            return FloatingBarLayout.size(
                items: items,
                availableWidth: screen?.visibleFrame.width ?? 1200,
                availableHeight: screen?.visibleFrame.height ?? 800,
                orientation: settings.hudBarOrientation,
                quotas: settings.hudBarQuotas
            )
        }
        return NSSize(width: 380, height: 300)
    }

    private func applyContentSize(to panel: NSPanel) {
        let size = desiredContentSize
        var frame = panel.frame
        frame.size = size
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) }) {
            frame.origin.x = min(max(frame.origin.x, screen.visibleFrame.minX), screen.visibleFrame.maxX - size.width)
            frame.origin.y = min(max(frame.origin.y, screen.visibleFrame.minY), screen.visibleFrame.maxY - size.height)
        }
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
        savePanelPosition()
    }

    private func savePanelPosition() {
        guard let p = panel else { return }
        UserDefaults.standard.set(NSStringFromRect(p.frame), forKey: Self.framePrefKey)
    }

    // MARK: - NSWindowDelegate
    public func windowDidMove(_ notification: Notification) {
        savePanelPosition()
    }

    public func windowWillClose(_ notification: Notification) {
        savePanelPosition()
    }
}
