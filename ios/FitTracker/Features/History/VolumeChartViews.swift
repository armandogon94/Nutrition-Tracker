//
//  VolumeChartViews.swift
//  Slice 8.4: SwiftUI Charts analytics.
//   - VolumeTrendChartView: weekly total training volume over the last 12
//     weeks (bar per ISO week).
//   - MuscleDistributionChartView: volume split by primary muscle group,
//     color-blind-safe (Okabe-Ito) with redundant symbol legend.
//
//  Both read pre-aggregated immutable structs from `HistoryService` so the
//  charts never aggregate on the main thread mid-scroll (Slice 8 perf plan).
//  Each chart exposes an `accessibilityChartDescriptor` so VoiceOver users
//  get an audio-graph summary, and a fallback text label/value.
//

import SwiftUI
import Charts

// MARK: - Weekly volume trend

struct VolumeTrendChartView: View {
    @Environment(\.appTheme) private var theme
    let points: [WeeklyVolumePoint]

    private var hasData: Bool { points.contains { $0.totalVolume > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("history.chart.weeklyVolume")
                .font(theme.font.captionMedium).tracking(1.4)
                .foregroundStyle(theme.textTertiary)

            if !hasData {
                emptyState
            } else {
                chart
            }
        }
        .padding(16)
        .themedCard()
    }

    private var chart: some View {
        Chart(points) { point in
            BarMark(
                x: .value(String(localized: "history.chart.axis.week"), point.weekStart, unit: .weekOfYear),
                y: .value(String(localized: "history.chart.axis.volume"), point.totalVolume)
            )
            .foregroundStyle(theme.accent.gradient)
            .cornerRadius(4)
        }
        .frame(height: 200)
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(theme.textTertiary.opacity(0.2))
                AxisValueLabel().foregroundStyle(theme.textTertiary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .accessibilityChartDescriptor(WeeklyVolumeDescriptor(points: points))
    }

    private var emptyState: some View {
        Text("history.chart.noData")
            .font(theme.font.body)
            .foregroundStyle(theme.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 200)
            .accessibilityLabel(Text("history.chart.noData"))
    }
}

// MARK: - Muscle distribution

struct MuscleDistributionChartView: View {
    @Environment(\.appTheme) private var theme
    let points: [MuscleVolumePoint]

    private var hasData: Bool { points.contains { $0.totalVolume > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("history.chart.muscleDistribution")
                .font(theme.font.captionMedium).tracking(1.4)
                .foregroundStyle(theme.textTertiary)

            if !hasData {
                emptyState
            } else {
                chart
                legend
            }
        }
        .padding(16)
        .themedCard()
    }

    private var chart: some View {
        Chart(points) { point in
            BarMark(
                x: .value(String(localized: "history.chart.axis.volume"), point.totalVolume),
                y: .value(String(localized: "history.chart.axis.muscle"), point.muscle.label)
            )
            .foregroundStyle(MuscleChartStyle.color(for: point.muscle))
            .cornerRadius(4)
            .annotation(position: .trailing, alignment: .leading) {
                Text(compact(point.totalVolume))
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .frame(height: CGFloat(points.count) * 38 + 20)
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(theme.textTertiary.opacity(0.2))
                AxisValueLabel().foregroundStyle(theme.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel().foregroundStyle(theme.textSecondary)
            }
        }
        .accessibilityChartDescriptor(MuscleVolumeDescriptor(points: points))
    }

    /// Redundant (non-color) legend: muscle name + its distinct symbol, so
    /// the chart is readable without color perception (WCAG 1.4.1).
    private var legend: some View {
        FlowLegend(items: points.map { ($0.muscle.label,
                                        MuscleChartStyle.symbol(for: $0.muscle),
                                        MuscleChartStyle.color(for: $0.muscle)) })
            .accessibilityHidden(true)
    }

    private var emptyState: some View {
        Text("history.chart.noData")
            .font(theme.font.body)
            .foregroundStyle(theme.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 160)
            .accessibilityLabel(Text("history.chart.noData"))
    }

    private func compact(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1fk", v / 1000) : String(Int(v))
    }
}

// MARK: - Simple wrapping legend

private struct FlowLegend: View {
    @Environment(\.appTheme) private var theme
    let items: [(label: String, symbol: String, color: Color)]

    var body: some View {
        // Two-column grid keeps it compact without a full flow-layout dep.
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)], spacing: 6) {
            ForEach(items, id: \.label) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.symbol)
                        .font(.caption2)
                        .foregroundStyle(item.color)
                    Text(item.label)
                        .font(theme.font.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Accessibility chart descriptors (audio graph for VoiceOver)

struct WeeklyVolumeDescriptor: AXChartDescriptorRepresentable {
    let points: [WeeklyVolumePoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM"
        dateFormatter.locale = Locale(identifier: "es_419")

        let xAxis = AXCategoricalDataAxisDescriptor(
            title: String(localized: "history.chart.axis.week"),
            categoryOrder: points.map { dateFormatter.string(from: $0.weekStart) }
        )
        let maxVolume = points.map(\.totalVolume).max() ?? 1
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "history.chart.axis.volume"),
            range: 0...max(maxVolume, 1),
            gridlinePositions: []
        ) { String(Int($0)) + " kg" }

        let series = AXDataSeriesDescriptor(
            name: String(localized: "history.chart.weeklyVolume"),
            isContinuous: false,
            dataPoints: points.map {
                AXDataPoint(x: dateFormatter.string(from: $0.weekStart), y: $0.totalVolume)
            }
        )
        return AXChartDescriptor(
            title: String(localized: "history.chart.weeklyVolume"),
            summary: nil,
            xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series]
        )
    }
}

struct MuscleVolumeDescriptor: AXChartDescriptorRepresentable {
    let points: [MuscleVolumePoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: String(localized: "history.chart.axis.muscle"),
            categoryOrder: points.map { $0.muscle.label }
        )
        let maxVolume = points.map(\.totalVolume).max() ?? 1
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "history.chart.axis.volume"),
            range: 0...max(maxVolume, 1),
            gridlinePositions: []
        ) { String(Int($0)) + " kg" }

        let series = AXDataSeriesDescriptor(
            name: String(localized: "history.chart.muscleDistribution"),
            isContinuous: false,
            dataPoints: points.map { AXDataPoint(x: $0.muscle.label, y: $0.totalVolume) }
        )
        return AXChartDescriptor(
            title: String(localized: "history.chart.muscleDistribution"),
            summary: nil,
            xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series]
        )
    }
}
