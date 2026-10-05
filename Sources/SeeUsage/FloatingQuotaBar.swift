import SwiftUI

/// Uses its intrinsic size until it exceeds the available screen space.
struct FloatingQuotaBar: View {
    let items: [FloatingQuotaItem]
    let orientation: FloatingBarOrientation
    let quotas: FloatingBarQuotas

    var body: some View {
        Group {
            if orientation == .horizontal {
                ViewThatFits(in: .horizontal) {
                    horizontalRows.fixedSize()
                    ScrollView(.horizontal) { horizontalRows.fixedSize() }
                        .frame(height: FloatingBarLayout.horizontalRowHeight)
                }
            } else {
                ViewThatFits(in: .vertical) {
                    verticalRows.fixedSize()
                    ScrollView(.vertical) { verticalRows }
                }
            }
        }
        .padding(.horizontal, FloatingBarLayout.horizontalPadding)
        .padding(.vertical, FloatingBarLayout.verticalPadding)
        .overlay {
            RoundedRectangle(cornerRadius: FloatingBarLayout.cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.10), .white.opacity(0.28)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.5
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var horizontalRows: some View {
        HStack(spacing: FloatingBarLayout.itemSpacing) {
            if items.isEmpty { emptyContent }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle().fill(UIColors.border.opacity(0.6))
                        .frame(width: 1, height: 24)
                }
                VStack(alignment: .leading, spacing: 4) {
                    profileName(item)
                    quotaValues(item)
                }
                .frame(width: FloatingBarLayout.horizontalItemWidth(item, quotas: quotas),
                       height: FloatingBarLayout.horizontalRowHeight, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("floating-profile-\(item.id)")
            }
        }
    }

    private var verticalRows: some View {
        VStack(alignment: .leading, spacing: FloatingBarLayout.itemSpacing) {
            if items.isEmpty { emptyContent }
            ForEach(items) { item in
                HStack(spacing: FloatingBarLayout.labelSpacing) {
                    profileName(item)
                        .frame(width: items.map(\.labelWidth).max() ?? 70, alignment: .leading)
                    quotaValues(item)
                }
                .frame(height: FloatingBarLayout.verticalRowHeight)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("floating-profile-\(item.id)")
            }
        }
    }

    private var emptyContent: some View {
        Text("SeeUsage —")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: 110, height: orientation == .horizontal
                   ? FloatingBarLayout.horizontalRowHeight : FloatingBarLayout.verticalRowHeight)
    }

    private func profileName(_ item: FloatingQuotaItem) -> some View {
        Text(item.label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(item.label)
    }

    private func quotaValues(_ item: FloatingQuotaItem) -> some View {
        HStack(spacing: FloatingBarLayout.quotaSpacing) {
            ForEach(item.values) { value in
                HStack(spacing: FloatingBarLayout.periodSpacing) {
                    if quotas == .both {
                        Text(value.period.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: FloatingBarLayout.periodWidth, alignment: .leading)
                    }
                    Text(value.percent.map { "\(Int($0.rounded()))%" } ?? "—")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(value.percent.map { UIColors.quotaTextColor(percent: $0) } ?? .secondary)
                        .frame(width: FloatingBarLayout.percentageWidth, alignment: .trailing)
                }
                .help("\(item.label) · \(value.period.title)\(value.percent == nil ? " · Unavailable" : "")")
                .accessibilityLabel(value.period.title)
                .accessibilityValue(value.percent.map { "\(Int($0.rounded()))%" } ?? "Unavailable")
            }
        }
    }
}
