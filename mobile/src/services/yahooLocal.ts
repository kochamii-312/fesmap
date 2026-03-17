// Yahoo! Open Local Platform (YOLP) ローカル検索サービス
// 周辺スポットをYahoo APIから取得し、おすすめ表示に使用する
// EXPO_PUBLIC_YOLP_APP_ID 環境変数が必要

import { SpotSummary } from '../types';

const YOLP_APP_ID = process.env.EXPO_PUBLIC_YOLP_APP_ID ?? '';
const YOLP_BASE_URL = 'https://map.yahooapis.jp/search/local/V1/localSearch';
const YOLP_TIMEOUT_MS = 10000;

// YOLPレスポンスの型定義
interface YOLPResponse {
  Feature?: YOLPFeature[];
}

interface YOLPFeature {
  Id: string;
  Name?: string;
  Geometry?: {
    Coordinates?: string; // "経度,緯度"
  };
  Category?: string[];
  Property?: {
    Address?: string;
    Tel1?: string;
    Gid?: string;
  };
}

// YOLPカテゴリ → アプリカテゴリのマッピング
function mapCategory(yolpCategories?: string[]): string {
  if (!yolpCategories || yolpCategories.length === 0) return 'other';
  const cat = yolpCategories.join(' ');
  if (cat.includes('トイレ')) return 'restroom';
  if (cat.includes('カフェ') || cat.includes('喫茶')) return 'cafe';
  if (cat.includes('レストラン') || cat.includes('食堂') || cat.includes('飲食')) return 'restaurant';
  if (cat.includes('公園') || cat.includes('庭園')) return 'park';
  if (cat.includes('駅') || cat.includes('ターミナル')) return 'station';
  if (cat.includes('駐車')) return 'parking';
  if (cat.includes('病院') || cat.includes('医院') || cat.includes('薬局')) return 'medical';
  if (cat.includes('コンビニ') || cat.includes('スーパー') || cat.includes('ショッピング')) return 'shopping';
  return 'other';
}

// 2点間の距離を計算（Haversine公式、メートル単位）
function calcDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/**
 * Yahoo YOLP ローカル検索で単一キーワードのスポットを取得（内部用）
 */
async function fetchYolpSpots(
  lat: number,
  lng: number,
  distKm: number,
  query?: string,
): Promise<SpotSummary[]> {
  const params = new URLSearchParams({
    appid: YOLP_APP_ID,
    lat: lat.toString(),
    lon: lng.toString(),
    dist: distKm.toString(),
    output: 'json',
    sort: 'dist',
    results: '10',
  });
  if (query) {
    params.set('query', query);
  }

  const url = `${YOLP_BASE_URL}?${params.toString()}`;
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), YOLP_TIMEOUT_MS);

  try {
    const res = await fetch(url, {
      method: 'GET',
      signal: controller.signal,
    });

    if (!res.ok) {
      console.error(`[Yahoo] API Error ${res.status}`);
      return [];
    }

    const data: YOLPResponse = await res.json();

    if (!data.Feature || data.Feature.length === 0) {
      return [];
    }

    const spots: SpotSummary[] = [];
    for (const feature of data.Feature) {
      if (!feature.Name || !feature.Geometry?.Coordinates) continue;

      const coords = feature.Geometry.Coordinates.split(',');
      if (coords.length < 2) continue;

      const spotLng = parseFloat(coords[0]);
      const spotLat = parseFloat(coords[1]);
      if (isNaN(spotLat) || isNaN(spotLng)) continue;

      const distance = calcDistance(lat, lng, spotLat, spotLng);
      const category = mapCategory(feature.Category);

      spots.push({
        spotId: feature.Property?.Gid ?? feature.Id,
        name: feature.Name,
        category,
        location: { lat: spotLat, lng: spotLng },
        distanceMeters: Math.round(distance),
        accessibilityScore: 50,
        wheelchairAccessible: false,
      });
    }

    return spots;
  } catch (e) {
    if (e instanceof DOMException && e.name === 'AbortError') {
      console.error('[Yahoo] タイムアウト');
    } else {
      console.error('[Yahoo] 検索エラー:', e);
    }
    return [];
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * Yahoo YOLP ローカル検索で周辺スポットを取得
 * 複数キーワードを並行検索してマージする
 * @param lat 緯度
 * @param lng 経度
 * @param radiusMeters 検索半径（メートル、デフォルト1000）
 * @param queries 検索キーワード配列（省略時: バリアフリー関連キーワード）
 */
export async function searchYahooLocalSpots(
  lat: number,
  lng: number,
  radiusMeters: number = 1000,
  ...queries: string[]
): Promise<SpotSummary[]> {
  if (!YOLP_APP_ID) {
    console.warn('[Yahoo] EXPO_PUBLIC_YOLP_APP_ID が未設定です');
    return [];
  }

  // メートル → km 変換（YOLP の dist はkm単位）
  const distKm = Math.min(radiusMeters / 1000, 50);

  // デフォルトキーワード
  const keywords = queries.length > 0 ? queries : ['カフェ', 'レストラン', 'コンビニ'];

  // 各キーワードを並行検索
  const results = await Promise.allSettled(
    keywords.map((q) => fetchYolpSpots(lat, lng, distKm, q)),
  );

  // マージして重複除去
  const seen = new Set<string>();
  const merged: SpotSummary[] = [];
  for (const result of results) {
    if (result.status !== 'fulfilled') {
      console.warn('[Yahoo] キーワード検索が失敗:', result.reason);
      continue;
    }
    for (const spot of result.value) {
      if (!seen.has(spot.spotId)) {
        seen.add(spot.spotId);
        merged.push(spot);
      }
    }
  }

  // 距離順でソート
  merged.sort((a, b) => a.distanceMeters - b.distanceMeters);

  return merged;
}
