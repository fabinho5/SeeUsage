import AppKit
import SwiftUI

/// Native surfaces share the same untinted glass; SwiftUI supplies their content.
@MainActor
class NativeGlassHostingController: NSViewController {
    var cornerRadius: CGFloat
    private let material: NSVisualEffectView.Material
    private let hostingController: NSHostingController<AnyView>

    init(rootView: AnyView, material: NSVisualEffectView.Material, cornerRadius: CGFloat = NativeGlassStyle.cornerRadius) {
        self.material = material
        self.cornerRadius = cornerRadius
        hostingController = NSHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        addChild(hostingController)
        hostingController.sizingOptions = []
        let content = hostingController.view
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.contentView = content
            view = glass
        } else {
            let material = NSVisualEffectView()
            material.material = self.material
            material.blendingMode = .behindWindow
            material.state = .active
            material.wantsLayer = true
            material.layer?.masksToBounds = true
            material.addSubview(content)
            view = material
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        updateAppearance()
    }

    func updateAppearance() {
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            glass.style = .regular
            glass.tintColor = nil
            glass.cornerRadius = cornerRadius
        } else {
            view.layer?.cornerRadius = cornerRadius
        }
    }
}

@MainActor
final class FloatingGlassHostingController: NativeGlassHostingController {
    init(rootView: AnyView) {
        super.init(rootView: rootView, material: .hudWindow)
    }

    convenience init() { self.init(rootView: AnyView(FloatingHUDView())) }

    required init?(coder: NSCoder) { nil }

    override func updateAppearance() {
        cornerRadius = SettingsStore.shared.hudCompactMode ? NativeGlassStyle.cornerRadius : 12
        super.updateAppearance()
    }
}

enum NativeGlassStyle {
    static let cornerRadius: CGFloat = 18
}

struct GlassEdgeHighlight: View {
    var cornerRadius: CGFloat = NativeGlassStyle.cornerRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.10), .white.opacity(0.28)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.5
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
