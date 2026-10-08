import SwiftUI

struct QuotaHintView: View {
    let hints: QuotaHints
    var compact = false
    var uiProfile: UIProfile = .compact

    var body: some View {
        Group {
            if uiProfile == .classic {
                VStack(alignment: .leading, spacing: 3) {
                    Text(forecastText).foregroundStyle(color)
                    if let sessions = hints.sessionText {
                        Text(sessions).foregroundStyle(.secondary)
                    }
                    if let windows = hints.pacing?.windowText {
                        Text(windows).foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(Text(forecastText).foregroundColor(color))\(Text(detailSuffix).foregroundColor(.secondary))")
                    .font(.system(size: compact ? 9 : 10.5))
                    .lineLimit(compact ? 1 : nil)
                    .minimumScaleFactor(0.9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(hints.tooltip)
        .accessibilityLabel(forecastText + (hints.sessionText.map { ", " + $0 } ?? "")
                            + (hints.pacing?.windowText.map { ", " + $0 } ?? ""))
    }

    private var forecastText: String {
        if let pacing = hints.pacing { return pacing.text }
        return switch hints.forecast.status {
        case .learning: "Learning usage"
        case .reserve:
            "\(Int((hints.forecast.projectedRemainingPercent ?? 0).rounded()))% in reserve · Lasts until reset"
        case .onTrack:
            (hints.forecast.projectedRemainingPercent ?? 0) < 0
                ? "Close to limit · May run out"
                : "On pace · Lasts until reset"
        case .deficit:
            "Deficit · ~\(QuotaForecast.duration(hints.forecast.secondsBeforeReset ?? 0)) before reset"
        case .idle: "No recent usage"
        case .exhausted: "Quota exhausted"
        }
    }

    private var detailSuffix: String {
        guard hints.isWeekly else { return "" }
        var parts: [String] = []
        if let sessions = hints.sessions {
            parts.append("Est. \(sessions.capacityText) typical 5h sessions left")
        } else {
            parts.append("Learning sessions")
        }
        if let windows = hints.pacing?.windowText { parts.append(windows) }
        return " · " + parts.joined(separator: " · ")
    }

    private var color: Color {
        switch hints.pacing?.status ?? hints.forecast.status {
        case .deficit, .exhausted: .orange
        default: .secondary
        }
    }
}
