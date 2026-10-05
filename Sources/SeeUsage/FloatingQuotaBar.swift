import SwiftUI

/// Uses its intrinsic size until it exceeds the available screen space.
struct FloatingQuotaBar: View {
    let items: [FloatingQuotaItem]
    let orientation: FloatingBarOrientation
    let quotas: FloatingBarQuotas
    var onContentSizeChange: (@MainActor (NSSize) -> Void)? = nil

    var body: some View {
        let naturalSize = FloatingBarLayout.naturalSize(items: items, orientation: orientation, quotas: quotas)
        let key = FloatingBarLayout.SizeKey(items: items, orientation: orientation, quotas: quotas)
        Group {
            if orientation == .horizontal {
                ScrollView(.horizontal) { measuredHorizontalRows }
                    .frame(idealWidth: naturalSize.width - 2 * FloatingBarLayout.horizontalPadding,
                           minHeight: FloatingBarLayout.horizontalRowHeight,
                           maxHeight: FloatingBarLayout.horizontalRowHeight, alignment: .topLeading)
            } else {
                ScrollView([.horizontal, .vertical]) { measuredVerticalRows }
                    .frame(idealWidth: naturalSize.width - 2 * FloatingBarLayout.horizontalPadding,
                           idealHeight: naturalSize.height - 2 * FloatingBarLayout.verticalPadding,
                           alignment: .topLeading)
            }
        }
        // Selection changes must discard the previous scroll offset and layout state.
        // Quota refreshes keep the same identity.
        .id(key)
        .scrollIndicators(.hidden)
        .transaction { $0.animation = nil }
        .padding(.horizontal, FloatingBarLayout.horizontalPadding)
        .padding(.vertical, FloatingBarLayout.verticalPadding)
        .clipShape(RoundedRectangle(cornerRadius: NativeGlassStyle.cornerRadius, style: .continuous))
        .overlay { GlassEdgeHighlight() }
        .onPreferenceChange(FloatingBarContentSizePreference.self) { contentSize in
            guard contentSize.width > 0, contentSize.height > 0 else { return }
            let size = NSSize(width: contentSize.width + 2 * FloatingBarLayout.horizontalPadding,
                              height: contentSize.height + 2 * FloatingBarLayout.verticalPadding)
            Task { @MainActor in onContentSizeChange?(size) }
        }
    }

    private var measuredHorizontalRows: some View {
        horizontalRows.fixedSize().background(contentSizeReader)
    }

    private var measuredVerticalRows: some View {
        verticalRows.fixedSize().background(contentSizeReader)
    }

    private var contentSizeReader: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: FloatingBarContentSizePreference.self, value: geometry.size)
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

private struct FloatingBarContentSizePreference: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}
