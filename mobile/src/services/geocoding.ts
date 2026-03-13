// ジオコーディングサービス
// バックエンドAPI経由でGoogle Maps Geocoding APIを呼び出す
// バックエンド障害時はNominatim（OpenStreetMap）をフォールバックとして使用
// （APIキーのクライアント露出を防止）

import { LatLng } from '../types';
import { geocodeAddress, reverseGeocodeLocation } from './api';
import * as Location from 'expo-location';

// Nominatim APIのベースURL（フォールバック用、APIキー不要）
const NOMINATIM_BASE_URL = 'https://nominatim.openstreetmap.org';

// Nominatimのタイムアウト（ミリ秒）
const NOMINATIM_TIMEOUT_MS = 10000;

// 既知の地名のキャッシュ（APIコール削減 + オフラインフォールバック）
const KNOWN_PLACES: Record<string, LatLng> = {
  // 東京主要駅
  '東京駅': { lat: 35.6812, lng: 139.7671 },
  '新宿駅': { lat: 35.6896, lng: 139.7006 },
  '渋谷駅': { lat: 35.6580, lng: 139.7016 },
  '池袋駅': { lat: 35.7295, lng: 139.7109 },
  '品川駅': { lat: 35.6284, lng: 139.7387 },
  '上野駅': { lat: 35.7141, lng: 139.7774 },
  '秋葉原駅': { lat: 35.6984, lng: 139.7731 },
  '有楽町駅': { lat: 35.6748, lng: 139.7631 },
  '六本木駅': { lat: 35.6632, lng: 139.7313 },
  '銀座駅': { lat: 35.6717, lng: 139.7647 },
  '表参道駅': { lat: 35.6652, lng: 139.7123 },
  '中目黒駅': { lat: 35.6441, lng: 139.6991 },
  '恵比寿駅': { lat: 35.6467, lng: 139.7100 },
  '目黒駅': { lat: 35.6337, lng: 139.7158 },
  '大崎駅': { lat: 35.6197, lng: 139.7283 },
  '浜松町駅': { lat: 35.6555, lng: 139.7571 },
  '田町駅': { lat: 35.6458, lng: 139.7476 },
  '新橋駅': { lat: 35.6660, lng: 139.7583 },
  '神田駅': { lat: 35.6918, lng: 139.7709 },
  '御茶ノ水駅': { lat: 35.6998, lng: 139.7652 },
  '飯田橋駅': { lat: 35.7022, lng: 139.7452 },
  '四ツ谷駅': { lat: 35.6862, lng: 139.7302 },
  '市ヶ谷駅': { lat: 35.6919, lng: 139.7359 },
  '高田馬場駅': { lat: 35.7128, lng: 139.7038 },
  '代々木駅': { lat: 35.6833, lng: 139.7020 },
  '原宿駅': { lat: 35.6702, lng: 139.7027 },
  // 川崎・横浜エリア
  '溝の口駅': { lat: 35.6006, lng: 139.6107 },
  '武蔵溝ノ口駅': { lat: 35.6006, lng: 139.6107 },
  '川崎駅': { lat: 35.5313, lng: 139.7020 },
  '武蔵小杉駅': { lat: 35.5762, lng: 139.6596 },
  '横浜駅': { lat: 35.4661, lng: 139.6226 },
  '桜木町駅': { lat: 35.4510, lng: 139.6310 },
  '関内駅': { lat: 35.4437, lng: 139.6368 },
  '中華街駅': { lat: 35.4422, lng: 139.6454 },
  // 観光地
  '東京タワー': { lat: 35.6586, lng: 139.7454 },
  '東京スカイツリー': { lat: 35.7101, lng: 139.8107 },
  '浅草寺': { lat: 35.7148, lng: 139.7967 },
  '明治神宮': { lat: 35.6764, lng: 139.6993 },
  '皇居': { lat: 35.6852, lng: 139.7528 },
  '上野公園': { lat: 35.7146, lng: 139.7734 },
  'お台場': { lat: 35.6268, lng: 139.7744 },
  // 空港
  '羽田空港': { lat: 35.5494, lng: 139.7798 },
  '成田空港': { lat: 35.7720, lng: 140.3929 },
  // デフォルト
  '現在地': { lat: 35.6812, lng: 139.7671 }, // デフォルト: 東京駅
};

// ジオコーディング結果のランタイムキャッシュ（セッション中のみ保持）
const geocodeCache = new Map<string, LatLng>();

/**
 * Nominatim（OpenStreetMap）を使ったフォールバックジオコーディング
 * バックエンドAPIが利用不可の場合に使用（APIキー不要）
 * @param placeName 変換したい地名
 * @returns 緯度・経度（見つからない場合はnull）
 */
async function geocodeWithNominatim(placeName: string): Promise<LatLng | null> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), NOMINATIM_TIMEOUT_MS);

  try {
    // 日本の地名検索に限定して精度を向上
    const params = new URLSearchParams({
      q: placeName,
      format: 'json',
      limit: '1',
      countrycodes: 'jp',
      'accept-language': 'ja',
    });
    const url = `${NOMINATIM_BASE_URL}/search?${params.toString()}`;

    console.log('[Geocode] Nominatimフォールバック:', placeName);
    const res = await fetch(url, {
      headers: {
        'User-Agent': 'AccessRoute-App/1.0',
      },
      signal: controller.signal,
    });

    if (!res.ok) {
      console.warn('[Geocode] Nominatim HTTP Error:', res.status);
      return null;
    }

    const data = await res.json();
    if (!Array.isArray(data) || data.length === 0) {
      console.warn('[Geocode] Nominatim: 結果なし:', placeName);
      return null;
    }

    const result = data[0];
    const lat = parseFloat(result.lat);
    const lng = parseFloat(result.lon);

    if (isNaN(lat) || isNaN(lng)) {
      return null;
    }

    console.log(`[Geocode] Nominatim成功: ${placeName} -> ${lat},${lng}`);
    return { lat, lng };
  } catch (e: unknown) {
    if (e instanceof DOMException && e.name === 'AbortError') {
      console.warn('[Geocode] Nominatimタイムアウト');
    } else {
      console.warn('[Geocode] Nominatimエラー:', e);
    }
    return null;
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * Nominatim（OpenStreetMap）を使ったフォールバック逆ジオコーディング
 * @param lat 緯度
 * @param lng 経度
 * @returns 住所文字列（見つからない場合はnull）
 */
async function reverseGeocodeWithNominatim(lat: number, lng: number): Promise<string | null> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), NOMINATIM_TIMEOUT_MS);

  try {
    const params = new URLSearchParams({
      lat: lat.toString(),
      lon: lng.toString(),
      format: 'json',
      'accept-language': 'ja',
    });
    const url = `${NOMINATIM_BASE_URL}/reverse?${params.toString()}`;

    console.log('[ReverseGeocode] Nominatimフォールバック');
    const res = await fetch(url, {
      headers: {
        'User-Agent': 'AccessRoute-App/1.0',
      },
      signal: controller.signal,
    });

    if (!res.ok) {
      return null;
    }

    const data = await res.json();
    return data.display_name ?? null;
  } catch {
    return null;
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * 地名を緯度・経度に変換する
 * 1. 既知の地名キャッシュを確認
 * 2. ランタイムキャッシュを確認
 * 3. バックエンドAPI経由でGoogle Maps Geocoding APIを使用
 * 4. バックエンド失敗時はNominatim（OpenStreetMap）でフォールバック
 * @param placeName 変換したい地名
 * @returns 緯度・経度
 */
export async function geocode(placeName: string): Promise<LatLng> {
  const trimmed = placeName.trim();

  // 「現在地」の場合はGPSから実際の位置を取得
  if (trimmed === '現在地') {
    try {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status === 'granted') {
        const location = await Location.getCurrentPositionAsync({
          accuracy: Location.Accuracy.Balanced,
        });
        return { lat: location.coords.latitude, lng: location.coords.longitude };
      }
    } catch {
      // GPS取得失敗時はデフォルト値（東京駅）にフォールバック
    }
    return KNOWN_PLACES['現在地'];
  }

  // 既知の地名はキャッシュから返す
  if (KNOWN_PLACES[trimmed]) {
    return KNOWN_PLACES[trimmed];
  }

  // ランタイムキャッシュを確認
  const cached = geocodeCache.get(trimmed);
  if (cached) {
    return cached;
  }

  // 座標形式（"35.6812,139.7671"）の場合はそのままパース
  const coordMatch = trimmed.match(/^(-?\d+\.?\d*)\s*,\s*(-?\d+\.?\d*)$/);
  if (coordMatch) {
    const lat = parseFloat(coordMatch[1]);
    const lng = parseFloat(coordMatch[2]);
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      throw new Error(`無効な座標です: lat=${lat}, lng=${lng}`);
    }
    return { lat, lng };
  }

  // バックエンドAPI経由でジオコーディングを試行
  try {
    const location = await geocodeAddress(trimmed);
    if (location && typeof location.lat === 'number' && typeof location.lng === 'number') {
      // 成功結果をランタイムキャッシュに保存
      geocodeCache.set(trimmed, location);
      return location;
    }
  } catch (error) {
    console.warn('[Geocode] バックエンドAPI失敗、Nominatimフォールバックを試行:', error);
  }

  // フォールバック: Nominatim（OpenStreetMap）で検索
  const nominatimResult = await geocodeWithNominatim(trimmed);
  if (nominatimResult) {
    // 成功結果をランタイムキャッシュに保存
    geocodeCache.set(trimmed, nominatimResult);
    return nominatimResult;
  }

  // 全て失敗した場合、駅名の部分一致で検索を試みる
  const partialMatch = findPartialMatch(trimmed);
  if (partialMatch) {
    console.log(`[Geocode] 部分一致ヒット: "${trimmed}" -> "${partialMatch.name}"`);
    return partialMatch.location;
  }

  throw new Error(`場所が見つかりません: ${trimmed}`);
}

/**
 * 既知の地名から部分一致で検索する
 * 「溝の口」->「溝の口駅」、「東京タワー付近」->「東京タワー」など
 */
function findPartialMatch(query: string): { name: string; location: LatLng } | null {
  // 入力が既知の地名を含むか
  for (const [name, location] of Object.entries(KNOWN_PLACES)) {
    if (query.includes(name) || name.includes(query)) {
      return { name, location };
    }
  }
  // 「駅」を付けて再検索
  if (!query.endsWith('駅')) {
    const withStation = query + '駅';
    if (KNOWN_PLACES[withStation]) {
      return { name: withStation, location: KNOWN_PLACES[withStation] };
    }
  }
  return null;
}

/**
 * 緯度・経度を住所に変換する（逆ジオコーディング）
 * バックエンドAPI経由でGoogle Maps Geocoding APIを使用
 * 失敗時はNominatimでフォールバック
 * @param location 緯度・経度
 * @returns 住所文字列
 */
export async function reverseGeocode(location: LatLng): Promise<string> {
  // バックエンドAPIを試行
  try {
    const address = await reverseGeocodeLocation(location.lat, location.lng);
    if (address) {
      return address;
    }
  } catch (error) {
    console.warn('[reverseGeocode] バックエンドAPI失敗:', error);
  }

  // フォールバック: Nominatim
  try {
    const address = await reverseGeocodeWithNominatim(location.lat, location.lng);
    if (address) {
      return address;
    }
  } catch (error) {
    console.warn('[reverseGeocode] Nominatimフォールバック失敗:', error);
  }

  // 全て失敗した場合は座標を返す
  return `${location.lat.toFixed(4)}, ${location.lng.toFixed(4)}`;
}
