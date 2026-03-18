
import Foundation
import Combine

/// アプリケーション全体で共有される状態を管理するクラス
/// SwiftUIのEnvironmentObjectとして利用されることを想定
@MainActor
final class AppState: ObservableObject {
    
    /// 地図に表示するよう要求された推薦スポットのリスト
    /// ChatViewModelがこの値を更新し、HomeViewModelがこれを監視して地図にピンを表示する
    @Published var spotsToShowOnMap: [RecommendedSpot] = []

}
