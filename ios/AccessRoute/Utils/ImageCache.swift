import SwiftUI

// NSCacheベースの画像キャッシュユーティリティ
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        // メモリ制限: 最大50枚、合計50MB
        cache.countLimit = 50
        cache.totalCostLimit = 50 * 1024 * 1024
    }

    // キャッシュから画像を取得
    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    // キャッシュに画像を保存
    func setImage(_ image: UIImage, forKey key: String) {
        let cost = image.pngData()?.count ?? 0
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    // キャッシュから画像を削除
    func removeImage(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    // 全キャッシュをクリア
    func clearAll() {
        cache.removeAllObjects()
    }
}

// 非同期画像読み込みView（キャッシュ対応）
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var loadedImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let loadedImage {
                content(Image(uiImage: loadedImage))
            } else {
                placeholder()
                    .task(id: url) {
                        await loadImage()
                    }
            }
        }
    }

    // 画像の非同期読み込み（キャッシュ優先）
    private func loadImage() async {
        guard let url else { return }
        let key = url.absoluteString

        // キャッシュ確認
        if let cached = ImageCache.shared.image(forKey: key) {
            loadedImage = cached
            return
        }

        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return }
            ImageCache.shared.setImage(image, forKey: key)
            await MainActor.run {
                loadedImage = image
            }
        } catch {
            // 読み込み失敗時はプレースホルダーを維持
        }
    }
}
