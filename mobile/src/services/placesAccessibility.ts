// Google Places API (New) 車椅子アクセシビリティ情報サービス
// 周辺施設のバリアフリー対応状況を取得する

/** 施設のアクセシビリティ情報 */
export interface PlaceAccessibility {
  placeId: string;
  name: string;
  location: { lat: number; lng: number };
  wheelchairAccessibleEntrance?: boolean;
  wheelchairAccessibleParking?: boolean;
  wheelchairAccessibleRestroom?: boolean;
  wheelchairAccessibleSeating?: boolean;
}

// Google Places API (New) ベースURL・認証キー
const PLACES_API_BASE = 'https://places.googleapis.com/v1/';
const GOOGLE_API_KEY = process.env.EXPO_PUBLIC_GOOGLE_MAPS_API_KEY ?? '';

// タイムアウト（ミリ秒）
const REQUEST_TIMEOUT_MS = 10_000;

// キャッシュ（座標グリッド0.005度単位）
const nearbyCache = new Map<string, { data: PlaceAccessibility[]; timestamp: number }>();
const CACHE_TTL_MS = 5 * 60 * 1000; // 5分

/**
 * 座標をグリッドキーに変換（0.005度単位）
 */
function toGridKey(lat: number, lng: number, types?: string[]): string {
  const gridLat = Math.round(lat / 0.005) * 0.005;
  const gridLng = Math.round(lng / 0.005) * 0.005;
  const typeKey = types ? types.sort().join(',') : 'default';
  return `${gridLat.toFixed(3)}_${gridLng.toFixed(3)}_${typeKey}`;
}

// Google Places API レスポンスの型定義（必要なフィールドのみ）
interface PlacesNearbyResponse {
  places?: PlacesResult[];
}

interface PlacesResult {
  id?: string;
  displayName?: { text?: string; languageCode?: string };
  location?: { latitude?: number; longitude?: number };
  accessibilityOptions?: {
    wheelchairAccessibleEntrance?: boolean;
    wheelchairAccessibleParking?: boolean;
    wheelchairAccessibleRestroom?: boolean;
    wheelchairAccessibleSeating?: boolean;
  };
}

/**
 * タイムアウト付きfetch
 */
async function fetchWithTimeout(
  url: string,
  options: RequestInit,
  timeoutMs: number,
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { ...options, signal: controller.signal });
    return response;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * APIレスポンスからPlaceAccessibilityを生成
 */
function parsePlaceResult(place: PlacesResult): PlaceAccessibility | null {
  const placeId = place.id;
  if (!placeId) return null;

  const name = place.displayName?.text ?? '不明';
  const lat = place.location?.latitude ?? 0;
  const lng = place.location?.longitude ?? 0;
  const options = place.accessibilityOptions;

  return {
    placeId,
    name,
    location: { lat, lng },
    wheelchairAccessibleEntrance: options?.wheelchairAccessibleEntrance,
    wheelchairAccessibleParking: options?.wheelchairAccessibleParking,
    wheelchairAccessibleRestroom: options?.wheelchairAccessibleRestroom,
    wheelchairAccessibleSeating: options?.wheelchairAccessibleSeating,
  };
}

/**
 * 指定座標周辺のアクセシブルな施設を検索
 *
 * Google Places API (New) の searchNearby を使用。
 * 結果は座標グリッド（0.005度）単位でキャッシュされる。
 *
 * @param lat - 緯度
 * @param lng - 経度
 * @param radiusMeters - 検索半径（メートル）
 * @param types - 検索対象の施設タイプ（省略時: restaurant, cafe, store）
 * @returns 周辺施設のアクセシビリティ情報配列
 */
export async function searchAccessiblePlacesNearby(
  lat: number,
  lng: number,
  radiusMeters: number,
  types?: string[],
): Promise<PlaceAccessibility[]> {
  // キャッシュチェック
  const cacheKey = toGridKey(lat, lng, types);
  const cached = nearbyCache.get(cacheKey);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL_MS) {
    return cached.data;
  }

  try {
    const url = `${PLACES_API_BASE}places:searchNearby`;
    const body = {
      includedTypes: types ?? ['restaurant', 'cafe', 'store'],
      maxResultCount: 20,
      locationRestriction: {
        circle: {
          center: { latitude: lat, longitude: lng },
          radius: radiusMeters,
        },
      },
    };

    const response = await fetchWithTimeout(
      url,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': GOOGLE_API_KEY,
          'X-Goog-FieldMask':
            'places.id,places.displayName,places.location,places.accessibilityOptions',
        },
        body: JSON.stringify(body),
      },
      REQUEST_TIMEOUT_MS,
    );

    if (!response.ok) {
      console.warn(`Google Places API エラー: ${response.status}`);
      return [];
    }

    const data: PlacesNearbyResponse = await response.json();
    const places = data.places ?? [];

    const results: PlaceAccessibility[] = [];
    for (const place of places) {
      const parsed = parsePlaceResult(place);
      if (parsed) {
        results.push(parsed);
      }
    }

    // キャッシュに保存
    nearbyCache.set(cacheKey, { data: results, timestamp: Date.now() });
    return results;
  } catch (error) {
    console.warn('Google Places API 周辺検索失敗:', error);
    return [];
  }
}

/**
 * 特定の施設のアクセシビリティ情報を取得
 *
 * @param placeId - Google Place ID
 * @returns 施設のアクセシビリティ情報、取得失敗時はnull
 */
export async function getPlaceAccessibility(
  placeId: string,
): Promise<PlaceAccessibility | null> {
  try {
    const url = `${PLACES_API_BASE}places/${placeId}`;

    const response = await fetchWithTimeout(
      url,
      {
        method: 'GET',
        headers: {
          'X-Goog-Api-Key': GOOGLE_API_KEY,
          'X-Goog-FieldMask': 'id,displayName,location,accessibilityOptions',
        },
      },
      REQUEST_TIMEOUT_MS,
    );

    if (!response.ok) {
      console.warn(`Google Places API 詳細取得エラー: ${response.status}`);
      return null;
    }

    const data: PlacesResult = await response.json();
    return parsePlaceResult(data);
  } catch (error) {
    console.warn('Google Places API 詳細取得失敗:', error);
    return null;
  }
}
