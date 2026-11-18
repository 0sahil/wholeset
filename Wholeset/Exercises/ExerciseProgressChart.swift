// SPDX-License-Identifier: GPL-3.0-or-later

import Charts
import SwiftUI
import WholesetKit

/// A point of the progress chart, already in the display unit.
struct ProgressChartPoint: Identifiable, Equatable {
    /// The session's identifier.
    let id: UUID
    let date: Date
    /// The value in the display unit.
    let value: Double
    /// What VoiceOver reads for the value, with its unit.
    let spokenValue: String
}

/// A line with a dot per session. Tapping near a dot opens that session; VoiceOver reads
/// each dot (date and value), and the chart offers an Audio Graph.
struct ExerciseProgressChart: View {
    let points: [ProgressChartPoint]
    /// Includes zero on the value axis (for volume), instead of fitting the values.
    let includesZero: Bool
    let valueName: String
    let onSelect: (UUID) -> Void

    /// How far from a dot, in points, a tap still selects it.
    private let tapTolerance: CGFloat = 44

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Date", point.date), y: .value(valueName, point.value))
                // Straight segments: a curve would show values between sessions that never happened.
                .interpolationMethod(.linear)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            PointMark(x: .value("Date", point.date), y: .value(valueName, point.value))
                .symbolSize(point.id == points.last?.id ? 64 : 24)
                .foregroundStyle(.tint)
                .accessibilityLabel(HistoryFormat.shortDate(point.date))
                .accessibilityValue(point.spokenValue)
        }
        .chartYScale(domain: .automatic(includesZero: includesZero))
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        select(at: location, proxy: proxy, geometry: geometry)
                    }
            }
            .accessibilityHidden(true)
        }
        .accessibilityLabel(valueName)
        .frame(height: 200)
    }

    /// Opens the session of the dot nearest to the tap, if it is close enough.
    private func select(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let x = location.x - frame.origin.x
        let y = location.y - frame.origin.y
        var best: (point: ProgressChartPoint, distance: CGFloat)?
        for point in points {
            guard let position = proxy.position(for: (x: point.date, y: point.value)) else { continue }
            let distance = hypot(position.x - x, position.y - y)
            if distance < (best?.distance ?? .infinity) { best = (point, distance) }
        }
        guard let best, best.distance <= tapTolerance else { return }
        onSelect(best.point.id)
    }
}
