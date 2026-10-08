import SwiftUI

struct QuotaGauge: View {
    let percent: Double
    let color: Color
    var height: CGFloat = 4
    var pacing: QuotaPacing? = nil

    private var markerColor: Color? {
        switch pacing?.status {
        case .reserve: .green
        case .deficit: .red
        default: nil
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(UIColors.track)
                Capsule().fill(color)
                    .frame(width: geometry.size.width * (percent.isFinite ? max(0, min(100, percent)) / 100 : 0))
                if let pacing, let markerColor {
                    let position = max(1, min(geometry.size.width - 1,
                                             geometry.size.width * pacing.expectedRemainingPercent / 100))
                    Rectangle().fill(Color.black.opacity(0.8))
                        .frame(width: 6).offset(x: position - 3)
                    Rectangle().fill(markerColor)
                        .frame(width: 2).offset(x: position - 1)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Remaining quota")
        .accessibilityValue("\(Int((percent.isFinite ? max(0, min(100, percent)) : 0).rounded()))%"
                            + (pacing.map { ", " + $0.text } ?? ""))
        .help(pacing?.explanation ?? "Remaining quota")
    }
}
