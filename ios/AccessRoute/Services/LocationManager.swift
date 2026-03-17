import CoreLocation

// 現在地の取得・監視を管理するサービス
@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?

    private let manager = CLLocationManager()

    // デフォルト位置（東京駅）
    // デフォルト位置（溝の口駅）
    static let defaultLocation = CLLocationCoordinate2D(latitude: 35.6006, longitude: 139.6107)

    // 現在地またはデフォルト位置を返す
    var locationOrDefault: CLLocationCoordinate2D {
        currentLocation ?? Self.defaultLocation
    }

    // 位置情報が利用可能か
    var isLocationAvailable: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10 // 10m移動ごとに更新
        authorizationStatus = manager.authorizationStatus
    }

    // 位置情報の許可をリクエスト
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    // 位置情報の取得を開始
    func startUpdating() {
        guard isLocationAvailable else {
            requestPermission()
            return
        }
        manager.startUpdatingLocation()
    }

    // 位置情報の取得を停止
    func stopUpdating() {
        manager.stopUpdatingLocation()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location.coordinate
            self.errorMessage = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            // ユーザーが拒否した場合は静かに処理
            if let clError = error as? CLError, clError.code == .denied {
                self.errorMessage = nil
                return
            }
            self.errorMessage = "位置情報の取得に失敗しました"
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.startUpdatingLocation()
            case .denied, .restricted:
                self.errorMessage = nil
                self.currentLocation = nil
            default:
                break
            }
        }
    }
}
