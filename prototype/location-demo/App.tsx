import { StatusBar } from "expo-status-bar";
import { useEffect, useState } from "react";
import {
  StyleSheet,
  Text,
  View,
  TouchableOpacity,
  ActivityIndicator,
  Platform,
} from "react-native";
import * as Location from "expo-location";

/** 位置情報の状態 */
type LocationState =
  | { status: "idle" }
  | { status: "loading" }
  | { status: "granted"; coords: Location.LocationObjectCoords }
  | { status: "denied"; message: string }
  | { status: "error"; message: string };

export default function App() {
  const [locationState, setLocationState] = useState<LocationState>({
    status: "idle",
  });

  /** 現在地を取得する */
  const fetchLocation = async () => {
    setLocationState({ status: "loading" });

    try {
      // 権限リクエスト
      const { status } = await Location.requestForegroundPermissionsAsync();

      if (status !== "granted") {
        setLocationState({
          status: "denied",
          message: "位置情報の権限が許可されていません",
        });
        return;
      }

      // 現在地取得
      const location = await Location.getCurrentPositionAsync({
        accuracy: Location.Accuracy.High,
      });

      setLocationState({
        status: "granted",
        coords: location.coords,
      });
    } catch (e) {
      setLocationState({
        status: "error",
        message: e instanceof Error ? e.message : "不明なエラーが発生しました",
      });
    }
  };

  useEffect(() => {
    fetchLocation();
  }, []);

  return (
    <View style={styles.container}>
      <StatusBar style="auto" />

      <Text style={styles.title}>AccessRoute</Text>
      <Text style={styles.subtitle}>現在地取得プロトタイプ</Text>

      <View style={styles.card}>
        {locationState.status === "idle" || locationState.status === "loading" ? (
          <View style={styles.loadingContainer}>
            <ActivityIndicator size="large" color="#007AFF" />
            <Text style={styles.loadingText}>現在地を取得中...</Text>
          </View>
        ) : locationState.status === "granted" ? (
          <View>
            <Text style={styles.successLabel}>現在地を取得しました</Text>
            <View style={styles.coordRow}>
              <Text style={styles.coordLabel}>緯度</Text>
              <Text style={styles.coordValue}>
                {locationState.coords.latitude.toFixed(6)}
              </Text>
            </View>
            <View style={styles.coordRow}>
              <Text style={styles.coordLabel}>経度</Text>
              <Text style={styles.coordValue}>
                {locationState.coords.longitude.toFixed(6)}
              </Text>
            </View>
            {locationState.coords.altitude != null && (
              <View style={styles.coordRow}>
                <Text style={styles.coordLabel}>高度</Text>
                <Text style={styles.coordValue}>
                  {locationState.coords.altitude.toFixed(1)} m
                </Text>
              </View>
            )}
            <View style={styles.coordRow}>
              <Text style={styles.coordLabel}>精度</Text>
              <Text style={styles.coordValue}>
                ±{locationState.coords.accuracy?.toFixed(1) ?? "不明"} m
              </Text>
            </View>
          </View>
        ) : (
          <View>
            <Text style={styles.errorLabel}>
              {locationState.status === "denied" ? "権限エラー" : "取得エラー"}
            </Text>
            <Text style={styles.errorMessage}>{locationState.message}</Text>
          </View>
        )}
      </View>

      <TouchableOpacity
        style={styles.button}
        onPress={fetchLocation}
        activeOpacity={0.7}
        accessibilityLabel="現在地を再取得"
        accessibilityHint="ボタンを押すと現在地を再度取得します"
      >
        <Text style={styles.buttonText}>現在地を再取得</Text>
      </TouchableOpacity>

      <Text style={styles.note}>
        {Platform.OS === "ios"
          ? "Expo Go で実行中"
          : Platform.OS === "android"
            ? "Expo Go (Android) で実行中"
            : "Web ブラウザで実行中"}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#F5F5F7",
    alignItems: "center",
    justifyContent: "center",
    padding: 24,
  },
  title: {
    fontSize: 28,
    fontWeight: "bold",
    color: "#1A1A1A",
    marginBottom: 4,
  },
  subtitle: {
    fontSize: 16,
    color: "#666",
    marginBottom: 32,
  },
  card: {
    backgroundColor: "#FFFFFF",
    borderRadius: 16,
    padding: 24,
    width: "100%",
    maxWidth: 360,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 8,
    elevation: 4,
    minHeight: 160,
    justifyContent: "center",
  },
  loadingContainer: {
    alignItems: "center",
    gap: 12,
  },
  loadingText: {
    fontSize: 16,
    color: "#666",
  },
  successLabel: {
    fontSize: 16,
    fontWeight: "600",
    color: "#34C759",
    marginBottom: 16,
    textAlign: "center",
  },
  coordRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    paddingVertical: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: "#E5E5E5",
  },
  coordLabel: {
    fontSize: 16,
    color: "#666",
  },
  coordValue: {
    fontSize: 16,
    fontWeight: "600",
    color: "#1A1A1A",
  },
  errorLabel: {
    fontSize: 16,
    fontWeight: "600",
    color: "#FF3B30",
    marginBottom: 8,
    textAlign: "center",
  },
  errorMessage: {
    fontSize: 14,
    color: "#666",
    textAlign: "center",
  },
  button: {
    backgroundColor: "#007AFF",
    borderRadius: 12,
    paddingVertical: 14,
    paddingHorizontal: 32,
    marginTop: 24,
    minWidth: 200,
    minHeight: 44,
    alignItems: "center",
    justifyContent: "center",
  },
  buttonText: {
    fontSize: 17,
    fontWeight: "600",
    color: "#FFFFFF",
  },
  note: {
    fontSize: 12,
    color: "#999",
    marginTop: 16,
  },
});
