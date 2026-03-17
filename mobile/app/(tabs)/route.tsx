import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  View,
  Text,
  TextInput,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  ActivityIndicator,
  Dimensions,
  Alert,
  Linking,
  Platform,
} from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import MapViewWrapper, {
  RouteData,
  RouteCoordinate,
  DirectionsResult,
  DirectionsRequest,
} from '../../src/components/MapViewWrapper';
import {
  RoutePriority,
  RouteResult,
  RouteRequest,
  LatLng,
  TransportMode,
  MultiModalRoute,
  WaypointLeg,
} from '../../src/types';
import { searchRoute, getPlaceSuggestions } from '../../src/services/api';
import { parseDirectionsResult } from '../../src/services/directions';
import { getCurrentUserId } from '../../src/services/auth';
import { searchTransitRoute, enhanceTransitPolylines } from '../../src/services/transitRouter';
import { geocode } from '../../src/services/geocoding';
import { GOOGLE_MAPS_API_KEY } from '../../src/components/MapViewWrapper';
import { loadUnifiedNeeds } from '../../src/services/userNeeds';
import { fetchPersonalizedSpots, buildSearchKeywords, getSeenSpotIds, markSpotsAsSeen, filterSeenSpots, ScoredSpot } from '../../src/services/nearbySpots';

const { height: SCREEN_HEIGHT } = Dimensions.get('window');
const MAP_HEIGHT = SCREEN_HEIGHT * 0.35;

// 移動モード定義
const TRANSPORT_MODES: { value: TransportMode; label: string; icon: string }[] = [
  { value: 'walking', label: '徒歩', icon: '\u{1F6B6}' },
  { value: 'transit', label: '電車', icon: '\u{1F683}' },
  { value: 'driving', label: '車', icon: '\u{1F697}' },
  { value: 'bicycling', label: '自転車', icon: '\u{1F6B2}' },
];

// ルートの色割り当て
const ROUTE_COLORS = ['#4285F4', '#34A853', '#EA4335', '#FBBC05', '#9C27B0'];

// 移動モードごとの色
const MODE_COLORS: Record<TransportMode, string> = {
  walking: '#9E9E9E',
  transit: '#4285F4',
  driving: '#1A73E8',
  bicycling: '#FF6D00',
};

// 経由地データ
interface WaypointEntry {
  id: string;
  text: string;
  coords: LatLng | null;
  mode: TransportMode; // この経由地から次の地点までの移動手段
}

// ルーティング用の地点情報
interface RoutePoint {
  address: string;
  coords: LatLng;
  mode: TransportMode; // この地点から次の地点までの移動手段
}

// 乗り換え駅ウェイポイントマーカー（transit ルート表示用）
interface TransitStationMarker {
  latitude: number;
  longitude: number;
  title: string;
  label?: string; // 路線名ラベル（例: "山手線 → 中央線"）
  type: 'station' | 'transfer';
}

/**
 * MultiModalRoute のレッグからtransit駅マーカーを生成するユーティリティ
 */
function buildTransitStationMarkersFromRoutes(routes: MultiModalRoute[]): TransitStationMarker[] {
  const stations: TransitStationMarker[] = [];
  for (const route of routes) {
    for (let i = 0; i < route.legs.length; i++) {
      const leg = route.legs[i];
      if (leg.mode !== 'transit' || !leg.transitDetails || leg.transitDetails.length === 0) continue;
      const td = leg.transitDetails[0];
      // 乗車駅
      if (leg.origin?.lat != null && leg.origin?.lng != null) {
        const nextLine = td.lineName;
        const prevLeg = i > 0 ? route.legs[i - 1] : null;
        const prevLine = prevLeg?.mode === 'transit' && prevLeg.transitDetails?.[0]?.lineName;
        stations.push({
          latitude: leg.origin.lat,
          longitude: leg.origin.lng,
          title: td.departureStop,
          label: prevLine ? `${prevLine} → ${nextLine}` : nextLine,
          type: prevLine ? 'transfer' : 'station',
        });
      }
      // 降車駅
      if (leg.destination?.lat != null && leg.destination?.lng != null) {
        const nextLeg = i < route.legs.length - 1 ? route.legs[i + 1] : null;
        const nextLine = nextLeg?.mode === 'transit' && nextLeg.transitDetails?.[0]?.lineName;
        stations.push({
          latitude: leg.destination.lat,
          longitude: leg.destination.lng,
          title: td.arrivalStop,
          label: nextLine ? `${td.lineName} → ${nextLine}` : td.lineName,
          type: nextLine ? 'transfer' : 'station',
        });
      }
    }
  }
  // 重複除去（同じ駅名+座標）
  const seen = new Set<string>();
  return stations.filter((s) => {
    const key = `${s.title}:${s.latitude.toFixed(5)},${s.longitude.toFixed(5)}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

/**
 * 自前ルーターの TransitRouteResult から駅マーカーを生成
 */
function buildTransitStationMarkers(transitResult: ReturnType<typeof searchTransitRoute>): TransitStationMarker[] {
  const stations: TransitStationMarker[] = [];
  if (transitResult.originStation) {
    stations.push({
      latitude: transitResult.originStation.lat,
      longitude: transitResult.originStation.lng,
      title: transitResult.originStation.name,
      type: 'station',
    });
  }
  if (transitResult.destStation) {
    stations.push({
      latitude: transitResult.destStation.lat,
      longitude: transitResult.destStation.lng,
      title: transitResult.destStation.name,
      type: 'station',
    });
  }
  for (const route of transitResult.routes) {
    stations.push(...buildTransitStationMarkersFromRoutes([route]));
  }
  // 重複除去
  const seen = new Set<string>();
  return stations.filter((s) => {
    const key = `${s.title}:${s.latitude.toFixed(5)},${s.longitude.toFixed(5)}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

// スコアに応じた色を返す
function scoreColor(score: number): string {
  if (score >= 80) return '#34C759';
  if (score >= 50) return '#FF9500';
  return '#FF3B30';
}

// スコアラベル
function scoreLabel(score: number): string {
  if (score >= 80) return 'とても良い';
  if (score >= 50) return '普通';
  return '注意が必要';
}

// 距離テキスト
function distanceText(meters: number): string {
  if (meters >= 1000) {
    return `${(meters / 1000).toFixed(1)}km`;
  }
  return `${Math.round(meters)}m`;
}

// 所要時間テキスト
function durationText(minutes: number): string {
  if (minutes >= 60) {
    const h = Math.floor(minutes / 60);
    const m = minutes % 60;
    return m > 0 ? `${h}時間${m}分` : `${h}時間`;
  }
  return `${minutes}分`;
}

// 時刻フォーマット
// Google Maps DirectionsService は "14:30" のようなテキストを返す
// ISO文字列の場合もあるので両方対応
function formatTime(timeString?: string): string | null {
  if (!timeString) return null;
  // 既に "HH:MM" 形式ならそのまま返す
  if (/^\d{1,2}:\d{2}$/.test(timeString.trim())) {
    return timeString.trim();
  }
  // "午後2:30" のような日本語形式
  if (/[午前後]/.test(timeString)) {
    return timeString.trim();
  }
  // ISO文字列の場合
  try {
    const date = new Date(timeString);
    if (!isNaN(date.getTime())) {
      const hours = date.getHours().toString().padStart(2, '0');
      const mins = date.getMinutes().toString().padStart(2, '0');
      return `${hours}:${mins}`;
    }
  } catch {
    // パース失敗
  }
  // パースできない場合はそのまま返す（何かしらのテキスト）
  return timeString.trim() || null;
}

// モードラベル
function modeLabel(mode: TransportMode): string {
  const m = TRANSPORT_MODES.find((t) => t.value === mode);
  return m ? m.label : mode;
}

// モードアイコン
function modeIcon(mode: TransportMode): string {
  const m = TRANSPORT_MODES.find((t) => t.value === mode);
  return m ? m.icon : '\u{1F6B6}';
}

// Google Maps Encoded Polyline をデコード
function decodePolyline(encoded: string): RouteCoordinate[] {
  const coords: RouteCoordinate[] = [];
  let index = 0;
  let lat = 0;
  let lng = 0;

  while (index < encoded.length) {
    let b: number;
    let shift = 0;
    let result = 0;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    const dlat = result & 1 ? ~(result >> 1) : result >> 1;
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    const dlng = result & 1 ? ~(result >> 1) : result >> 1;
    lng += dlng;

    coords.push({ latitude: lat / 1e5, longitude: lng / 1e5 });
  }
  return coords;
}

/**
 * Google Directions API REST を直接呼んで transit ポリラインを取得する。
 * overview_polyline ではなく、各ステップの個別ポリラインを結合して
 * 高精度な線路ポリラインを返す。
 * エラー時は null を返し、呼び出し元のフォールバック処理に任せる。
 */
async function fetchTransitPolyline(
  origin: { lat: number; lng: number },
  dest: { lat: number; lng: number },
): Promise<string | null> {
  if (!GOOGLE_MAPS_API_KEY) return null;
  try {
    const url =
      `https://maps.googleapis.com/maps/api/directions/json` +
      `?origin=${origin.lat},${origin.lng}` +
      `&destination=${dest.lat},${dest.lng}` +
      `&mode=transit` +
      `&language=ja` +
      `&key=${GOOGLE_MAPS_API_KEY}`;
    const res = await fetch(url);
    if (!res.ok) return null;
    const data = await res.json();
    if (data.status !== 'OK' || !data.routes || data.routes.length === 0) return null;

    // 各ステップの個別ポリラインを結合して高解像度ポリラインを構築
    const allPoints: Array<{ lat: number; lng: number }> = [];
    const route = data.routes[0];
    for (const leg of route.legs ?? []) {
      for (const step of leg.steps ?? []) {
        // transit ステップにはサブステップがある場合がある
        const subSteps = step.steps ?? [step];
        for (const sub of subSteps) {
          if (sub.polyline?.points) {
            const decoded = decodePolyline(sub.polyline.points);
            for (const pt of decoded) {
              // 重複する最後の点を除去（前のステップの終点=次のステップの始点）
              const last = allPoints[allPoints.length - 1];
              if (!last || Math.abs(last.lat - pt.latitude) > 1e-7 || Math.abs(last.lng - pt.longitude) > 1e-7) {
                allPoints.push({ lat: pt.latitude, lng: pt.longitude });
              }
            }
          }
        }
      }
    }

    if (allPoints.length < 2) {
      // フォールバック: overview_polyline を使用
      return route.overview_polyline?.points ?? null;
    }

    // 結合した高精度ポイント列をエンコードして返す
    return encodePolylineFromPoints(allPoints);
  } catch (err) {
    console.warn('[Route] fetchTransitPolyline error:', err);
    return null;
  }
}

/**
 * Google Directions API REST で徒歩ルートのポリラインを取得する。
 * 駅〜出発地/目的地間の徒歩区間を道路に沿って表示するために使用。
 */
async function fetchWalkingPolyline(
  origin: { lat: number; lng: number },
  dest: { lat: number; lng: number },
): Promise<string | null> {
  if (!GOOGLE_MAPS_API_KEY) return null;
  // 短距離（50m未満）の徒歩は直線で十分
  const dLat = (dest.lat - origin.lat) * 111320;
  const dLng = (dest.lng - origin.lng) * 111320 * Math.cos((origin.lat * Math.PI) / 180);
  const dist = Math.sqrt(dLat * dLat + dLng * dLng);
  if (dist < 50) return null;

  try {
    const url =
      `https://maps.googleapis.com/maps/api/directions/json` +
      `?origin=${origin.lat},${origin.lng}` +
      `&destination=${dest.lat},${dest.lng}` +
      `&mode=walking` +
      `&language=ja` +
      `&key=${GOOGLE_MAPS_API_KEY}`;
    const res = await fetch(url);
    if (!res.ok) return null;
    const data = await res.json();
    if (data.status !== 'OK' || !data.routes || data.routes.length === 0) return null;

    // 各ステップの個別ポリラインを結合
    const allPoints: Array<{ lat: number; lng: number }> = [];
    for (const leg of data.routes[0].legs ?? []) {
      for (const step of leg.steps ?? []) {
        if (step.polyline?.points) {
          const decoded = decodePolyline(step.polyline.points);
          for (const pt of decoded) {
            const last = allPoints[allPoints.length - 1];
            if (!last || Math.abs(last.lat - pt.latitude) > 1e-7 || Math.abs(last.lng - pt.longitude) > 1e-7) {
              allPoints.push({ lat: pt.latitude, lng: pt.longitude });
            }
          }
        }
      }
    }

    if (allPoints.length < 2) return null;
    return encodePolylineFromPoints(allPoints);
  } catch (err) {
    console.warn('[Route] fetchWalkingPolyline error:', err);
    return null;
  }
}

/**
 * ポイント配列を Google Encoded Polyline にエンコードする
 */
function encodePolylineFromPoints(points: Array<{ lat: number; lng: number }>): string {
  let encoded = '';
  let prevLat = 0;
  let prevLng = 0;

  for (const pt of points) {
    const lat = Math.round(pt.lat * 1e5);
    const lng = Math.round(pt.lng * 1e5);

    let dLat = lat - prevLat;
    let dLng = lng - prevLng;
    prevLat = lat;
    prevLng = lng;

    // エンコード処理
    for (const delta of [dLat, dLng]) {
      let val = delta < 0 ? ~(delta << 1) : delta << 1;
      while (val >= 0x20) {
        encoded += String.fromCharCode((0x20 | (val & 0x1f)) + 63);
        val >>= 5;
      }
      encoded += String.fromCharCode(val + 63);
    }
  }
  return encoded;
}

/**
 * MultiModalRoute 配列内の transit・walking レッグに対して
 * Google Directions API の実ポリラインに差し替える。
 * - transit レッグ: 線路に沿った正確なポリライン
 * - walking レッグ: 道路に沿った正確なポリライン
 */
async function enhanceRoutesWithRealPolylines(
  routes: MultiModalRoute[],
): Promise<MultiModalRoute[]> {
  // ディープコピーして元データを壊さない
  const enhanced = routes.map((r) => ({
    ...r,
    legs: r.legs.map((l) => ({
      ...l,
      steps: l.steps.map((s) => ({ ...s })),
    })),
  }));

  const promises: Promise<void>[] = [];
  for (const route of enhanced) {
    for (const leg of route.legs) {
      if (leg.mode === 'transit' && leg.transitDetails && leg.transitDetails.length > 0) {
        // transit レッグの出発駅・到着駅情報を取得
        const originStation = {
          lat: leg.origin.lat,
          lng: leg.origin.lng,
          name: leg.transitDetails[0].departureStop,
        };
        const destStation = {
          lat: leg.destination.lat,
          lng: leg.destination.lng,
          name: leg.transitDetails[leg.transitDetails.length - 1].arrivalStop,
        };

        promises.push(
          enhanceTransitPolylines(
            leg.steps,
            originStation,
            destStation,
            fetchTransitPolyline,
          ).then(() => {
            // enhanceTransitPolylines は steps を in-place で更新する
          }),
        );
      } else if (leg.mode === 'walking') {
        // walking レッグ: 道路に沿ったポリラインを取得
        promises.push(
          (async () => {
            const polyline = await fetchWalkingPolyline(
              leg.origin,
              leg.destination,
            );
            if (polyline && leg.steps.length > 0) {
              // 全ステップのポリラインを道路に沿ったものに差し替え
              leg.steps[0].polyline = polyline;
              // 複数ステップがある場合は最初のステップにまとめる
              for (let i = 1; i < leg.steps.length; i++) {
                leg.steps[i].polyline = '';
              }
            }
          })(),
        );
      }
    }
  }

  await Promise.allSettled(promises);
  return enhanced;
}

// ルートの座標配列を生成（MultiModalRoute のレッグから）
// polyline データがあればデコードして正確な道筋を描画
function buildMultiModalRouteCoordinates(route: MultiModalRoute): RouteCoordinate[] {
  const coords: RouteCoordinate[] = [];

  for (const leg of route.legs) {
    for (const step of leg.steps) {
      if (step.polyline) {
        // polyline があれば正確な道筋を使用
        const decoded = decodePolyline(step.polyline);
        coords.push(...decoded);
      } else {
        // polyline がなければ start/end を直線で接続
        coords.push({ latitude: step.startLocation.lat, longitude: step.startLocation.lng });
        coords.push({ latitude: step.endLocation.lat, longitude: step.endLocation.lng });
      }
    }

    // steps が空の場合は leg の origin/destination を使用
    if (leg.steps.length === 0) {
      coords.push({ latitude: leg.origin.lat, longitude: leg.origin.lng });
      coords.push({ latitude: leg.destination.lat, longitude: leg.destination.lng });
    }
  }

  // 重複座標を削除
  const deduped: RouteCoordinate[] = [];
  for (const c of coords) {
    const last = deduped[deduped.length - 1];
    if (!last || last.latitude !== c.latitude || last.longitude !== c.longitude) {
      deduped.push(c);
    }
  }

  // (0,0) 座標をフィルタリング
  const filtered = deduped.filter((c) => c.latitude !== 0 || c.longitude !== 0);

  if (filtered.length >= 2) return filtered;

  // フォールバック: 最初と最後のレッグの origin/destination を使用
  if (route.legs.length > 0) {
    const firstLeg = route.legs[0];
    const lastLeg = route.legs[route.legs.length - 1];
    if (firstLeg.origin && lastLeg.destination &&
        firstLeg.origin.lat != null && firstLeg.origin.lng != null &&
        lastLeg.destination.lat != null && lastLeg.destination.lng != null) {
      return [
        { latitude: firstLeg.origin.lat, longitude: firstLeg.origin.lng },
        { latitude: lastLeg.destination.lat, longitude: lastLeg.destination.lng },
      ];
    }
  }

  return filtered.length > 0 ? filtered : [];
}

// レガシー RouteResult から座標配列を生成
function buildLegacyRouteCoordinates(
  route: RouteResult,
  origin: LatLng,
  destination: LatLng,
): RouteCoordinate[] {
  const coords: RouteCoordinate[] = [];

  if (route.steps.length === 0) {
    coords.push({ latitude: origin.lat, longitude: origin.lng });
    coords.push({ latitude: destination.lat, longitude: destination.lng });
    return coords;
  }

  for (let i = 0; i < route.steps.length; i++) {
    const step = route.steps[i];
    if (i === 0) {
      coords.push({
        latitude: step.startLocation.lat,
        longitude: step.startLocation.lng,
      });
    }
    // polyline があればデコードして正確な道筋を使用
    if (step.polyline && step.polyline.length > 0) {
      const decoded = decodePolyline(step.polyline);
      if (decoded.length > 0) {
        coords.push(...decoded);
      } else {
        coords.push({
          latitude: step.endLocation.lat,
          longitude: step.endLocation.lng,
        });
      }
    } else {
      coords.push({
        latitude: step.endLocation.lat,
        longitude: step.endLocation.lng,
      });
    }
  }

  return coords;
}

// ユニークID生成
let waypointIdCounter = 0;
function generateWaypointId(): string {
  waypointIdCounter += 1;
  return `wp_${Date.now()}_${waypointIdCounter}`;
}

export default function RouteScreen() {
  const params = useLocalSearchParams<{ destination?: string; originLat?: string; originLng?: string; destLat?: string; destLng?: string }>();

  // 入力状態
  const [originText, setOriginText] = useState('現在地');
  const [destinationText, setDestinationText] = useState('');
  const [selectedMode, setSelectedMode] = useState<TransportMode>('transit');
  const [waypoints, setWaypoints] = useState<WaypointEntry[]>([]);

  // 検索結果（マルチモーダルまたはレガシー）
  const [multiModalResults, setMultiModalResults] = useState<MultiModalRoute[]>([]);
  const [legacyResults, setLegacyResults] = useState<RouteResult[]>([]);
  const [isMultiModal, setIsMultiModal] = useState(false);

  const [isSearching, setIsSearching] = useState(false);
  const [selectedRouteId, setSelectedRouteId] = useState<string | null>(null);
  const [expandedRouteId, setExpandedRouteId] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // 座標の保持
  const [originCoords, setOriginCoords] = useState<LatLng | null>(null);
  const [destCoords, setDestCoords] = useState<LatLng | null>(null);

  // transit ルートの乗り換え駅ウェイポイント
  const [transitWaypoints, setTransitWaypoints] = useState<TransitStationMarker[]>([]);

  // WebView DirectionsService用
  const [directionsReq, setDirectionsReq] = useState<DirectionsRequest | undefined>(undefined);

  // 目的地周辺おすすめスポット
  const [recommendedSpots, setRecommendedSpots] = useState<ScoredSpot[]>([]);
  const [showSpots, setShowSpots] = useState(true);

  const lastParamDestRef = useRef<string | null>(null);

  // オートコンプリートサジェスト
  const [destSuggestions, setDestSuggestions] = useState<Array<{ description: string; place_id: string }>>([]);
  const [showDestSuggestions, setShowDestSuggestions] = useState(false);
  const [originSuggestions, setOriginSuggestions] = useState<Array<{ description: string; place_id: string }>>([]);
  const [showOriginSuggestions, setShowOriginSuggestions] = useState(false);
  const suggestTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // リクエスト重複排除用ID
  const searchIdRef = useRef(0);

  // オートコンプリート取得（デバウンス付き）
  const fetchSuggestions = useCallback(
    (text: string, setter: typeof setDestSuggestions, showSetter: typeof setShowDestSuggestions) => {
      if (suggestTimerRef.current) clearTimeout(suggestTimerRef.current);
      if (text.trim().length < 2) {
        setter([]);
        showSetter(false);
        return;
      }
      suggestTimerRef.current = setTimeout(async () => {
        try {
          const results = await getPlaceSuggestions(text);
          setter(results);
          showSetter(results.length > 0);
        } catch {
          setter([]);
          showSetter(false);
        }
      }, 300);
    },
    [],
  );

  // サジェスト選択 → テキスト設定 + バックグラウンドジオコーディング
  const handleDestSuggestionSelect = useCallback(
    (suggestion: { description: string; place_id: string }) => {
      setDestinationText(suggestion.description);
      setShowDestSuggestions(false);
      setDestCoords(null);
      // バックグラウンドでジオコーディング → 検索ボタン押下時には座標が準備済み
      geocode(suggestion.description).then((coords) => {
        setDestCoords(coords);
      }).catch(() => {});
    },
    [],
  );

  const handleOriginSuggestionSelect = useCallback(
    (suggestion: { description: string; place_id: string }) => {
      setOriginText(suggestion.description);
      setShowOriginSuggestions(false);
      setOriginCoords(null);
      geocode(suggestion.description).then((coords) => {
        setOriginCoords(coords);
      }).catch(() => {});
    },
    [],
  );

  // 経由地追加（最大3つ）
  const addWaypoint = useCallback(() => {
    if (waypoints.length >= 3) return;
    setWaypoints((prev) => [
      ...prev,
      { id: generateWaypointId(), text: '', coords: null, mode: selectedMode },
    ]);
  }, [waypoints.length, selectedMode]);

  // 経由地削除
  const removeWaypoint = useCallback((id: string) => {
    setWaypoints((prev) => prev.filter((wp) => wp.id !== id));
  }, []);

  // 経由地テキスト更新
  const updateWaypointText = useCallback((id: string, text: string) => {
    setWaypoints((prev) =>
      prev.map((wp) => (wp.id === id ? { ...wp, text } : wp)),
    );
  }, []);

  // 経由地モード更新
  const updateWaypointMode = useCallback((id: string, mode: TransportMode) => {
    setWaypoints((prev) =>
      prev.map((wp) => (wp.id === id ? { ...wp, mode } : wp)),
    );
  }, []);

  // マルチモーダルルートをレッグごとに分解して RouteData 配列を生成
  // 各レッグを個別の RouteData にし、モード別に色分けする
  function buildPerLegRouteData(route: MultiModalRoute): RouteData[] {
    const isSelected = selectedRouteId === route.routeId;
    return route.legs.map((leg) => {
      // transit レッグは路線色を使用、walking はグレー
      const color =
        leg.mode === 'transit' && leg.transitDetails && leg.transitDetails.length > 0
          ? (leg.transitDetails[0].lineColor || MODE_COLORS.transit)
          : MODE_COLORS[leg.mode];

      // レッグの座標を生成
      const coords: RouteCoordinate[] = [];
      if (leg.steps.length > 0) {
        for (const step of leg.steps) {
          if (step.polyline && step.polyline.length > 0) {
            const decoded = decodePolyline(step.polyline);
            if (decoded.length > 0) {
              coords.push(...decoded);
            } else {
              coords.push({ latitude: step.startLocation.lat, longitude: step.startLocation.lng });
              coords.push({ latitude: step.endLocation.lat, longitude: step.endLocation.lng });
            }
          } else {
            coords.push({ latitude: step.startLocation.lat, longitude: step.startLocation.lng });
            coords.push({ latitude: step.endLocation.lat, longitude: step.endLocation.lng });
          }
        }
      } else {
        // ステップが無い場合は origin→destination の直線
        coords.push({ latitude: leg.origin.lat, longitude: leg.origin.lng });
        coords.push({ latitude: leg.destination.lat, longitude: leg.destination.lng });
      }

      // 重複座標を削除（隣接ステップの終点と始点が同じ駅になるため）
      const deduped: RouteCoordinate[] = [];
      for (const c of coords) {
        const last = deduped[deduped.length - 1];
        if (!last || last.latitude !== c.latitude || last.longitude !== c.longitude) {
          deduped.push(c);
        }
      }

      // (0,0) 座標をフィルタリング
      const filteredCoords = deduped.filter((c) => c.latitude !== 0 || c.longitude !== 0);

      // フォールバック: レッグの origin/destination を使用
      const fallbackCoords: RouteCoordinate[] = [];
      if (filteredCoords.length < 2) {
        if (leg.origin && leg.origin.lat != null && leg.origin.lng != null &&
            !(leg.origin.lat === 0 && leg.origin.lng === 0)) {
          fallbackCoords.push({ latitude: leg.origin.lat, longitude: leg.origin.lng });
        }
        if (leg.destination && leg.destination.lat != null && leg.destination.lng != null &&
            !(leg.destination.lat === 0 && leg.destination.lng === 0)) {
          fallbackCoords.push({ latitude: leg.destination.lat, longitude: leg.destination.lng });
        }
      }

      const finalCoords = filteredCoords.length >= 2 ? filteredCoords : fallbackCoords;

      return {
        id: `${route.routeId}_leg${leg.legIndex}`,
        coordinates: finalCoords.length >= 2 ? finalCoords : [],
        color,
        width: isSelected ? 6 : 3,
        selected: isSelected,
        mode: leg.mode as RouteData['mode'],
        dashed: leg.mode === 'walking',
      } as RouteData;
    });
  }

  // ルートデータをMapViewWrapper用に変換
  // 座標が未取得の場合はルート描画をスキップ
  const mapRoutes: RouteData[] = isMultiModal
    ? multiModalResults.flatMap((route) => buildPerLegRouteData(route))
    : (originCoords && destCoords)
      ? legacyResults.map((route, index) => ({
          id: route.routeId,
          coordinates: buildLegacyRouteCoordinates(
            route,
            originCoords,
            destCoords,
          ),
          color: ROUTE_COLORS[index % ROUTE_COLORS.length],
          width: selectedRouteId === route.routeId ? 7 : 4,
          selected: selectedRouteId === route.routeId,
        }))
      : [];

  const hasResults = isMultiModal ? multiModalResults.length > 0 : legacyResults.length > 0;

  // マップでルート選択
  const handleRouteSelect = useCallback((routeId: string) => {
    setSelectedRouteId(routeId);
  }, []);

  // フォールバック試行済みフラグ（transit → walking の自動リトライ用）
  const fallbackTriedRef = useRef(false);

  // WebView DirectionsService からの結果ハンドラ
  const handleDirectionsResult = useCallback((result: DirectionsResult) => {
    // BUG #1 修正: リクエストをクリアして再実行を防止
    setDirectionsReq(undefined);

    // リクエスト時のモードを使用（クロージャの selectedMode は古い可能性がある）
    const requestedMode = (result as DirectionsResult & { requestedMode?: string }).requestedMode as TransportMode || selectedMode;

    if (result.status === 'OK' && result.routes && result.routes.length > 0) {
      // BUG #2 修正: parseDirectionsResult を try-catch で囲む
      try {
        const parsed = parseDirectionsResult(result, requestedMode);
        if (parsed.length > 0) {
          fallbackTriedRef.current = false;
          setMultiModalResults(parsed);
          setIsMultiModal(true);
          setSelectedRouteId(parsed[0].routeId);
          // transit の場合は駅マーカーを生成
          if (requestedMode === 'transit') {
            const stations = buildTransitStationMarkersFromRoutes(parsed);
            setTransitWaypoints(stations);
          }
          setIsSearching(false);
          return;
        }
      } catch (err) {
        console.error('[Route] parseDirectionsResult error:', err);
        // パース失敗時はフォールバック
      }
    }

    // ZERO_RESULTS で driving/bicycling の場合 → walking で自動リトライ
    // transit は自前ルーターを使うため WebView フォールバック不要
    if (result.status === 'ZERO_RESULTS' && requestedMode !== 'walking' && requestedMode !== 'transit' && !fallbackTriedRef.current) {
      console.log(`[Route] ${requestedMode} で ZERO_RESULTS → walking でリトライ`);
      fallbackTriedRef.current = true;
      setErrorMessage(`${requestedMode === 'driving' ? '車' : '自転車'}のルートが見つかりませんでした。徒歩ルートを検索中...`);
      if (originCoords && destCoords) {
        requestAnimationFrame(() => {
          setDirectionsReq({
            originLat: originCoords.lat,
            originLng: originCoords.lng,
            destLat: destCoords.lat,
            destLng: destCoords.lng,
            mode: 'walking',
          });
        });
      }
      return;
    }

    // DirectionsService失敗時、バックエンドAPIにフォールバック
    console.log('[Route] DirectionsService status:', result.status, '→ バックエンドにフォールバック');
    fallbackTriedRef.current = false;
    (async () => {
      try {
        if (!originCoords || !destCoords) {
          setErrorMessage('ルートが見つかりませんでした');
          setIsSearching(false);
          return;
        }
        let userId = 'anonymous';
        try { userId = (await getCurrentUserId()) ?? 'anonymous'; } catch {}
        const req: RouteRequest = {
          origin: originCoords,
          destination: destCoords,
          userProfileId: userId,
          prioritize: 'accessible',
          mode: requestedMode,
        };
        const response = await searchRoute(req);
        if (response?.routes && response.routes.length > 0) {
          setLegacyResults(response.routes);
          setIsMultiModal(false);
          setSelectedRouteId(response.routes[0].routeId);
        } else {
          setErrorMessage('ルートが見つかりませんでした');
        }
      } catch {
        setErrorMessage('ルート検索に失敗しました。ネットワーク接続を確認してください。');
      } finally {
        setIsSearching(false);
      }
    })();
  }, [selectedMode, originCoords, destCoords]);

  // 単一区間のルーティング（transit / walking / driving）
  // transit は自前ルーター、walking は直線ウォーキングレッグ、driving は WebView Directions
  const routeSegment = useCallback(
    async (
      from: LatLng,
      to: LatLng,
      mode: TransportMode,
      fromName: string,
      toName: string,
      legIndexStart: number,
    ): Promise<{ legs: WaypointLeg[]; stations: TransitStationMarker[] }> => {
      const legs: WaypointLeg[] = [];
      const stations: TransitStationMarker[] = [];

      if (mode === 'transit') {
        const transitResult = searchTransitRoute(from, to);
        if (transitResult.routes.length > 0) {
          // 最良ルートの全レッグを取得
          const bestRoute = transitResult.routes[0];
          for (const leg of bestRoute.legs) {
            legs.push({ ...leg, legIndex: legIndexStart + legs.length });
          }
          // 乗り換え駅マーカー
          if (transitResult.originStation) {
            stations.push({
              latitude: transitResult.originStation.lat,
              longitude: transitResult.originStation.lng,
              title: transitResult.originStation.name,
              type: 'station',
            });
          }
          if (transitResult.destStation) {
            stations.push({
              latitude: transitResult.destStation.lat,
              longitude: transitResult.destStation.lng,
              title: transitResult.destStation.name,
              type: 'station',
            });
          }
          for (const leg of bestRoute.legs) {
            if (leg.mode === 'transit' && leg.transitDetails) {
              for (const td of leg.transitDetails) {
                if (leg.origin?.lat != null && leg.origin?.lng != null) {
                  stations.push({
                    latitude: leg.origin.lat,
                    longitude: leg.origin.lng,
                    title: td.departureStop,
                    type: 'transfer',
                  });
                }
                if (leg.destination?.lat != null && leg.destination?.lng != null) {
                  stations.push({
                    latitude: leg.destination.lat,
                    longitude: leg.destination.lng,
                    title: td.arrivalStop,
                    type: 'transfer',
                  });
                }
              }
            }
          }
        } else {
          // フォールバック: 徒歩レッグ
          const dist = Math.round(
            Math.sqrt(
              Math.pow((to.lat - from.lat) * 111320, 2) +
              Math.pow((to.lng - from.lng) * 111320 * Math.cos((from.lat * Math.PI) / 180), 2),
            ),
          );
          const walkMin = Math.round(dist / 80);
          legs.push({
            legIndex: legIndexStart,
            mode: 'walking',
            origin: from,
            destination: to,
            originName: fromName,
            destinationName: toName,
            distanceMeters: dist,
            durationMinutes: walkMin,
            steps: [{
              stepId: `walk_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
              instruction: `${toName}まで徒歩 約${dist}m`,
              distanceMeters: dist,
              durationSeconds: walkMin * 60,
              startLocation: from,
              endLocation: to,
              polyline: '',
              hasStairs: false,
              hasSlope: false,
            }],
          });
        }
      } else {
        // walking / driving / bicycling: 直接ウォーキングレッグを生成
        const dist = Math.round(
          Math.sqrt(
            Math.pow((to.lat - from.lat) * 111320, 2) +
            Math.pow((to.lng - from.lng) * 111320 * Math.cos((from.lat * Math.PI) / 180), 2),
          ),
        );
        const speed = mode === 'driving' ? 500 : mode === 'bicycling' ? 250 : 80; // m/分
        const durMin = Math.max(1, Math.round(dist / speed));
        const modeLabels: Record<TransportMode, string> = {
          walking: '徒歩',
          driving: '車',
          bicycling: '自転車',
          transit: '電車',
        };
        legs.push({
          legIndex: legIndexStart,
          mode,
          origin: from,
          destination: to,
          originName: fromName,
          destinationName: toName,
          distanceMeters: dist,
          durationMinutes: durMin,
          steps: [{
            stepId: `${mode}_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
            instruction: `${toName}まで${modeLabels[mode]} 約${distanceText(dist)}`,
            distanceMeters: dist,
            durationSeconds: durMin * 60,
            startLocation: from,
            endLocation: to,
            polyline: '',
            hasStairs: false,
            hasSlope: false,
          }],
        });
      }

      return { legs, stations };
    },
    [],
  );

  // ルート検索実行
  const performSearch = useCallback(
    async (dest?: string) => {
      const destination = dest ?? destinationText;
      if (!destination.trim()) return;

      // リクエスト重複排除: 新しい検索IDを発行
      searchIdRef.current += 1;
      const currentSearchId = searchIdRef.current;

      setIsSearching(true);
      setSelectedRouteId(null);
      setExpandedRouteId(null);
      setErrorMessage(null);
      setMultiModalResults([]);
      setLegacyResults([]);
      setTransitWaypoints([]);

      try {
        // 経由地のあるアドレスリストを構築
        const validWaypoints = waypoints.filter((wp) => wp.text.trim());

        // ジオコーディング: 出発地、全経由地、目的地を並列実行
        // 既に座標がある場合はジオコーディングをスキップ
        const geocodePromises = [
          originCoords ? Promise.resolve(originCoords) : geocode(originText),
          ...validWaypoints.map((wp) => wp.coords ? Promise.resolve(wp.coords) : geocode(wp.text)),
          destCoords ? Promise.resolve(destCoords) : geocode(destination),
        ];
        const allCoords = await Promise.all(geocodePromises);

        // 古いリクエストの結果を無視
        if (currentSearchId !== searchIdRef.current) return;

        const oCoords = allCoords[0];
        const dCoords = allCoords[allCoords.length - 1];
        const wpCoordsList = allCoords.slice(1, -1);

        setOriginCoords(oCoords);
        setDestCoords(dCoords);

        // 経由地の座標を更新
        if (wpCoordsList.length > 0) {
          setWaypoints((prev) => {
            const validIdx: number[] = [];
            prev.forEach((wp, i) => { if (wp.text.trim()) validIdx.push(i); });
            return prev.map((wp, i) => {
              const idx = validIdx.indexOf(i);
              if (idx >= 0 && idx < wpCoordsList.length) {
                return { ...wp, coords: wpCoordsList[idx] };
              }
              return wp;
            });
          });
        }

        // 経由地がない場合: 従来のルーティングロジック
        if (validWaypoints.length === 0) {
          if (selectedMode === 'transit') {
            // Google Directions Transit API を WebView 経由で呼び出す（優先）
            // 同時に自前ルーターも走らせてフォールバックに使う
            const capturedSearchId = currentSearchId;

            // 自前ルーターの結果を先に取得（即座に返る）
            let customRouterResult: ReturnType<typeof searchTransitRoute> | null = null;
            try {
              customRouterResult = searchTransitRoute(oCoords, dCoords);
            } catch (err) {
              console.warn('[Route] 自前ルーター失敗:', err);
            }

            // Google Transit を WebView に送信
            // handleDirectionsResult で結果を受信する
            setDirectionsReq(undefined);
            requestAnimationFrame(() => {
              setDirectionsReq({
                originLat: oCoords.lat,
                originLng: oCoords.lng,
                destLat: dCoords.lat,
                destLng: dCoords.lng,
                mode: 'transit',
              });
            });

            // Google結果のタイムアウト時は自前ルーター結果にフォールバック
            setTimeout(() => {
              if (capturedSearchId !== searchIdRef.current) return;
              setIsSearching((current) => {
                if (!current) return current; // Google結果が既に届いている
                // タイムアウト: 自前ルーター結果にフォールバック
                console.warn('[Route] Google Transit タイムアウト → 自前ルーターにフォールバック');
                if (customRouterResult && customRouterResult.routes.length > 0) {
                  const stations = buildTransitStationMarkers(customRouterResult);
                  setMultiModalResults(customRouterResult.routes);
                  setIsMultiModal(true);
                  setSelectedRouteId(customRouterResult.routes[0].routeId);
                  setTransitWaypoints(stations);
                  // ポリライン強化
                  enhanceRoutesWithRealPolylines(customRouterResult.routes).then(
                    (enhanced) => {
                      if (capturedSearchId !== searchIdRef.current) return;
                      setMultiModalResults(enhanced);
                    },
                  ).catch(() => {});
                } else {
                  setErrorMessage('電車ルートが見つかりませんでした');
                }
                setDirectionsReq(undefined);
                return false;
              });
            }, 12000);
          } else {
            if (currentSearchId !== searchIdRef.current) return;
            setDirectionsReq(undefined);
            requestAnimationFrame(() => {
              setDirectionsReq({
                originLat: oCoords.lat,
                originLng: oCoords.lng,
                destLat: dCoords.lat,
                destLng: dCoords.lng,
                mode: selectedMode,
              });
            });
            setTimeout(() => {
              setIsSearching((current) => {
                if (current) {
                  console.warn('[Route] DirectionsService タイムアウト (15s)');
                  setErrorMessage('ルート検索がタイムアウトしました。もう一度お試しください。');
                  setDirectionsReq(undefined);
                  return false;
                }
                return current;
              });
            }, 15000);
          }
          return;
        }

        // ========================================
        // 経由地ありのマルチセグメントルーティング
        // ========================================

        // 地点リストを構築: [origin, wp1, wp2, ..., destination]
        const points: RoutePoint[] = [
          { address: originText, coords: oCoords, mode: selectedMode },
          ...validWaypoints.map((wp, i) => ({
            address: wp.text,
            coords: wpCoordsList[i],
            mode: wp.mode,
          })),
          { address: destination, coords: dCoords, mode: 'walking' as TransportMode }, // 最後の地点のmodeは使わない
        ];

        // 各区間の名前リスト
        const pointNames = [
          originText || '出発地',
          ...validWaypoints.map((wp, i) => wp.text || `経由地${i + 1}`),
          destination || '目的地',
        ];

        // 各区間のモード: points[i].mode → points[i] から points[i+1] への移動手段
        // Origin->WP1: selectedMode, WP1->WP2: wp1.mode, ..., lastWP->Dest: lastWP.mode
        const segmentModes: TransportMode[] = [];
        for (let i = 0; i < points.length - 1; i++) {
          segmentModes.push(points[i].mode);
        }

        // 全区間を並列でルーティング
        const allLegs: WaypointLeg[] = [];
        const allStations: TransitStationMarker[] = [];
        let legIdx = 0;

        for (let i = 0; i < points.length - 1; i++) {
          const fromPt = points[i];
          const toPt = points[i + 1];
          const mode = segmentModes[i];

          const result = await routeSegment(
            fromPt.coords,
            toPt.coords,
            mode,
            pointNames[i],
            pointNames[i + 1],
            legIdx,
          );

          // legIndex を正しく再番号付け
          for (const leg of result.legs) {
            leg.legIndex = legIdx;
            allLegs.push(leg);
            legIdx++;
          }
          allStations.push(...result.stations);
        }

        if (currentSearchId !== searchIdRef.current) return;

        // 全レッグを1つの MultiModalRoute に統合
        const totalDistance = allLegs.reduce((sum, leg) => sum + leg.distanceMeters, 0);
        const totalDuration = allLegs.reduce((sum, leg) => sum + leg.durationMinutes, 0);

        // アクセシビリティスコアを計算
        const transitLegs = allLegs.filter((l) => l.mode === 'transit');
        const transferCount = transitLegs.length > 0 ? transitLegs.length - 1 : 0;
        let accessScore = 90;
        accessScore -= transferCount * 5;
        const walkingLegs = allLegs.filter((l) => l.mode === 'walking');
        const maxWalkDist = walkingLegs.length > 0
          ? Math.max(...walkingLegs.map((l) => l.distanceMeters))
          : 0;
        if (maxWalkDist > 1000) accessScore -= 15;
        else if (maxWalkDist > 500) accessScore -= 10;
        accessScore = Math.max(accessScore, 30);

        // 警告を生成
        const warnings: string[] = [];
        for (const leg of allLegs) {
          if (leg.mode === 'walking' && leg.distanceMeters > 1000) {
            warnings.push(
              `${leg.originName}から${leg.destinationName}まで約${Math.round(leg.distanceMeters)}mの徒歩区間があります。`,
            );
          }
        }
        if (validWaypoints.length > 0) {
          warnings.push(`${validWaypoints.length}箇所の経由地を含むルートです。`);
        }

        const combinedRoute: MultiModalRoute = {
          routeId: `multi_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
          totalDistanceMeters: totalDistance,
          totalDurationMinutes: totalDuration,
          accessibilityScore: accessScore,
          legs: allLegs,
          warnings,
        };

        setMultiModalResults([combinedRoute]);
        setIsMultiModal(true);
        setSelectedRouteId(combinedRoute.routeId);
        setTransitWaypoints(allStations);
        setIsSearching(false);

        // バックグラウンドで transit レッグの実ポリライン取得 → 再描画
        const hasTransitLeg = allLegs.some((l) => l.mode === 'transit');
        if (hasTransitLeg) {
          const capturedSearchId = currentSearchId;
          enhanceRoutesWithRealPolylines([combinedRoute]).then(
            (enhanced) => {
              if (capturedSearchId !== searchIdRef.current) return;
              setMultiModalResults(enhanced);
            },
          ).catch((err) => {
            console.warn('[Route] ポリライン強化失敗（フォールバック使用）:', err);
          });
        }
      } catch (e: unknown) {
        console.error('[Route] ジオコーディング失敗:', e);
        const msg = e instanceof Error ? e.message : '場所が見つかりませんでした';
        setErrorMessage(msg);
        setIsSearching(false);
      }
    },
    [destinationText, selectedMode, originText, waypoints, routeSegment],
  );

  // ルート検索画面に遷移パラメータがあれば設定
  useEffect(() => {
    if (params.destination && params.destination !== lastParamDestRef.current) {
      lastParamDestRef.current = params.destination;
      setDestinationText(params.destination);

      // ホーム画面から現在地座標が渡されている場合はセット
      if (params.originLat && params.originLng) {
        const lat = parseFloat(params.originLat);
        const lng = parseFloat(params.originLng);
        if (!isNaN(lat) && !isNaN(lng)) {
          setOriginCoords({ lat, lng });
        }
      }

      // ホーム画面から目的地座標が渡されている場合はセット（ジオコーディングスキップ）
      if (params.destLat && params.destLng) {
        const lat = parseFloat(params.destLat);
        const lng = parseFloat(params.destLng);
        if (!isNaN(lat) && !isNaN(lng)) {
          setDestCoords({ lat, lng });
        }
      }

      performSearch(params.destination);
    }
  }, [params.destination, params.originLat, params.originLng, params.destLat, params.destLng, performSearch]);

  // モード変更時に再検索（結果が既にある場合のみ）
  const prevModeRef = useRef(selectedMode);
  useEffect(() => {
    if (prevModeRef.current !== selectedMode) {
      prevModeRef.current = selectedMode;
      if (destinationText.trim()) {
        performSearch();
      }
    }
  }, [selectedMode, destinationText, performSearch]);

  // 目的地周辺のおすすめスポットを取得（ルート検索完了後）
  useEffect(() => {
    if (!destCoords || !hasResults) {
      setRecommendedSpots([]);
      return;
    }
    let cancelled = false;
    (async () => {
      // 閲覧済みスポットIDを取得
      const seenIds = await getSeenSpotIds();

      try {
        const needs = await loadUnifiedNeeds();
        const spots = await fetchPersonalizedSpots(destCoords, needs);
        if (!cancelled && spots.length > 0) {
          const filtered = filterSeenSpots(spots, seenIds);
          // 閲覧済み除外後にスポットが残っていればそれを表示、なければ全件表示
          const toShow = filtered.length > 0 ? filtered : spots;
          setRecommendedSpots(toShow);
          markSpotsAsSeen(toShow.map((s) => s.spotId));
          return;
        }
      } catch {
        console.warn('[Route] fetchPersonalizedSpots失敗');
      }
      // フォールバック: クライアント直接YOLPで取得（ニーズに基づくキーワード）
      if (!cancelled) {
        try {
          const needs = await loadUnifiedNeeds();
          const keywords = buildSearchKeywords(needs);
          const { searchYahooLocalSpots } = await import('../../src/services/yahooLocal');
          const yolpSpots = await searchYahooLocalSpots(destCoords.lat, destCoords.lng, 1000, ...keywords);
          if (!cancelled && yolpSpots.length > 0) {
            const scored = yolpSpots.slice(0, 10).map(spot => ({
              ...spot,
              relevanceScore: 50,
              relevanceReason: spot.category === 'cafe' ? 'カフェ' : spot.category === 'restaurant' ? 'レストラン' : spot.name,
            }));
            const filtered = filterSeenSpots(scored, seenIds);
            const toShow = filtered.length > 0 ? filtered : scored;
            setRecommendedSpots(toShow);
            markSpotsAsSeen(toShow.map((s) => s.spotId));
          }
        } catch {
          console.warn('[Route] クライアントYOLPフォールバックも失敗');
        }
      }
    })();
    return () => { cancelled = true; };
  }, [destCoords?.lat, destCoords?.lng, hasResults]);

  // 検索結果のクリア
  const clearResults = useCallback(() => {
    setDestinationText('');
    setMultiModalResults([]);
    setLegacyResults([]);
    setSelectedRouteId(null);
    setExpandedRouteId(null);
    setOriginCoords(null);
    setDestCoords(null);
    setErrorMessage(null);
    setTransitWaypoints([]);
    setRecommendedSpots([]);
    setShowSpots(true);
    setWaypoints((prev) => prev.map((wp) => ({ ...wp, coords: null })));
  }, []);

  // カード展開/折りたたみ
  const toggleExpand = useCallback((routeId: string) => {
    setExpandedRouteId((prev) => (prev === routeId ? null : routeId));
    setSelectedRouteId(routeId);
  }, []);

  // ナビ開始: Google Maps アプリで経路案内を起動
  const startNavigation = useCallback((routeId: string) => {
    // 対象ルートの目的地座標を取得
    let destLat: number | undefined;
    let destLng: number | undefined;
    let originLat: number | undefined;
    let originLng: number | undefined;

    if (isMultiModal) {
      const route = multiModalResults.find((r) => r.routeId === routeId);
      if (route && route.legs.length > 0) {
        const firstLeg = route.legs[0];
        const lastLeg = route.legs[route.legs.length - 1];
        if (firstLeg.steps.length > 0) {
          originLat = firstLeg.steps[0].startLocation.lat;
          originLng = firstLeg.steps[0].startLocation.lng;
        }
        if (lastLeg.steps.length > 0) {
          const lastStep = lastLeg.steps[lastLeg.steps.length - 1];
          destLat = lastStep.endLocation.lat;
          destLng = lastStep.endLocation.lng;
        }
      }
    } else {
      const route = legacyResults.find((r) => r.routeId === routeId);
      if (route && route.steps.length > 0) {
        originLat = route.steps[0].startLocation.lat;
        originLng = route.steps[0].startLocation.lng;
        const lastStep = route.steps[route.steps.length - 1];
        destLat = lastStep.endLocation.lat;
        destLng = lastStep.endLocation.lng;
      }
    }

    if (destLat == null || destLng == null) {
      Alert.alert('エラー', 'ルート情報の取得に失敗しました');
      return;
    }

    // Google Maps アプリでナビを開始
    const modeParam = selectedMode === 'driving' ? 'd' : selectedMode === 'transit' ? 'r' : 'w';
    const originParam = originLat != null && originLng != null ? `&origin=${originLat},${originLng}` : '';
    const url = Platform.select({
      ios: `comgooglemaps://?daddr=${destLat},${destLng}${originParam}&directionsmode=${selectedMode}`,
      android: `google.navigation:q=${destLat},${destLng}&mode=${modeParam}`,
      default: `https://www.google.com/maps/dir/?api=1&destination=${destLat},${destLng}&travelmode=${selectedMode}`,
    }) as string;

    // Google Maps アプリが開けない場合はブラウザで開く
    const webUrl = `https://www.google.com/maps/dir/?api=1&destination=${destLat},${destLng}&travelmode=${selectedMode}`;

    Linking.canOpenURL(url)
      .then((supported) => {
        if (supported) {
          Linking.openURL(url);
        } else {
          Linking.openURL(webUrl);
        }
      })
      .catch(() => {
        Linking.openURL(webUrl);
      });
  }, [isMultiModal, multiModalResults, legacyResults, selectedMode]);

  // タイムラインレッグのレンダリング
  const renderLegTimeline = useCallback((legs: WaypointLeg[], totalDuration: number) => {
    return (
      <View style={styles.timelineContainer} accessibilityLabel="ルートタイムライン">
        {legs.map((leg, index) => {
          const widthPercent = totalDuration > 0
            ? Math.max(10, (leg.durationMinutes / totalDuration) * 100)
            : 100 / legs.length;

          const color = leg.transitDetails && leg.transitDetails.length > 0
            ? (leg.transitDetails[0].lineColor || MODE_COLORS[leg.mode])
            : MODE_COLORS[leg.mode];

          const isDashed = leg.mode === 'walking';
          const lineLabel = leg.transitDetails && leg.transitDetails.length > 0
            ? leg.transitDetails[0].lineName
            : null;

          return (
            <View
              key={`leg-${leg.legIndex}`}
              style={[
                styles.timelineLeg,
                { width: `${widthPercent}%` as unknown as number },
              ]}
              accessibilityLabel={`${modeLabel(leg.mode)} ${durationText(leg.durationMinutes)}${lineLabel ? ` ${lineLabel}` : ''}`}
            >
              <View
                style={[
                  styles.timelineBar,
                  {
                    backgroundColor: isDashed ? 'transparent' : color,
                    borderColor: isDashed ? color : 'transparent',
                    borderWidth: isDashed ? 2 : 0,
                    borderStyle: isDashed ? 'dashed' : 'solid',
                  },
                ]}
              >
                {lineLabel && (
                  <Text style={styles.timelineLineLabel} numberOfLines={1}>
                    {lineLabel}
                  </Text>
                )}
              </View>
              <Text style={styles.timelineLegDuration} numberOfLines={1}>
                {modeIcon(leg.mode)} {leg.durationMinutes}分
              </Text>
            </View>
          );
        })}
      </View>
    );
  }, []);

  // マルチモーダルルートカードのレンダリング
  const renderMultiModalCard = useCallback((route: MultiModalRoute, index: number) => {
    const isSelected = selectedRouteId === route.routeId;
    const isExpanded = expandedRouteId === route.routeId;
    const depTime = formatTime(route.departureTime);
    const arrTime = formatTime(route.arrivalTime);

    return (
      <TouchableOpacity
        key={route.routeId}
        style={[
          styles.routeCard,
          isSelected && {
            borderColor: ROUTE_COLORS[index % ROUTE_COLORS.length],
            backgroundColor: '#F8FAFF',
          },
        ]}
        activeOpacity={0.7}
        onPress={() => toggleExpand(route.routeId)}
        accessibilityLabel={`${scoreLabel(route.accessibilityScore)}、距離${distanceText(route.totalDistanceMeters)}、所要時間${durationText(route.totalDurationMinutes)}${route.warnings.length > 0 ? '、注意: ' + route.warnings.join('、') : ''}`}
        accessibilityState={{ selected: isSelected }}
      >
        {/* ルート色バー */}
        <View
          style={[
            styles.routeColorBar,
            { backgroundColor: ROUTE_COLORS[index % ROUTE_COLORS.length] },
          ]}
        />

        <View style={styles.routeCardContent}>
          {/* 上段: 時間・距離 */}
          <View style={styles.routeTopRow}>
            <View style={styles.durationBlock}>
              <Text style={styles.durationLarge}>
                {durationText(route.totalDurationMinutes)}
              </Text>
              <Text style={styles.distanceSmall}>
                {distanceText(route.totalDistanceMeters)}
              </Text>
            </View>

            <View style={styles.timeBlock}>
              {depTime && arrTime && (
                <Text style={styles.timeText}>
                  {depTime} → {arrTime}
                </Text>
              )}
              {route.fare && (
                <Text style={styles.fareText}>{route.fare}</Text>
              )}
            </View>
          </View>

          {/* タイムラインストリップ */}
          {renderLegTimeline(route.legs, route.totalDurationMinutes)}

          {/* アクセシビリティスコア・警告 */}
          <View style={styles.routeBottomRow}>
            <View style={styles.scoreBadgeSmall}>
              <Text style={[styles.scoreValueSmall, { color: scoreColor(route.accessibilityScore) }]}>
                {'\u267F'} {route.accessibilityScore}
              </Text>
            </View>

            {route.warnings.length > 0 && (
              <View style={styles.warningBadge}>
                <Text style={styles.warningBadgeText}>
                  {'\u26A0'} {route.warnings.length}
                </Text>
              </View>
            )}

            <View style={styles.spacer} />
            <Text style={styles.chevron}>
              {isExpanded ? '\u2304' : '\u203A'}
            </Text>
          </View>

          {/* 警告テキスト */}
          {isSelected && route.warnings.length > 0 && (
            <View style={styles.warningsContainer}>
              {route.warnings.map((warning, idx) => (
                <View key={idx} style={styles.warningRow}>
                  <Text style={styles.warningIcon}>{'\u26A0'}</Text>
                  <Text style={styles.warningText}>{warning}</Text>
                </View>
              ))}
            </View>
          )}

          {/* 展開時: レッグ詳細 */}
          {isExpanded && (
            <View style={styles.expandedContainer}>
              {route.legs.map((leg) => (
                <View key={`detail-${leg.legIndex}`} style={styles.legDetail}>
                  {/* レッグヘッダー */}
                  <View style={styles.legHeader}>
                    <View
                      style={[
                        styles.legModeTag,
                        { backgroundColor: MODE_COLORS[leg.mode] },
                      ]}
                    >
                      <Text style={styles.legModeTagText}>
                        {modeIcon(leg.mode)} {modeLabel(leg.mode)}
                      </Text>
                    </View>
                    <Text style={styles.legMetric}>
                      {distanceText(leg.distanceMeters)} / {durationText(leg.durationMinutes)}
                    </Text>
                  </View>

                  {/* 出発地→到着地 */}
                  <View style={styles.legRoute}>
                    <Text style={styles.legStopName}>{leg.originName}</Text>
                    <Text style={styles.legArrow}>{' → '}</Text>
                    <Text style={styles.legStopName}>{leg.destinationName}</Text>
                  </View>

                  {/* 乗り換え詳細 */}
                  {leg.transitDetails && leg.transitDetails.map((transit, tIdx) => (
                    <View key={`transit-${tIdx}`} style={styles.transitDetailCard}>
                      <View style={styles.transitLineRow}>
                        <View
                          style={[
                            styles.transitLineDot,
                            { backgroundColor: transit.lineColor || MODE_COLORS.transit },
                          ]}
                        />
                        <Text style={styles.transitLineName}>{transit.lineName}</Text>
                        {transit.headSign && (
                          <Text style={styles.transitHeadSign}>
                            {'  '}({transit.headSign}方面)
                          </Text>
                        )}
                      </View>

                      <View style={styles.transitStops}>
                        <Text style={styles.transitStopText}>
                          {transit.departureStop}
                          {transit.departureTime ? ` ${formatTime(transit.departureTime)}発` : ''}
                        </Text>
                        <Text style={styles.transitStopArrow}>{'  ↓  '}</Text>
                        <Text style={styles.transitNumStops}>
                          {transit.numStops}駅
                        </Text>
                        <Text style={styles.transitStopArrow}>{'  ↓  '}</Text>
                        <Text style={styles.transitStopText}>
                          {transit.arrivalStop}
                          {transit.arrivalTime ? ` ${formatTime(transit.arrivalTime)}着` : ''}
                        </Text>
                      </View>
                    </View>
                  ))}

                  {/* ステップ */}
                  {leg.steps.length > 0 && (
                    <View style={styles.legSteps}>
                      {leg.steps.map((step, sIdx) => (
                        <View key={step.stepId} style={styles.stepRow}>
                          <View
                            style={[
                              styles.stepNumber,
                              { backgroundColor: MODE_COLORS[leg.mode] },
                            ]}
                          >
                            <Text style={styles.stepNumberText}>{sIdx + 1}</Text>
                          </View>
                          <View style={styles.stepContent}>
                            <Text style={styles.stepInstruction}>
                              {step.instruction}
                            </Text>
                            <Text style={styles.stepMeta}>
                              {distanceText(step.distanceMeters)}
                              {step.hasStairs ? ' \u30FB 階段あり' : ''}
                              {step.hasSlope ? ' \u30FB 坂道あり' : ''}
                            </Text>
                          </View>
                        </View>
                      ))}
                    </View>
                  )}
                </View>
              ))}

              {/* ナビ開始ボタン */}
              <TouchableOpacity
                onPress={() => startNavigation(route.routeId)}
                style={[
                  styles.navigateButton,
                  { backgroundColor: ROUTE_COLORS[index % ROUTE_COLORS.length] },
                ]}
                accessibilityLabel="このルートでナビを開始"
              >
                <Text style={styles.navigateButtonText}>
                  このルートで出発
                </Text>
              </TouchableOpacity>
            </View>
          )}
        </View>
      </TouchableOpacity>
    );
  }, [selectedRouteId, expandedRouteId, renderLegTimeline, toggleExpand, startNavigation]);

  // レガシールートカードのレンダリング
  const renderLegacyCard = useCallback((route: RouteResult, index: number) => {
    const isSelected = selectedRouteId === route.routeId;
    const isExpanded = expandedRouteId === route.routeId;

    return (
      <TouchableOpacity
        key={route.routeId}
        style={[
          styles.routeCard,
          isSelected && {
            borderColor: ROUTE_COLORS[index % ROUTE_COLORS.length],
            backgroundColor: '#F8FAFF',
          },
        ]}
        activeOpacity={0.7}
        onPress={() => toggleExpand(route.routeId)}
        accessibilityLabel={`${scoreLabel(route.accessibilityScore)}、距離${distanceText(route.distanceMeters)}、所要時間${durationText(route.durationMinutes)}${route.warnings.length > 0 ? '、注意: ' + route.warnings.join('、') : ''}`}
        accessibilityState={{ selected: isSelected }}
      >
        <View
          style={[
            styles.routeColorBar,
            { backgroundColor: ROUTE_COLORS[index % ROUTE_COLORS.length] },
          ]}
        />

        <View style={styles.routeCardContent}>
          <View style={styles.routeTopRow}>
            <View style={styles.scoreBadge}>
              <Text style={[styles.scoreValue, { color: scoreColor(route.accessibilityScore) }]}>
                {route.accessibilityScore}
              </Text>
              <Text style={styles.scoreMax}>/ 100</Text>
            </View>

            <View style={styles.routeMetrics}>
              <View style={styles.metricItem}>
                <Text style={styles.metricIcon}>{'\u{1F6B6}'}</Text>
                <Text style={styles.metricText}>{distanceText(route.distanceMeters)}</Text>
              </View>
              <View style={styles.metricItem}>
                <Text style={styles.metricIcon}>{'\u{1F552}'}</Text>
                <Text style={styles.metricText}>{durationText(route.durationMinutes)}</Text>
              </View>
            </View>
          </View>

          {route.warnings.length > 0 && (
            <View style={styles.warningsContainer}>
              {route.warnings.map((warning, idx) => (
                <View key={idx} style={styles.warningRow}>
                  <Text style={styles.warningIcon}>{'\u26A0'}</Text>
                  <Text style={styles.warningText}>{warning}</Text>
                </View>
              ))}
            </View>
          )}

          <View style={styles.routeBottomRow}>
            <Text style={styles.stepsText}>{route.steps.length}ステップ</Text>
            {route.nearbySpots.length > 0 && (
              <View style={styles.spotsTag}>
                <Text style={styles.spotsTagText}>
                  沿道スポット {route.nearbySpots.length}件
                </Text>
              </View>
            )}
            <View style={styles.spacer} />
            <Text style={styles.chevron}>
              {isExpanded ? '\u2304' : '\u203A'}
            </Text>
          </View>

          {isExpanded && (
            <View style={styles.expandedContainer}>
              {route.steps.map((step, idx) => (
                <View key={step.stepId} style={styles.stepRow}>
                  <View
                    style={[
                      styles.stepNumber,
                      { backgroundColor: ROUTE_COLORS[index % ROUTE_COLORS.length] },
                    ]}
                  >
                    <Text style={styles.stepNumberText}>{idx + 1}</Text>
                  </View>
                  <View style={styles.stepContent}>
                    <Text style={styles.stepInstruction}>{step.instruction}</Text>
                    <Text style={styles.stepMeta}>
                      {distanceText(step.distanceMeters)}
                      {step.hasStairs ? ' \u30FB 階段あり' : ''}
                      {step.hasSlope ? ' \u30FB 坂道あり' : ''}
                    </Text>
                  </View>
                </View>
              ))}

              <TouchableOpacity
                onPress={() => startNavigation(route.routeId)}
                style={[
                  styles.navigateButton,
                  { backgroundColor: ROUTE_COLORS[index % ROUTE_COLORS.length] },
                ]}
                accessibilityLabel="このルートでナビを開始"
              >
                <Text style={styles.navigateButtonText}>このルートで出発</Text>
              </TouchableOpacity>
            </View>
          )}
        </View>
      </TouchableOpacity>
    );
  }, [selectedRouteId, expandedRouteId, toggleExpand, startNavigation]);

  return (
    <View style={styles.container}>
      {/* 地図表示エリア */}
      <View style={styles.mapContainer}>
        {hasResults && originCoords && destCoords ? (
          <MapViewWrapper
            style={styles.map}
            initialRegion={{
              latitude: (originCoords.lat + destCoords.lat) / 2,
              longitude: (originCoords.lng + destCoords.lng) / 2,
              latitudeDelta:
                Math.abs(originCoords.lat - destCoords.lat) * 1.5 + 0.005,
              longitudeDelta:
                Math.abs(originCoords.lng - destCoords.lng) * 1.5 + 0.005,
            }}
            routes={mapRoutes}
            originMarker={{
              latitude: originCoords.lat,
              longitude: originCoords.lng,
              title: originText || '出発地',
            }}
            destinationMarker={{
              latitude: destCoords.lat,
              longitude: destCoords.lng,
              title: destinationText || '目的地',
            }}
            fitToRoute
            onRouteSelect={handleRouteSelect}
            onDirectionsResult={handleDirectionsResult}
            directionsRequest={directionsReq}
            waypointMarkers={[
              // ユーザー追加の経由地マーカー
              ...waypoints
                .filter((wp) => wp.coords != null)
                .map((wp, i) => ({
                  latitude: wp.coords!.lat,
                  longitude: wp.coords!.lng,
                  title: wp.text || `経由地${i + 1}`,
                  mode: wp.mode,
                  label: wp.text || `経由地${i + 1}`,
                })),
              // 乗り換え駅マーカー
              ...transitWaypoints.map((tw) => ({
                latitude: tw.latitude,
                longitude: tw.longitude,
                title: tw.title,
                mode: 'transit' as const,
                label: tw.label || tw.title,
              })),
              // おすすめスポットマーカー
              ...(showSpots ? recommendedSpots.map((spot) => ({
                latitude: spot.location.lat,
                longitude: spot.location.lng,
                title: spot.name,
                label: spot.relevanceReason || spot.category,
                mode: 'walking' as const,
              })) : []),
            ]}
            accessibilityLabel="ルート地図"
          />
        ) : (
          <MapViewWrapper
            style={styles.map}
            showsUserLocation
            onDirectionsResult={handleDirectionsResult}
            directionsRequest={directionsReq}
            accessibilityLabel="ルート地図"
          />
        )}

        {/* マップ上のルート切替インジケータ */}
        {(isMultiModal ? multiModalResults.length : legacyResults.length) > 1 && (
          <View style={styles.routeIndicatorContainer}>
            {(isMultiModal ? multiModalResults : legacyResults).map((route, index) => (
              <TouchableOpacity
                key={route.routeId}
                style={[
                  styles.routeIndicator,
                  {
                    backgroundColor:
                      selectedRouteId === route.routeId
                        ? ROUTE_COLORS[index % ROUTE_COLORS.length]
                        : 'rgba(255,255,255,0.9)',
                    borderColor: ROUTE_COLORS[index % ROUTE_COLORS.length],
                  },
                ]}
                onPress={() => setSelectedRouteId(route.routeId)}
                accessibilityLabel={`ルート${index + 1}を選択`}
              >
                <Text
                  style={[
                    styles.routeIndicatorText,
                    {
                      color:
                        selectedRouteId === route.routeId
                          ? '#fff'
                          : ROUTE_COLORS[index % ROUTE_COLORS.length],
                    },
                  ]}
                >
                  {durationText(
                    isMultiModal
                      ? (route as MultiModalRoute).totalDurationMinutes
                      : (route as RouteResult).durationMinutes,
                  )}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
        )}
      </View>

      {/* 入力セクション */}
      <View style={styles.inputSection}>
        {/* 出発地 */}
        <View style={styles.inputRow}>
          <View style={styles.inputDot}>
            <View style={[styles.dot, { backgroundColor: '#00AA00' }]} />
          </View>
          <TextInput
            style={styles.textInput}
            placeholder="出発地"
            placeholderTextColor="#999"
            value={originText}
            onChangeText={(text) => {
              setOriginText(text);
              setOriginCoords(null);
              fetchSuggestions(text, setOriginSuggestions, setShowOriginSuggestions);
            }}
            onFocus={() => { if (originSuggestions.length > 0) setShowOriginSuggestions(true); }}
            onBlur={() => { setTimeout(() => setShowOriginSuggestions(false), 200); }}
            accessibilityLabel="出発地入力フィールド"
          />
        </View>
        {showOriginSuggestions && originSuggestions.length > 0 && (
          <View style={styles.suggestionsContainer}>
            {originSuggestions.map((s, idx) => (
              <TouchableOpacity
                key={s.place_id + idx}
                style={styles.suggestionItem}
                onPress={() => handleOriginSuggestionSelect(s)}
              >
                <Text style={styles.suggestionText} numberOfLines={1}>{s.description}</Text>
              </TouchableOpacity>
            ))}
          </View>
        )}

        {/* 経由地リスト */}
        {waypoints.map((wp, wpIndex) => (
          <View key={wp.id}>
            {/* 経由地入力 */}
            <View style={styles.inputDivider} />
            <View style={styles.inputRow}>
              <View style={styles.inputDot}>
                <View style={[styles.dot, { backgroundColor: '#FF9500' }]} />
              </View>
              <TextInput
                style={styles.textInput}
                placeholder={`経由地 ${wpIndex + 1}`}
                placeholderTextColor="#999"
                value={wp.text}
                onChangeText={(text) => updateWaypointText(wp.id, text)}
                accessibilityLabel={`経由地${wpIndex + 1}入力フィールド`}
              />
              <TouchableOpacity
                onPress={() => removeWaypoint(wp.id)}
                style={styles.clearButton}
                accessibilityLabel={`経由地${wpIndex + 1}を削除`}
                hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
              >
                <Text style={styles.clearIcon}>{'\u2715'}</Text>
              </TouchableOpacity>
            </View>

            {/* この経由地から次の地点までのモード選択 */}
            <View style={styles.segmentModeRow}>
              <View style={styles.segmentLine} />
              <View style={styles.segmentModePills}>
                {TRANSPORT_MODES.filter((tm) => ['walking', 'transit', 'driving'].includes(tm.value)).map((tm) => (
                  <TouchableOpacity
                    key={tm.value}
                    style={[
                      styles.segmentModePill,
                      wp.mode === tm.value && styles.segmentModePillActive,
                    ]}
                    onPress={() => updateWaypointMode(wp.id, tm.value)}
                    accessibilityLabel={`${wp.text || `経由地${wpIndex + 1}`}から${tm.label}で移動`}
                    accessibilityState={{ selected: wp.mode === tm.value }}
                  >
                    <Text style={styles.segmentModePillIcon}>{tm.icon}</Text>
                  </TouchableOpacity>
                ))}
              </View>
            </View>
          </View>
        ))}

        {/* 経由地追加ボタン */}
        {waypoints.length < 3 && (
          <>
            <View style={styles.inputDivider} />
            <TouchableOpacity
              style={styles.addWaypointButton}
              onPress={addWaypoint}
              accessibilityLabel="経由地を追加"
            >
              <Text style={styles.addWaypointText}>{'\uFF0B'} 経由地を追加</Text>
            </TouchableOpacity>
          </>
        )}

        {/* 目的地 */}
        <View style={styles.inputDivider} />
        <View style={styles.inputRow}>
          <View style={styles.inputDot}>
            <View style={[styles.dot, { backgroundColor: '#FF3B30' }]} />
          </View>
          <TextInput
            style={styles.textInput}
            placeholder="目的地を入力"
            placeholderTextColor="#999"
            value={destinationText}
            onChangeText={(text) => {
              setDestinationText(text);
              setDestCoords(null);
              fetchSuggestions(text, setDestSuggestions, setShowDestSuggestions);
            }}
            onFocus={() => { if (destSuggestions.length > 0) setShowDestSuggestions(true); }}
            onBlur={() => { setTimeout(() => setShowDestSuggestions(false), 200); }}
            onSubmitEditing={() => { setShowDestSuggestions(false); performSearch(); }}
            returnKeyType="search"
            accessibilityLabel="目的地入力フィールド"
          />
          {destinationText.length > 0 && (
            <TouchableOpacity
              onPress={clearResults}
              style={styles.clearButton}
              accessibilityLabel="テキストをクリア"
              hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
            >
              <Text style={styles.clearIcon}>{'\u2715'}</Text>
            </TouchableOpacity>
          )}
        </View>
        {showDestSuggestions && destSuggestions.length > 0 && (
          <View style={styles.suggestionsContainer}>
            {destSuggestions.map((s, idx) => (
              <TouchableOpacity
                key={s.place_id + idx}
                style={styles.suggestionItem}
                onPress={() => handleDestSuggestionSelect(s)}
              >
                <Text style={styles.suggestionText} numberOfLines={1}>{s.description}</Text>
              </TouchableOpacity>
            ))}
          </View>
        )}
      </View>

      {/* 移動モードセレクター */}
      <View style={styles.modeContainer} accessibilityLabel="移動手段の選択">
        {TRANSPORT_MODES.map((tm) => (
          <TouchableOpacity
            key={tm.value}
            style={[
              styles.modeButton,
              selectedMode === tm.value && styles.modeButtonActive,
            ]}
            onPress={() => {
              setSelectedMode(tm.value);
              // performSearch は次のレンダーサイクルで呼び出す
              // （selectedMode の更新を反映させるため）
            }}
            accessibilityLabel={`${tm.label}モード`}
            accessibilityState={{ selected: selectedMode === tm.value }}
          >
            <Text style={styles.modeIcon}>{tm.icon}</Text>
            <Text
              style={[
                styles.modeText,
                selectedMode === tm.value && styles.modeTextActive,
              ]}
            >
              {tm.label}
            </Text>
          </TouchableOpacity>
        ))}

        {/* 検索ボタン */}
        <TouchableOpacity
          style={[
            styles.searchButton,
            !destinationText.trim() && styles.searchButtonDisabled,
          ]}
          onPress={() => performSearch()}
          disabled={!destinationText.trim()}
          accessibilityLabel="ルートを検索"
        >
          <Text style={styles.searchButtonText}>検索</Text>
        </TouchableOpacity>
      </View>

      {/* 目的地周辺おすすめスポット */}
      {recommendedSpots.length > 0 && (
        <View>
          <View style={styles.spotHeaderRow}>
            <Text style={styles.spotSectionTitle}>あなたへのおすすめ</Text>
            <TouchableOpacity
              onPress={() => setShowSpots(!showSpots)}
              style={styles.spotToggle}
              accessibilityLabel={showSpots ? 'スポットを非表示' : 'スポットを表示'}
            >
              <Text style={styles.spotToggleText}>
                {showSpots ? '非表示' : '表示'}
              </Text>
            </TouchableOpacity>
          </View>
          {showSpots && (
            <ScrollView
              horizontal
              showsHorizontalScrollIndicator={false}
              contentContainerStyle={styles.spotScrollContent}
            >
              {recommendedSpots.map((spot) => (
                <View key={spot.spotId} style={styles.spotCard}>
                  <Text style={styles.spotCardName} numberOfLines={1}>{spot.name}</Text>
                  <Text style={styles.spotCardReason} numberOfLines={1}>
                    {spot.relevanceReason}
                  </Text>
                  <Text style={styles.spotCardDistance}>
                    {spot.distanceMeters >= 1000
                      ? `${(spot.distanceMeters / 1000).toFixed(1)}km`
                      : `${Math.round(spot.distanceMeters)}m`}
                  </Text>
                  <View style={styles.spotCardScoreRow}>
                    <View
                      style={[
                        styles.spotCardScoreBadge,
                        { backgroundColor: spot.accessibilityScore >= 80 ? '#E8F5E9' : spot.accessibilityScore >= 50 ? '#FFF3E0' : '#FFEBEE' },
                      ]}
                    >
                      <Text
                        style={[
                          styles.spotCardScore,
                          { color: spot.accessibilityScore >= 80 ? '#2E7D32' : spot.accessibilityScore >= 50 ? '#E65100' : '#C62828' },
                        ]}
                      >
                        {spot.accessibilityScore}
                      </Text>
                    </View>
                    <View style={styles.spotCardRelevanceBadge}>
                      <Text style={styles.spotCardRelevance}>
                        {spot.relevanceScore}%
                      </Text>
                    </View>
                  </View>
                </View>
              ))}
            </ScrollView>
          )}
        </View>
      )}

      {/* 結果エリア */}
      {isSearching ? (
        <View style={styles.emptyState}>
          <ActivityIndicator size="large" color="#007AFF" />
          <Text style={styles.emptyText}>ルートを検索中...</Text>
        </View>
      ) : !hasResults ? (
        <View style={styles.emptyState}>
          {errorMessage ? (
            <>
              <Text style={styles.emptyIcon}>{'\u26A0'}</Text>
              <Text style={styles.emptyText}>{errorMessage}</Text>
            </>
          ) : (
            <>
              <Text style={styles.emptyIcon}>{'\u{1F5FA}'}</Text>
              <Text style={styles.emptyText}>目的地を入力してルートを検索</Text>
              <Text style={styles.emptySubtext}>
                住所や場所名を入力できます
              </Text>
            </>
          )}
        </View>
      ) : (
        <ScrollView
          style={styles.resultsScroll}
          contentContainerStyle={styles.resultsContent}
          showsVerticalScrollIndicator={false}
        >
          {errorMessage && (
            <View style={styles.infoBanner}>
              <Text style={styles.infoBannerText}>{errorMessage}</Text>
            </View>
          )}
          {isMultiModal
            ? multiModalResults.map((route, index) => renderMultiModalCard(route, index))
            : legacyResults.map((route, index) => renderLegacyCard(route, index))}
        </ScrollView>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#F2F2F7',
  },

  // 地図
  mapContainer: {
    height: MAP_HEIGHT,
    backgroundColor: '#E8F0FE',
  },
  map: {
    flex: 1,
  },

  // マップ上のルート切替インジケータ
  routeIndicatorContainer: {
    position: 'absolute',
    bottom: 12,
    left: 12,
    flexDirection: 'row',
    gap: 8,
  },
  routeIndicator: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 16,
    borderWidth: 2,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.15,
    shadowRadius: 2,
    elevation: 3,
  },
  routeIndicatorText: {
    fontSize: 13,
    fontWeight: '700',
  },

  // 入力セクション
  inputSection: {
    backgroundColor: '#fff',
    marginHorizontal: 16,
    marginTop: -16,
    borderRadius: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 4,
    zIndex: 10,
  },
  inputRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  inputDot: {
    width: 24,
    alignItems: 'center',
  },
  dot: {
    width: 10,
    height: 10,
    borderRadius: 5,
  },
  textInput: {
    flex: 1,
    fontSize: 15,
    color: '#333',
    marginLeft: 8,
    paddingVertical: 0,
  },
  inputDivider: {
    height: 1,
    backgroundColor: '#E5E5EA',
    marginLeft: 44,
    marginRight: 12,
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

  // オートコンプリートサジェスト
  suggestionsContainer: {
    backgroundColor: '#FFF',
    borderTopWidth: 1,
    borderTopColor: '#E5E5EA',
    marginLeft: 44,
    marginRight: 12,
  },
  suggestionItem: {
    paddingVertical: 10,
    paddingHorizontal: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#E5E5EA',
  },
  suggestionText: {
    fontSize: 14,
    color: '#333',
  },

  // 経由地追加ボタン
  addWaypointButton: {
    paddingVertical: 10,
    paddingHorizontal: 44,
  },
  addWaypointText: {
    fontSize: 14,
    color: '#007AFF',
    fontWeight: '500',
  },

  // 区間モード選択
  segmentModeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingLeft: 22,
    paddingRight: 12,
    paddingVertical: 4,
  },
  segmentLine: {
    width: 2,
    height: 24,
    backgroundColor: '#E5E5EA',
    marginRight: 10,
  },
  segmentModePills: {
    flexDirection: 'row',
    gap: 4,
  },
  segmentModePill: {
    width: 32,
    height: 28,
    borderRadius: 14,
    backgroundColor: '#F2F2F7',
    alignItems: 'center',
    justifyContent: 'center',
  },
  segmentModePillActive: {
    backgroundColor: '#E3F2FD',
    borderWidth: 1.5,
    borderColor: '#4285F4',
  },
  segmentModePillIcon: {
    fontSize: 14,
  },

  // 移動モードセレクター
  modeContainer: {
    flexDirection: 'row',
    marginHorizontal: 16,
    marginTop: 10,
    backgroundColor: '#E5E5EA',
    borderRadius: 8,
    padding: 2,
    alignItems: 'center',
  },
  modeButton: {
    flex: 1,
    flexDirection: 'row',
    paddingVertical: 8,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 6,
    gap: 3,
  },
  modeButtonActive: {
    backgroundColor: '#fff',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 1,
    elevation: 1,
  },
  modeIcon: {
    fontSize: 14,
  },
  modeText: {
    fontSize: 12,
    color: '#666',
    fontWeight: '500',
  },
  modeTextActive: {
    color: '#4285F4',
    fontWeight: '600',
  },

  // 検索ボタン
  searchButton: {
    backgroundColor: '#4285F4',
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 6,
    marginLeft: 4,
  },
  searchButtonDisabled: {
    backgroundColor: '#B0B0B0',
  },
  searchButtonText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '600',
  },

  // 空状態
  emptyState: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingBottom: 40,
  },
  emptyIcon: {
    fontSize: 48,
    color: '#C7C7CC',
    marginBottom: 12,
  },
  emptyText: {
    fontSize: 15,
    color: '#8E8E93',
    marginTop: 8,
  },
  emptySubtext: {
    fontSize: 13,
    color: '#B0B0B0',
    marginTop: 4,
  },

  // 情報バナー
  infoBanner: {
    backgroundColor: '#FFF3CD',
    borderRadius: 8,
    padding: 10,
    marginBottom: 4,
  },
  infoBannerText: {
    fontSize: 13,
    color: '#856404',
    textAlign: 'center',
  },

  // 結果リスト
  resultsScroll: {
    flex: 1,
    marginTop: 8,
  },
  resultsContent: {
    paddingHorizontal: 16,
    paddingBottom: 24,
    gap: 10,
  },

  // ルートカード
  routeCard: {
    backgroundColor: '#fff',
    borderRadius: 16,
    flexDirection: 'row',
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.08,
    shadowRadius: 4,
    elevation: 2,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  routeColorBar: {
    width: 4,
  },
  routeCardContent: {
    flex: 1,
    padding: 14,
  },
  routeTopRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },

  // 所要時間ブロック（マルチモーダル用）
  durationBlock: {
    flexDirection: 'column',
  },
  durationLarge: {
    fontSize: 20,
    fontWeight: '700',
    color: '#333',
  },
  distanceSmall: {
    fontSize: 13,
    color: '#8E8E93',
    marginTop: 2,
  },

  // 時刻ブロック
  timeBlock: {
    alignItems: 'flex-end',
  },
  timeText: {
    fontSize: 14,
    color: '#333',
    fontWeight: '500',
  },
  fareText: {
    fontSize: 13,
    color: '#4285F4',
    fontWeight: '600',
    marginTop: 2,
  },

  // タイムラインストリップ
  timelineContainer: {
    flexDirection: 'row',
    marginTop: 10,
    marginBottom: 8,
    height: 36,
    gap: 2,
  },
  timelineLeg: {
    flexDirection: 'column',
    alignItems: 'center',
    minWidth: 30,
  },
  timelineBar: {
    height: 16,
    borderRadius: 4,
    width: '100%',
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
  },
  timelineLineLabel: {
    fontSize: 9,
    color: '#fff',
    fontWeight: '700',
    textAlign: 'center',
  },
  timelineLegDuration: {
    fontSize: 10,
    color: '#8E8E93',
    marginTop: 2,
  },

  // スコアバッジ（レガシー用）
  scoreBadge: {
    flexDirection: 'row',
    alignItems: 'baseline',
    gap: 4,
  },
  scoreValue: {
    fontSize: 22,
    fontWeight: '700',
  },
  scoreMax: {
    fontSize: 12,
    color: '#8E8E93',
  },

  // スコアバッジ小（マルチモーダル用）
  scoreBadgeSmall: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  scoreValueSmall: {
    fontSize: 13,
    fontWeight: '600',
  },

  // 警告バッジ
  warningBadge: {
    backgroundColor: '#FFF3CD',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 10,
    marginLeft: 8,
  },
  warningBadgeText: {
    fontSize: 12,
    color: '#856404',
    fontWeight: '500',
  },

  routeMetrics: {
    flexDirection: 'row',
    gap: 14,
  },
  metricItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  metricIcon: {
    fontSize: 14,
  },
  metricText: {
    fontSize: 14,
    color: '#666',
  },

  // 警告
  warningsContainer: {
    marginTop: 8,
    gap: 3,
  },
  warningRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  warningIcon: {
    fontSize: 12,
    color: '#FF9500',
  },
  warningText: {
    fontSize: 13,
    color: '#FF9500',
  },

  // 下部行
  routeBottomRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 4,
    gap: 4,
  },
  stepsText: {
    fontSize: 12,
    color: '#8E8E93',
  },
  spotsTag: {
    backgroundColor: 'rgba(0,122,255,0.1)',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 10,
  },
  spotsTagText: {
    fontSize: 12,
    color: '#007AFF',
  },
  spacer: {
    flex: 1,
  },
  chevron: {
    fontSize: 18,
    color: '#C7C7CC',
    fontWeight: '300',
  },

  // 展開コンテナ
  expandedContainer: {
    marginTop: 10,
    borderTopWidth: 1,
    borderTopColor: '#E5E5EA',
    paddingTop: 10,
  },

  // レッグ詳細
  legDetail: {
    marginBottom: 12,
    backgroundColor: '#FAFAFA',
    borderRadius: 10,
    padding: 10,
  },
  legHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 6,
  },
  legModeTag: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 12,
  },
  legModeTagText: {
    fontSize: 12,
    color: '#fff',
    fontWeight: '600',
  },
  legMetric: {
    fontSize: 12,
    color: '#8E8E93',
  },
  legRoute: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 6,
    flexWrap: 'wrap',
  },
  legStopName: {
    fontSize: 13,
    color: '#333',
    fontWeight: '500',
  },
  legArrow: {
    fontSize: 13,
    color: '#8E8E93',
  },

  // 乗り換え詳細
  transitDetailCard: {
    backgroundColor: '#fff',
    borderRadius: 8,
    padding: 8,
    marginBottom: 6,
    borderLeftWidth: 3,
    borderLeftColor: '#4285F4',
  },
  transitLineRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 4,
  },
  transitLineDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    marginRight: 6,
  },
  transitLineName: {
    fontSize: 14,
    fontWeight: '600',
    color: '#333',
  },
  transitHeadSign: {
    fontSize: 12,
    color: '#8E8E93',
  },
  transitStops: {
    marginLeft: 16,
  },
  transitStopText: {
    fontSize: 12,
    color: '#666',
  },
  transitStopArrow: {
    fontSize: 11,
    color: '#B0B0B0',
  },
  transitNumStops: {
    fontSize: 12,
    color: '#4285F4',
    fontWeight: '500',
    marginLeft: 4,
  },

  // レッグ内ステップ
  legSteps: {
    marginTop: 6,
    gap: 6,
  },

  // ステップ詳細
  stepRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 10,
  },
  stepNumber: {
    width: 22,
    height: 22,
    borderRadius: 11,
    alignItems: 'center',
    justifyContent: 'center',
  },
  stepNumberText: {
    color: '#fff',
    fontSize: 11,
    fontWeight: '700',
  },
  stepContent: {
    flex: 1,
  },
  stepInstruction: {
    fontSize: 13,
    color: '#333',
    fontWeight: '500',
  },
  stepMeta: {
    fontSize: 11,
    color: '#8E8E93',
    marginTop: 2,
  },

  // ナビ開始ボタン
  navigateButton: {
    marginTop: 10,
    paddingVertical: 12,
    borderRadius: 10,
    alignItems: 'center',
  },
  navigateButtonText: {
    color: '#fff',
    fontSize: 15,
    fontWeight: '700',
  },

  // おすすめスポット
  spotHeaderRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingTop: 8,
    paddingBottom: 4,
  },
  spotSectionTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: '#333',
  },
  spotToggle: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 12,
    backgroundColor: '#E8F5E9',
  },
  spotToggleText: {
    fontSize: 12,
    color: '#2E7D32',
    fontWeight: '500',
  },
  spotScrollContent: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    gap: 10,
  },
  spotCard: {
    width: 140,
    backgroundColor: '#fff',
    borderRadius: 10,
    padding: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.08,
    shadowRadius: 3,
    elevation: 2,
  },
  spotCardName: {
    fontSize: 13,
    fontWeight: '600',
    color: '#333',
    marginBottom: 2,
  },
  spotCardReason: {
    fontSize: 11,
    color: '#007AFF',
    fontWeight: '500',
    marginBottom: 4,
  },
  spotCardDistance: {
    fontSize: 11,
    color: '#999',
    marginBottom: 6,
  },
  spotCardScoreRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  spotCardScoreBadge: {
    borderRadius: 8,
    paddingHorizontal: 6,
    paddingVertical: 2,
  },
  spotCardScore: {
    fontSize: 12,
    fontWeight: '700',
  },
  spotCardRelevanceBadge: {
    borderRadius: 8,
    paddingHorizontal: 6,
    paddingVertical: 2,
    backgroundColor: '#E3F2FD',
  },
  spotCardRelevance: {
    fontSize: 11,
    fontWeight: '600',
    color: '#1565C0',
  },
});
