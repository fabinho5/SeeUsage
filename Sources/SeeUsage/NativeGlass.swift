import AppKit
import SwiftUI

/// The panel owns the glass; SwiftUI supplies only its content.
@MainActor
final class FloatingGlassHostingController: NSViewController {
    private let hostingController: NSHostingController<AnyView>

    init(rootView: AnyView) {
        hostingController = NSHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    convenience init() { self.init(rootView: AnyView(FloatingHUDView())) }

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
            material.material = .hudWindow
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
        let settings = SettingsStore.shared
        let radius: CGFloat = settings.hudCompactMode ? FloatingBarLayout.cornerRadius : 12
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            glass.style = .regular
            glass.tintColor = nil
            glass.cornerRadius = radius
        } else {
            view.layer?.cornerRadius = radius
        }
    }
}

struct NativeGlassSurface: ViewModifier {
    let material: NSVisualEffectView.Material
    var cornerRadius: CGFloat = 12
    var tintOpacity: Double = 0.08

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(
                .regular.tint(UIColors.background.opacity(tintOpacity)),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content.background {
                NativeGlassBackground(material: material, tintOpacity: tintOpacity)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(UIColors.border, lineWidth: 1)
                    }
            }
        }
    }
}

struct NativeGlassBackground: View {
    let material: NSVisualEffectView.Material
    var tintOpacity: Double = 0.08

    var body: some View {
        ZStack {
            VisualEffectBlur(material: material, blendingMode: .behindWindow)
            UIColors.background.opacity(tintOpacity)
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.white.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
