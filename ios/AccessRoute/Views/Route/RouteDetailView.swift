import SwiftUI
@preconcurrency import MapKit

// ルート詳細画面
struct RouteDetailView: View {
    let route: RouteResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 地図プレースホルダー
                mapSection

                // ルート概要
                routeSummarySection

                // 乗り換え情報サマリー（電車ルートの場合）
                if hasTransitSteps {
                    transitSummarySection
                }

                // 警告
                if !route.warnings.isEmpty {
                    warningsSection
                }

                // ステップバイステップ
                stepsSection

                // 沿道スポット
                if !route.nearbySpots.isEmpty {
                    nearbySpotsSection
                }
            }
            .padding(.bottom, 24)
        }
        .navigationTitle("ルート詳細")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 地図セクション

    // 全ステップのポリラインを結合した座標配列
    private var routeCoordinates: [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        for step in route.steps {
            if !step.polyline.isEmpty {
                // エンコード済みポリラインをデコード
                let decoded = PolylineDecoder.decode(step.polyline)
                // 重複する接続点を除去
                if !coordinates.isEmpty, let first = decoded.first,
                   let last = coordinates.last,
                   abs(last.latitude - first.latitude) < 1e-6,
                   abs(last.longitude - first.longitude) < 1e-6 {
                    coordinates.append(contentsOf: decoded.dropFirst())
                } else {
                    coordinates.append(contentsOf: decoded)
                }
            } else {
                // ポリラインがない場合は始点・終点を直接使用
                let start = CLLocationCoordinate2D(
                    latitude: step.startLocation.lat,
                    longitude: step.startLocation.lng
                )
                let end = CLLocationCoordinate2D(
                    latitude: step.endLocation.lat,
                    longitude: step.endLocation.lng
                )
                if coordinates.isEmpty {
                    coordinates.append(start)
                }
                coordinates.append(end)
            }
        }
        return coordinates
    }

    // ステップが電車区間かどうか判定
    private func isTransitStep(_ step: RouteStep) -> Bool {
        let instruction = step.instruction
        return instruction.contains("電車") || instruction.contains("乗車") || instruction.contains("下車")
    }

    // ステップごとの座標配列を取得
    private func stepCoordinates(for step: RouteStep) -> [CLLocationCoordinate2D] {
        if !step.polyline.isEmpty {
            return PolylineDecoder.decode(step.polyline)
        }
        return [
            CLLocationCoordinate2D(latitude: step.startLocation.lat, longitude: step.startLocation.lng),
            CLLocationCoordinate2D(latitude: step.endLocation.lat, longitude: step.endLocation.lng)
        ]
    }

    private var mapSection: some View {
        Map {
            // ステップごとに色分けしたポリライン描画
            ForEach(route.steps) { step in
                let coords = stepCoordinates(for: step)
                if coords.count >= 2 {
                    if isTransitStep(step) {
                        // 電車区間: 緑色の太い実線
                        MapPolyline(coordinates: coords)
                            .stroke(.green, lineWidth: 6)
                    } else {
                        // 徒歩区間: 青色の破線
                        MapPolyline(coordinates: coords)
                            .stroke(.blue, style: StrokeStyle(lineWidth: 4, dash: [8, 6]))
                    }
                }
            }

            // 出発地マーカー
            if let firstStep = route.steps.first {
                Marker(
                    "出発地",
                    coordinate: CLLocationCoordinate2D(
                        latitude: firstStep.startLocation.lat,
                        longitude: firstStep.startLocation.lng
                    )
                )
                .tint(.green)
            }
            // 目的地マーカー
            if let lastStep = route.steps.last {
                Marker(
                    "目的地",
                    coordinate: CLLocationCoordinate2D(
                        latitude: lastStep.endLocation.lat,
                        longitude: lastStep.endLocation.lng
                    )
                )
                .tint(.red)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .accessibilityLabel("ルート地図。出発地から目的地までの経路を表示")
    }

    // MARK: - ルート概要

    private var routeSummarySection: some View {
        HStack(spacing: 16) {
            // スコア
            VStack(spacing: 4) {
                ScoreBadgeView(score: route.accessibilityScore)
                Text(AccessibilityHelpers.scoreLabel(for: route.accessibilityScore))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 距離
            VStack(spacing: 4) {
                Image(systemName: "figure.walk")
                    .font(.title3)
                    .foregroundStyle(.blue)
                Text(AccessibilityHelpers.distanceText(meters: route.distanceMeters))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("距離")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("距離 \(AccessibilityHelpers.distanceText(meters: route.distanceMeters))")

            // 所要時間
            VStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.title3)
                    .foregroundStyle(.blue)
                Text(AccessibilityHelpers.durationText(minutes: route.durationMinutes))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("所要時間")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("所要時間 \(AccessibilityHelpers.durationText(minutes: route.durationMinutes))")
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // 電車ステップがあるか
    private var hasTransitSteps: Bool {
        route.steps.contains { step in
            step.instruction.contains("電車") || step.instruction.contains("乗車")
                || step.instruction.contains("下車") || step.instruction.contains("乗り換え")
        }
    }

    // MARK: - 乗り換えサマリーセクション

    private var transitSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("乗り換え情報", systemImage: "tram.fill")
                .font(.headline)
                .foregroundStyle(.green)

            // 各ステップを縦に表示
            ForEach(Array(route.steps.enumerated()), id: \.element.stepId) { _, step in
                let isTransit = step.instruction.contains("電車") || step.instruction.contains("乗車")
                    || step.instruction.contains("下車") || step.instruction.contains("乗り換え")
                let isWalk = step.instruction.contains("徒歩")

                if isTransit || isWalk {
                    HStack(spacing: 10) {
                        // アイコン
                        Image(systemName: isTransit ? "tram.fill" : "figure.walk")
                            .font(.caption)
                            .foregroundStyle(isTransit ? .green : .blue)
                            .frame(width: 20)

                        // 内容
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.instruction)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            if step.distanceMeters > 0 {
                                let durationMin = Int(step.durationSeconds / 60)
                                Text("\(AccessibilityHelpers.distanceText(meters: step.distanceMeters)) · 約\(max(1, durationMin))分")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        // 階段警告
                        if step.hasStairs {
                            Image(systemName: "stairs")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 4)

                    if !isWalk || step.stepId != route.steps.last?.stepId {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color.green.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    // MARK: - 警告セクション

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("注意事項", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            ForEach(route.warnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text(warning)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("注意事項: \(route.warnings.joined(separator: "、"))")
    }

    // MARK: - ステップセクション

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ナビゲーション")
                .font(.headline)
                .padding(.horizontal)
                .padding(.bottom, 8)

            ForEach(Array(route.steps.enumerated()), id: \.element.stepId) { index, step in
                StepRowView(step: step, stepNumber: index + 1, isLast: index == route.steps.count - 1)
            }
        }
    }

    // MARK: - 沿道スポットセクション

    private var nearbySpotsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("沿道のスポット")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(route.nearbySpots) { spot in
                        NavigationLink {
                            SpotDetailView(spotId: spot.spotId)
                        } label: {
                            NearbySpotCardView(spot: spot)
                        }
                        .accessibilityLabel("\(spot.name)、\(spot.category.label)、ルートから\(Int(spot.distanceFromRoute))m")
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// ステップ行
struct StepRowView: View {
    let step: RouteStep
    let stepNumber: Int
    let isLast: Bool

    // ステップが電車区間かどうか判定
    private var isTransitStep: Bool {
        let instruction = step.instruction
        return instruction.contains("電車") || instruction.contains("乗車")
            || instruction.contains("下車") || instruction.contains("乗り換え")
    }

    // ステップの種類に応じたアイコン
    private var stepIcon: String {
        if isTransitStep {
            return "tram.fill"
        }
        return "figure.walk"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // ステップ番号とライン
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(stepColor)
                        .frame(width: 28, height: 28)
                    Text("\(stepNumber)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }

                if !isLast {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }

            // ステップ内容
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    // 電車ステップには電車アイコンを表示
                    if isTransitStep {
                        Image(systemName: "tram.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Text(step.instruction)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                HStack(spacing: 12) {
                    // 距離
                    Label(
                        AccessibilityHelpers.distanceText(meters: step.distanceMeters),
                        systemImage: "arrow.right"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    // 時間
                    Label(
                        durationText,
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                // 注意事項アイコン
                HStack(spacing: 8) {
                    if step.hasStairs {
                        Label("階段あり", systemImage: "stairs")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    if step.hasSlope {
                        Label("坂道あり", systemImage: "arrow.up.right")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    if let grade = step.slopeGrade, grade > 0 {
                        Text("勾配\(String(format: "%.0f", grade))%")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stepAccessibilityLabel)
    }

    private var stepColor: Color {
        // 電車ステップは緑色
        if isTransitStep {
            return .green
        }
        if step.hasStairs || step.hasSlope {
            return .orange
        }
        return .blue
    }

    private var durationText: String {
        let minutes = step.durationSeconds / 60
        if minutes < 1 {
            return "1分未満"
        }
        return "\(Int(minutes))分"
    }

    private var stepAccessibilityLabel: String {
        var label = "ステップ\(stepNumber): \(step.instruction)。"
        label += "距離\(AccessibilityHelpers.distanceText(meters: step.distanceMeters))、"
        label += "約\(durationText)"
        if step.hasStairs { label += "。階段あり" }
        if step.hasSlope { label += "。坂道あり" }
        return label
    }
}

// 沿道スポットカード
struct NearbySpotCardView: View {
    let spot: SpotSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // カテゴリアイコン
            Image(systemName: spot.category.iconName)
                .font(.title2)
                .foregroundStyle(AccessibilityHelpers.scoreColor(for: spot.accessibilityScore))
                .frame(width: 40, height: 40)
                .background(
                    AccessibilityHelpers.scoreColor(for: spot.accessibilityScore).opacity(0.15),
                    in: Circle()
                )

            Text(spot.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text("ルートから\(Int(spot.distanceFromRoute))m")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 120)
        .padding(10)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }

}
