import Foundation

struct QuotaForecast: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case learning, idle, reserve, onTrack, deficit, exhausted
    }

    let status: Status
    var projectedRemainingPercent: Double? = nil
    var secondsBeforeReset: TimeInterval? = nil
    var observedSeconds: TimeInterval = 0
    var sampleCount: Int = 0

    var text: String {
        switch status {
        case .learning: return "Learning your usage"
        case .idle: return "No recent usage"
        case .reserve: return "Reserve · \(Int((projectedRemainingPercent ?? 0).rounded()))% spare at reset"
        case .onTrack:
            return (projectedRemainingPercent ?? 0) < 0
                ? "Close to limit · may run out before reset"
                : "Lasts until reset · little margin"
        case .deficit: return "Deficit · may run out ~\(Self.duration(secondsBeforeReset ?? 0)) before reset"
        case .exhausted: return "Quota exhausted · waiting for reset"
        }
    }

    var explanation: String {
        switch status {
        case .learning:
            return "Waiting for enough reliable history for this account and quota. Short windows need at least 30 minutes; weekly forecasts need 3 days with at least half that time observed. Gaps, refills and resets are excluded."
        case .idle:
            return "No consumption in the observed samples. A forecast will appear once there is a measurable usage pace."
        case .exhausted:
            return "The latest quota reading is zero."
        default:
            return "Estimate at your observed pace, including idle time: \(sampleCount) samples covering \(Self.duration(observedSeconds)). Usage changes can move this estimate. A five percentage point margin is treated as close to the limit."
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "an unknown time" }
        let minutes = max(1, Int(ceil(min(max(0, seconds), 365 * 86_400) / 60)))
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 1_440 { return "\(minutes / 60)h\(minutes % 60 == 0 ? "" : " \(minutes % 60)m")" }
        return "\(minutes / 1_440)d\(minutes % 1_440 < 60 ? "" : " \((minutes % 1_440) / 60)h")"
    }
}

struct WeeklySessionEstimate: Equatable, Sendable {
    let count: Int
    let typicalConsumption: Double
    let observedSessions: Int
    var fractionalCount: Double? = nil

    var capacityText: String {
        let value = fractionalCount ?? Double(count)
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
    var text: String { "~\(capacityText) typical 5-hour sessions left" }
    var explanation: String {
        "Weekly quota capacity, based on the median of \(observedSessions) completed, well-observed 5-hour windows (~\(Int(typicalConsumption.rounded()))% weekly quota per session). This estimates your usual usage, not guaranteed hours or sessions you can fit before reset."
    }
}

struct QuotaHints: Equatable, Sendable {
    let forecast: QuotaForecast
    let isWeekly: Bool
    let sessions: WeeklySessionEstimate?
    var pacing: QuotaPacing? = nil

    var sessionText: String? {
        isWeekly ? (sessions?.text ?? "Learning your sessions") : nil
    }

    var tooltip: String {
        var lines = pacing.map { [$0.text, $0.explanation] } ?? []
        if let windows = pacing?.windowText { lines.append(windows) }
        lines.append("Observed-history forecast: " + forecast.text)
        lines.append(forecast.explanation)
        if let sessionText {
            lines.append(sessionText)
            lines.append(sessions?.explanation ?? "Needs at least 3 completed 5-hour windows for this account and model scope, with reliable weekly readings throughout each window.")
        }
        return lines.joined(separator: "\n")
    }
}

/// Pure calculations: source timestamps prevent cached readings from fabricating history.
enum QuotaForecastCalculations {
    static func hints(
        for window: UsageWindow,
        profileID: UUID,
        service: String,
        windows: [UsageWindow],
        history: [QuotaHistorySnapshot],
        fetchedAt: Date,
        hasError: Bool = false,
        now: Date = Date(),
        staleAfter: TimeInterval = 600,
        maximumSampleGap: TimeInterval = 1_800
    ) -> QuotaHints? {
        guard !hasError, fetchedAt <= now, now.timeIntervalSince(fetchedAt) <= staleAfter,
              let remaining = window.remainingPercent, valid(remaining),
              let reset = window.resetsAt, reset > now else { return nil }
        // This independent reserve pool isn't the main weekly/session allowance.
        if service == "Codex", CodexQuotaPresentation.isReserve(window) { return nil }
        let weekly = FloatingQuotaPeriod.weekly.matches(window)
        let cutoff = fetchedAt.addingTimeInterval(weekly ? -14 * 86_400 : -2 * 3_600)
        var records: [QuotaSampleRecord] = []
        for snapshot in history {
            for record in snapshot.records {
                guard record.timestamp >= cutoff, record.timestamp <= fetchedAt,
                      record.profileID == profileID, record.service == service, record.scope == window.scope else { continue }
                records.append(record)
            }
        }
        let current = QuotaSampleRecord(timestamp: fetchedAt, profileID: profileID, profileName: "",
                                        service: service, scope: window.scope, windowLabel: window.label,
                                        windowID: window.id, durationMinutes: window.durationMinutes,
                                        remainingPercent: remaining, resetsAt: reset)
        let forecast = forecast(window: window, records: records, current: current,
                                weekly: weekly, maximumGap: maximumSampleGap)
        let estimate = weekly ? sessionEstimate(weeklyWindow: window, windows: windows, records: records,
                                               now: now, maximumGap: maximumSampleGap) : nil
        return QuotaHints(forecast: forecast, isWeekly: weekly, sessions: estimate,
                          pacing: QuotaPacing.calculate(for: window, fetchedAt: fetchedAt, now: now))
    }

    private static func forecast(
        window: UsageWindow, records: [QuotaSampleRecord], current: QuotaSampleRecord,
        weekly: Bool, maximumGap: TimeInterval
    ) -> QuotaForecast {
        let remaining = window.remainingPercent!
        if remaining == 0 { return QuotaForecast(status: .exhausted) }
        let reset = window.resetsAt!
        let fetchedAt = current.timestamp
        let lookback: TimeInterval = weekly ? 7 * 86_400 : 2 * 3_600
        var samples = sortedUnique(records.filter {
            matches($0, window) && sameCycle($0.resetsAt, reset) &&
            $0.timestamp >= fetchedAt.addingTimeInterval(-lookback)
        })
        // The live reading is authoritative; never advance its timestamp to the UI clock.
        samples.removeAll { abs($0.timestamp.timeIntervalSince(fetchedAt)) < 0.000_001 }
        samples.append(current)
        var start = samples.count - 1
        while start > 0 {
            let previous = samples[start - 1], current = samples[start]
            let gap = current.timestamp.timeIntervalSince(previous.timestamp)
            // A refill or invalid reading ends the usable history even if the deadline is unchanged.
            guard valid(previous.remainingPercent), valid(current.remainingPercent),
                  previous.remainingPercent >= current.remainingPercent,
                  weekly || gap <= maximumGap else { break }
            start -= 1
        }
        samples = Array(samples[start...])
        guard samples.count >= 3 else { return QuotaForecast(status: .learning) }
        var observed: TimeInterval = 0
        var consumed = 0.0
        for (previous, current) in zip(samples, samples.dropFirst()) {
            let gap = current.timestamp.timeIntervalSince(previous.timestamp)
            guard gap > 0, gap <= maximumGap else { continue }
            observed += gap
            consumed += previous.remainingPercent - current.remainingPercent
        }
        let span = fetchedAt.timeIntervalSince(samples[0].timestamp)
        guard span >= (weekly ? 3 * 86_400 : 1_800), observed >= span * (weekly ? 0.5 : 1) else {
            return QuotaForecast(status: .learning)
        }
        guard consumed > 0 else { return QuotaForecast(status: .idle, observedSeconds: observed, sampleCount: samples.count) }
        let rate = consumed / observed
        let timeLeft = reset.timeIntervalSince(fetchedAt)
        let projected = remaining - rate * timeLeft
        // Close forecasts get a neutral label instead of flipping reserve/deficit on rounding noise.
        let status: QuotaForecast.Status = projected > 5 ? .reserve : (projected < -5 ? .deficit : .onTrack)
        return QuotaForecast(status: status, projectedRemainingPercent: projected,
                             secondsBeforeReset: max(0, timeLeft - remaining / rate),
                             observedSeconds: observed, sampleCount: samples.count)
    }

    private static func sessionEstimate(
        weeklyWindow: UsageWindow, windows: [UsageWindow], records: [QuotaSampleRecord],
        now: Date, maximumGap: TimeInterval
    ) -> WeeklySessionEstimate? {
        let shortWindows = windows.filter { $0.scope == weeklyWindow.scope && FloatingQuotaPeriod.fiveHours.matches($0) }
        // Multiple session pools cannot be attributed to one weekly pool reliably.
        guard shortWindows.count == 1 else { return nil }
        let shortWindow = shortWindows[0]
        let cutoff = now.addingTimeInterval(-14 * 86_400)
        let short = sortedUnique(records.filter { matches($0, shortWindow) && $0.timestamp >= cutoff })
        let weekly = sortedUnique(records.filter { matches($0, weeklyWindow) && $0.timestamp >= cutoff })
        var cycles: [[QuotaSampleRecord]] = []
        for sample in short {
            if let last = cycles.last?.last, let reset = sample.resetsAt, sameCycle(last.resetsAt, reset) {
                cycles[cycles.count - 1].append(sample)
            } else {
                cycles.append([sample])
            }
        }
        var costs: [Double] = []
        for cycle in cycles {
            guard cycle.count >= 3, let first = cycle.first, let last = cycle.last,
                  let end = first.resetsAt, end <= now,
                  first.timestamp >= end.addingTimeInterval(-18_000 - 60),
                  first.timestamp <= end.addingTimeInterval(-18_000 + min(maximumGap, 300)),
                  last.timestamp <= end, end.timeIntervalSince(last.timestamp) <= min(maximumGap, 300),
                  last.timestamp.timeIntervalSince(first.timestamp) >= 17_400,
                  cycle.allSatisfy({ valid($0.remainingPercent) }),
                  zip(cycle, cycle.dropFirst()).allSatisfy({
                      $1.timestamp.timeIntervalSince($0.timestamp) <= maximumGap && $0.remainingPercent >= $1.remainingPercent
                  }), first.remainingPercent > last.remainingPercent else { continue }
            // Weekly readings must cover the same session, without a reset/refill or missing intervals.
            let weekSamples = weekly.filter { $0.timestamp >= first.timestamp && $0.timestamp <= last.timestamp }
            guard weekSamples.count >= 3, let weekFirst = weekSamples.first, let weekLast = weekSamples.last,
                  weekFirst.timestamp.timeIntervalSince(first.timestamp) <= 60,
                  last.timestamp.timeIntervalSince(weekLast.timestamp) <= 60,
                  let weeklyReset = weekFirst.resetsAt, weeklyReset > last.timestamp,
                  weekSamples.allSatisfy({ valid($0.remainingPercent) && sameCycle($0.resetsAt, weeklyReset) }),
                  zip(weekSamples, weekSamples.dropFirst()).allSatisfy({
                      $1.timestamp.timeIntervalSince($0.timestamp) <= maximumGap && $0.remainingPercent >= $1.remainingPercent
                  }) else { continue }
            let cost = weekFirst.remainingPercent - weekLast.remainingPercent
            // Ignore tiny changes dominated by percentage rounding; don't create huge session counts.
            if cost >= 1 { costs.append(cost) }
        }
        guard costs.count >= 3 else { return nil }
        costs.sort()
        let middle = costs.count / 2
        let median = costs.count.isMultiple(of: 2) ? (costs[middle - 1] + costs[middle]) / 2 : costs[middle]
        return WeeklySessionEstimate(count: Int(floor(weeklyWindow.remainingPercent! / median)),
                                     typicalConsumption: median, observedSessions: costs.count,
                                     fractionalCount: weeklyWindow.remainingPercent! / median)
    }

    private static func matches(_ record: QuotaSampleRecord, _ window: UsageWindow) -> Bool {
        if let id = record.windowID { return id == window.id }
        return record.windowLabel == window.label
    }

    private static func sameCycle(_ lhs: Date?, _ rhs: Date) -> Bool {
        lhs.map { abs($0.timeIntervalSince(rhs)) <= 60 } ?? false
    }

    private static func valid(_ value: Double) -> Bool { value.isFinite && (0...100).contains(value) }

    private static func sortedUnique(_ records: [QuotaSampleRecord]) -> [QuotaSampleRecord] {
        var byTimestamp: [Date: QuotaSampleRecord] = [:]
        for record in records { byTimestamp[record.timestamp] = record }
        return byTimestamp.values.sorted { $0.timestamp < $1.timestamp }
    }
}
