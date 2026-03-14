import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  View,
  Text,
  TextInput,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  ActivityIndicator,
  Platform,
  Alert,
} from 'react-native';
import MapView, { Marker, Region } from '../../src/components/MapViewWrapper';
import { useRouter } from 'expo-router';
import { SpotSummary } from '../../src/types';
import { getNearbySpots, getPlaceSuggestions, reverseGeocodeLocation } from '../../src/services/api';
import * as Location from 'expo-location';

// デフォルト位置（東京駅付近）
const DEFAULT_REGION: Region = {
  latitude: 35.6812,
  longitude: 139.7671,
  latitudeDelta: 0.008,
  longitudeDelta: 0.008,
};

// スコアに応じた色を返す
function scoreColor(score: number): string {
  if (score >= 80) return '#34C759';
  if (score >= 50) return '#FF9500';
  return '#FF3B30';
}

// 距離テキスト
function distanceText(meters: number): string {
  if (meters >= 1000) {
    return `${(meters / 1000).toFixed(1)}km`;
  }
  return `${Math.round(meters)}m`;
}

// スポットカテゴリのラベル
function categoryLabel(category: string): string {
  const labels: Record<string, string> = {
    restroom: 'トイレ',
    rest_area: '休憩所',
    cafe: 'カフェ',
    elevator: 'エレベーター',
    parking: '駐車場',
    station: '駅',
  };
  return labels[category] ?? category;
}

// バックエンドAPI経由で Places Autocomplete 候補を取得
type PlaceSuggestion = {
  description: string;
  place_id: string;
};

async function fetchPlaceSuggestions(input: string): Promise<PlaceSuggestion[]> {
  if (!input || input.length < 2) return [];
  try {
    return await getPlaceSuggestions(input);
  } catch {
    // フォールバック
  }
  return [];
}

// モックデータ（API未接続時のフォールバック）
// 渡された座標の周辺にスポットを生成する
function mockNearbySpots(centerLat: number, centerLng: number): SpotSummary[] {
  return [
    {
      spotId: 'spot_nearby_1',
      name: 'バリアフリートイレ',
      category: 'restroom',
      location: { lat: centerLat + 0.0003, lng: centerLng + 0.0004 },
      distanceMeters: 50,
      accessibilityScore: 95,
      wheelchairAccessible: true,
    },
    {
      spotId: 'spot_nearby_2',
      name: '休憩ベンチ',
      category: 'rest_area',
      location: { lat: centerLat - 0.0004, lng: centerLng - 0.0006 },
      distanceMeters: 120,
      accessibilityScore: 80,
      wheelchairAccessible: true,
    },
    {
      spotId: 'spot_nearby_3',
      name: 'カフェ',
      category: 'cafe',
      location: { lat: centerLat + 0.0008, lng: centerLng + 0.0009 },
      distanceMeters: 200,
      accessibilityScore: 72,
      wheelchairAccessible: false,
    },
  ];
}

// おすすめスポットのモックデータ
function mockRecommendedSpots(): SpotSummary[] {
  return [
    {
      spotId: 'rec_1',
      name: '丸の内バリアフリー広場',
      category: 'park',
      location: { lat: 35.6818, lng: 139.7660 },
      distanceMeters: 150,
      accessibilityScore: 95,
      wheelchairAccessible: true,
    },
    {
      spotId: 'rec_wc_1',
      name: '車椅子対応エレベーター 東京駅',
      category: 'elevator',
      location: { lat: 35.6814, lng: 139.7670 },
      distanceMeters: 30,
      accessibilityScore: 98,
      wheelchairAccessible: true,
    },
    {
      spotId: 'rec_wc_2',
      name: '多目的トイレ KITTE',
      category: 'restroom',
      location: { lat: 35.6807, lng: 139.7649 },
      distanceMeters: 100,
      accessibilityScore: 96,
      wheelchairAccessible: true,
    },
  ];
}

export default function HomeScreen() {
  const router = useRouter();
  const [searchText, setSearchText] = useState('');
  const [nearbySpots, setNearbySpots] = useState<SpotSummary[]>([]);
  const [recommendedSpots, setRecommendedSpots] = useState<SpotSummary[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [initialRegion, setInitialRegion] = useState<Region>(DEFAULT_REGION);
  const initialRegionSetRef = useRef(false); // initialRegion は一度だけ設定
  const [suggestions, setSuggestions] = useState<PlaceSuggestion[]>([]);
  const [showSuggestions, setShowSuggestions] = useState(false);
  const [userLocation, setUserLocation] = useState<Location.LocationObjectCoords | null>(null);
  const [locationReady, setLocationReady] = useState(false);
  const [currentAddress, setCurrentAddress] = useState<string | null>(null);
  const debounceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const suggestTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const mapRef = useRef<any>(null);

  // 周辺スポット取得
  const fetchNearbySpots = useCallback(async (lat: number, lng: number) => {
    setIsLoading(true);
    try {
      const spots = await getNearbySpots(lat, lng);
      setNearbySpots(spots);
    } catch {
      // API未接続時は現在地周辺のモックデータを使用
      setNearbySpots(mockNearbySpots(lat, lng));
    } finally {
      setIsLoading(false);
    }
  }, []);

  // マップ移動時のデバウンス付き再取得（initialRegion は変更しない）
  const handleRegionChangeComplete = useCallback(
    (newRegion: Region) => {
      if (debounceTimerRef.current) {
        clearTimeout(debounceTimerRef.current);
      }
      debounceTimerRef.current = setTimeout(() => {
        fetchNearbySpots(newRegion.latitude, newRegion.longitude);
      }, 500);
    },
    [fetchNearbySpots],
  );

  // 逆ジオコーディングで住所を取得
  const fetchAddress = useCallback(async (lat: number, lng: number) => {
    try {
      const address = await reverseGeocodeLocation(lat, lng);
      setCurrentAddress(address);
    } catch {
      // API失敗時は expo-location のローカル逆ジオコーディングを試行
      try {
        const results = await Location.reverseGeocodeAsync({ latitude: lat, longitude: lng });
        if (results.length > 0) {
          const r = results[0];
          const parts = [r.region, r.city, r.district, r.street, r.name].filter(Boolean);
          setCurrentAddress(parts.join(' ') || `${lat.toFixed(4)}, ${lng.toFixed(4)}`);
        }
      } catch {
        setCurrentAddress(`${lat.toFixed(4)}, ${lng.toFixed(4)}`);
      }
    }
  }, []);

  // 現在地を取得してマップを移動
  useEffect(() => {
    (async () => {
      try {
        const { status } = await Location.requestForegroundPermissionsAsync();

        // おすすめスポットのモックデータをセット
        setRecommendedSpots(mockRecommendedSpots());

        if (status !== 'granted') {
          setLocationReady(true);
          fetchNearbySpots(DEFAULT_REGION.latitude, DEFAULT_REGION.longitude);
          return;
        }

        const location = await Location.getCurrentPositionAsync({
          accuracy: Location.Accuracy.Balanced,
        });
        const { latitude, longitude } = location.coords;
        setUserLocation(location.coords);
        fetchAddress(latitude, longitude);

        // initialRegion は一度だけ設定（以降のマップ操作で上書きしない）
        if (!initialRegionSetRef.current) {
          initialRegionSetRef.current = true;
          setInitialRegion({
            latitude,
            longitude,
            latitudeDelta: 0.008,
            longitudeDelta: 0.008,
          });
        }
        setLocationReady(true);
        fetchNearbySpots(latitude, longitude);
      } catch {
        setLocationReady(true);
        fetchNearbySpots(DEFAULT_REGION.latitude, DEFAULT_REGION.longitude);
      }
    })();

    return () => {
      if (debounceTimerRef.current) {
        clearTimeout(debounceTimerRef.current);
      }
      if (suggestTimerRef.current) {
        clearTimeout(suggestTimerRef.current);
      }
    };
  }, [fetchNearbySpots, fetchAddress]);

  // 検索テキスト変更時にサジェスト取得
  const handleSearchTextChange = useCallback((text: string) => {
    setSearchText(text);
    if (suggestTimerRef.current) {
      clearTimeout(suggestTimerRef.current);
    }
    if (text.trim().length >= 2) {
      suggestTimerRef.current = setTimeout(async () => {
        const results = await fetchPlaceSuggestions(text);
        setSuggestions(results);
        setShowSuggestions(results.length > 0);
      }, 300);
    } else {
      setSuggestions([]);
      setShowSuggestions(false);
    }
  }, []);

  // 検索実行 -> ルート画面に遷移
  const handleSearch = useCallback(
    (destination?: string) => {
      const trimmed = (destination || searchText).trim();
      if (!trimmed) return;
      setShowSuggestions(false);
      const params = new URLSearchParams({ destination: trimmed });
      if (userLocation) {
        params.set('originLat', userLocation.latitude.toString());
        params.set('originLng', userLocation.longitude.toString());
      }
      router.navigate(`/(tabs)/route?${params.toString()}`);
    },
    [searchText, router],
  );

  // サジェスト選択
  const handleSuggestionSelect = useCallback(
    (suggestion: PlaceSuggestion) => {
      setSearchText(suggestion.description);
      setShowSuggestions(false);
      handleSearch(suggestion.description);
    },
    [handleSearch],
  );

  // おすすめスポット選択
  const handleSelectSpot = useCallback((spot: SpotSummary) => {
    const { lat, lng } = spot.location;
    const jsCommand = `
      map.panTo({lat: ${lat}, lng: ${lng}});
      map.setZoom(17);
      true;
    `;
    mapRef.current?.injectJavaScript(jsCommand);
  }, []);

  // クイックアクション
  const quickActions = [
    { label: '最寄りトイレ', icon: 'WC', query: 'バリアフリートイレ' },
    { label: 'エレベーター', icon: 'EV', query: 'エレベーター' },
    { label: '休憩所', icon: 'Rest', query: '休憩所' },
  ];

  return (
    <View style={styles.container}>
      {/* 地図 */}
      <MapView
        ref={mapRef}
        style={styles.map}
        initialRegion={initialRegion}
        onRegionChangeComplete={handleRegionChangeComplete}
        showsUserLocation
        showsMyLocationButton={false}
        userLocationCoords={userLocation ? { latitude: userLocation.latitude, longitude: userLocation.longitude } : undefined}
        accessibilityLabel="地図"
      >
        {/* 周辺スポットマーカー */}
        {nearbySpots.map((spot) => (
          <Marker
            key={spot.spotId}
            coordinate={{
              latitude: spot.location.lat,
              longitude: spot.location.lng,
            }}
            title={spot.name}
            description={`${categoryLabel(spot.category)} - スコア: ${spot.accessibilityScore}`}
            pinColor={scoreColor(spot.accessibilityScore)}
          />
        ))}
        {/* おすすめスポットマーカー */}
        {recommendedSpots.map((spot) => (
          <Marker
            key={spot.spotId}
            coordinate={{
              latitude: spot.location.lat,
              longitude: spot.location.lng,
            }}
            title={spot.name}
            description={`おすすめ: ${spot.name}`}
            pinColor="blue"
          />
        ))}
      </MapView>

      {/* 検索バー */}
      <View style={styles.searchBarContainer}>
        <View style={styles.searchBar}>
          <Text style={styles.searchIcon}>&#x1F50D;</Text>
          <TextInput
            style={styles.searchInput}
            placeholder="目的地を検索..."
            placeholderTextColor="#999"
            value={searchText}
            onChangeText={handleSearchTextChange}
            onSubmitEditing={() => handleSearch()}
            onFocus={() => {
              if (suggestions.length > 0) setShowSuggestions(true);
            }}
            returnKeyType="search"
            accessibilityLabel="目的地検索フィールド"
          />
          {searchText.length > 0 && (
            <TouchableOpacity
              onPress={() => {
                setSearchText('');
                setSuggestions([]);
                setShowSuggestions(false);
              }}
              style={styles.clearButton}
              accessibilityLabel="検索テキストをクリア"
              accessibilityHint="入力した検索テキストを削除します"
              hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
            >
              <Text style={styles.clearIcon}>{'\u2715'}</Text>
            </TouchableOpacity>
          )}
          {searchText.length > 0 && (
            <TouchableOpacity
              onPress={() => handleSearch()}
              style={styles.searchSubmitButton}
              accessibilityLabel="ルート検索を実行"
              accessibilityHint="入力した目的地へのルート検索画面に移動します"
              hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
            >
              <Text style={styles.searchSubmitIcon}>{'\u2192'}</Text>
            </TouchableOpacity>
          )}
        </View>

        {/* 検索サジェスト */}
        {showSuggestions && suggestions.length > 0 && (
          <View style={styles.suggestionsContainer}>
            {suggestions.map((s, idx) => (
              <TouchableOpacity
                key={s.place_id + idx}
                style={styles.suggestionRow}
                onPress={() => handleSuggestionSelect(s)}
                accessibilityLabel={`${s.description}を選択`}
              >
                <Text style={styles.suggestionIcon}>{'\u{1F4CD}'}</Text>
                <Text style={styles.suggestionText} numberOfLines={1}>
                  {s.description}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
        )}
      </View>

      {/* クイックアクション */}
      <View style={styles.quickActionsContainer}>
        {quickActions.map((action) => (
          <TouchableOpacity
            key={action.label}
            style={styles.quickActionButton}
            onPress={() => {
              setSearchText(action.query);
              handleSearch(action.query);
            }}
            accessibilityLabel={`${action.label}を検索`}
          >
            <Text style={styles.quickActionIcon}>{action.icon}</Text>
            <Text style={styles.quickActionLabel}>{action.label}</Text>
          </TouchableOpacity>
        ))}
      </View>

      {/* 現在地情報 */}
      {userLocation && currentAddress && (
        <View style={styles.locationInfoContainer}>
          <Text style={styles.locationInfoLabel}>現在地</Text>
          <Text style={styles.locationInfoAddress} numberOfLines={2}>
            {currentAddress}
          </Text>
          <Text style={styles.locationInfoCoords}>
            {userLocation.latitude.toFixed(6)}, {userLocation.longitude.toFixed(6)}
          </Text>
        </View>
      )}

      {/* 周辺スポット */}
      {isLoading ? (
        <View style={styles.spotsContainer}>
          <ActivityIndicator size="small" color="#007AFF" />
        </View>
      ) : recommendedSpots.length > 0 ? (
        <View style={styles.spotsContainer}>
          <Text style={styles.spotsTitle}>あなたへのおすすめ</Text>
          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={styles.spotsScroll}
          >
            {recommendedSpots.map((spot) => (
              <TouchableOpacity
                key={spot.spotId}
                style={styles.spotCard}
                activeOpacity={0.7}
                onPress={() => handleSelectSpot(spot)}
                accessibilityLabel={`${spot.name}、${categoryLabel(spot.category)}、スコア${spot.accessibilityScore}、${distanceText(spot.distanceMeters)}`}
              >
                <View style={styles.spotScoreRow}>
                  <Text
                    style={[
                      styles.spotCategory,
                      { color: scoreColor(spot.accessibilityScore) },
                    ]}
                  >
                    {categoryLabel(spot.category)}
                  </Text>
                  <Text
                    style={[
                      styles.spotScore,
                      { color: scoreColor(spot.accessibilityScore) },
                    ]}
                  >
                    {spot.accessibilityScore}
                  </Text>
                </View>
                <Text style={styles.spotName} numberOfLines={1}>
                  {spot.name}
                </Text>
                <Text style={styles.spotDistance}>
                  {distanceText(spot.distanceMeters)}
                </Text>
              </TouchableOpacity>
            ))}
          </ScrollView>
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  map: {
    ...StyleSheet.absoluteFillObject,
  },

  // 検索バー
  searchBarContainer: {
    position: 'absolute',
    top: Platform.OS === 'ios' ? 56 : 8,
    left: 16,
    right: 16,
    zIndex: 100,
  },
  searchBar: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(255,255,255,0.97)',
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.15,
    shadowRadius: 6,
    elevation: 5,
  },
  searchIcon: {
    fontSize: 16,
    marginRight: 8,
  },
  searchInput: {
    flex: 1,
    fontSize: 16,
    color: '#333',
    paddingVertical: 0,
  },
  clearButton: {
    padding: 4,
    marginLeft: 4,
  },
  clearIcon: {
    fontSize: 14,
    color: '#999',
    fontWeight: '600',
  },
  searchSubmitButton: {
    marginLeft: 8,
    backgroundColor: '#007AFF',
    borderRadius: 14,
    width: 28,
    height: 28,
    alignItems: 'center',
    justifyContent: 'center',
  },
  searchSubmitIcon: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '700',
  },

  // 検索サジェスト
  suggestionsContainer: {
    backgroundColor: 'rgba(255,255,255,0.98)',
    borderRadius: 12,
    marginTop: 4,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.12,
    shadowRadius: 4,
    elevation: 4,
    overflow: 'hidden',
  },
  suggestionRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#E5E5EA',
  },
  suggestionIcon: {
    fontSize: 16,
    marginRight: 10,
  },
  suggestionText: {
    flex: 1,
    fontSize: 15,
    color: '#333',
  },

  // クイックアクション
  quickActionsContainer: {
    position: 'absolute',
    top: Platform.OS === 'ios' ? 116 : 68,
    left: 16,
    flexDirection: 'row',
    gap: 8,
    zIndex: 50,
  },
  quickActionButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(255,255,255,0.95)',
    borderRadius: 20,
    paddingHorizontal: 12,
    paddingVertical: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.08,
    shadowRadius: 2,
    elevation: 2,
  },
  quickActionIcon: {
    fontSize: 12,
    fontWeight: '700',
    color: '#007AFF',
    marginRight: 4,
  },
  quickActionLabel: {
    fontSize: 13,
    color: '#333',
    fontWeight: '500',
  },

  // 周辺スポット
  spotsContainer: {
    position: 'absolute',
    bottom: 90,
    left: 0,
    right: 0,
    backgroundColor: 'rgba(255,255,255,0.92)',
    paddingVertical: 12,
  },
  spotsTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: '#333',
    marginLeft: 16,
    marginBottom: 8,
  },
  spotsScroll: {
    paddingHorizontal: 16,
    gap: 10,
  },
  spotCard: {
    width: 140,
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.08,
    shadowRadius: 3,
    elevation: 2,
  },
  spotScoreRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 4,
  },
  spotCategory: {
    fontSize: 11,
    fontWeight: '600',
  },
  spotScore: {
    fontSize: 13,
    fontWeight: '700',
  },
  spotName: {
    fontSize: 12,
    fontWeight: '500',
    color: '#333',
    marginBottom: 2,
  },
  spotDistance: {
    fontSize: 11,
    color: '#999',
  },

  // 現在地情報
  locationInfoContainer: {
    position: 'absolute',
    bottom: 250,
    left: 16,
    right: 72,
    backgroundColor: 'rgba(255,255,255,0.95)',
    borderRadius: 12,
    padding: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.12,
    shadowRadius: 4,
    elevation: 4,
    zIndex: 50,
  },
  locationInfoLabel: {
    fontSize: 11,
    fontWeight: '600',
    color: '#007AFF',
    marginBottom: 4,
  },
  locationInfoAddress: {
    fontSize: 14,
    fontWeight: '500',
    color: '#333',
    lineHeight: 20,
  },
  locationInfoCoords: {
    fontSize: 11,
    color: '#999',
    marginTop: 4,
  },

});
