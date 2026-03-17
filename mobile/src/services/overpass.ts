/**
 * OpenStreetMap Overpass APIサービス
 * ルートのアクセシビリティ情報をOSMデータで補強する
 */

import type {
  LatLng,
  RouteStep,
  MultiModalRoute,
  OsmAccessibility,
  OsmBarrier,
} from '../types';

// Overpass APIから返される要素の型
interface OverpassElement {
  type: 'node' | 'way';
  id: number;
  lat?: number;
  lon?: number;
  tags?: Record<string, string>;
}

// Overpass APIレスポンスの型
interface OverpassResponse {
  elements: OverpassElement[];
}

// セッションキャッシュ（bbox文字列 → 要素配列）
const sessionCache = new Map<string, OverpassElement[]>();

/**
 * 指定された地点群を囲むバウンディングボックスを計算する
 * @param points 地点の配列
 * @param paddingMeters パディング（メートル）
 * @returns バウンディングボックス（south, west, north, east）
 */
function buildBoundingBox(
  points: LatLng[],
  paddingMeters: number
): { south: number; west: number; north: number; east: number } {
  if (points.length === 0) {
    throw new Error('バウンディングボックス計算に最低1つの地点が必要です');
  }

  let minLat = Infinity;
  let maxLat = -Infinity;
  let minLng = Infinity;
  let maxLng = -Infinity;

  for (const point of points) {
    if (point.lat < minLat) minLat = point.lat;
    if (point.lat > maxLat) maxLat = point.lat;
    if (point.lng < minLng) minLng = point.lng;
    if (point.lng > maxLng) maxLng = point.lng;
  }

  // 緯度方向: 約111,111m = 1度 → 50mあたり約0.00045度
  const latPadding = (paddingMeters / 50) * 0.00045;
  // 経度方向: 緯度に応じて補正（中間緯度を使用）
  const midLat = (minLat + maxLat) / 2;
  const lngPadding = latPadding / Math.cos((midLat * Math.PI) / 180);

  return {
    south: minLat - latPadding,
    west: minLng - lngPadding,
    north: maxLat + latPadding,
    east: maxLng + lngPadding,
  };
}

/**
 * Overpass APIにアクセシビリティ関連データを問い合わせる
 * @param bbox バウンディングボックス
 * @returns Overpass要素の配列
 */
async function queryOverpassAccessibility(bbox: {
  south: number;
  west: number;
  north: number;
  east: number;
}): Promise<OverpassElement[]> {
  const bboxStr = `${bbox.south},${bbox.west},${bbox.north},${bbox.east}`;

  // キャッシュチェック
  const cached = sessionCache.get(bboxStr);
  if (cached) {
    return cached;
  }

  // Overpass QLクエリを構築
  const query = `
[out:json][timeout:10];
(
  node["barrier"](${bboxStr});
  node["kerb"](${bboxStr});
  way["wheelchair"](${bboxStr});
  way["sidewalk"](${bboxStr});
  way["surface"](${bboxStr});
  way["width"](${bboxStr});
);
out body;
`.trim();

  const body = `data=${encodeURIComponent(query)}`;

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 10000);

  try {
    const response = await fetch('https://overpass-api.de/api/interpreter', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body,
      signal: controller.signal,
    });

    if (!response.ok) {
      console.warn(`Overpass APIエラー: ${response.status}`);
      return [];
    }

    const data = (await response.json()) as OverpassResponse;
    const elements = data.elements || [];

    // キャッシュに保存
    sessionCache.set(bboxStr, elements);

    return elements;
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      console.warn('Overpass APIタイムアウト');
    } else {
      console.warn('Overpass APIリクエスト失敗:', error);
    }
    return [];
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * 指定地点の近傍にある要素をフィルタする
 * 簡易的な緯度経度距離近似を使用
 * @param elements 要素の配列
 * @param point 基準地点
 * @param radiusMeters 半径（メートル）
 * @returns フィルタされた要素の配列
 */
function findNearbyElements(
  elements: OverpassElement[],
  point: LatLng,
  radiusMeters: number
): OverpassElement[] {
  return elements.filter((element) => {
    if (element.lat == null || element.lon == null) {
      return false;
    }

    // 緯度経度差をメートルに近似変換
    const dLat = (element.lat - point.lat) * 111111;
    const dLng =
      (element.lon - point.lng) *
      111111 *
      Math.cos((point.lat * Math.PI) / 180);
    const distanceMeters = Math.sqrt(dLat * dLat + dLng * dLng);

    return distanceMeters <= radiusMeters;
  });
}

/**
 * 近傍の要素からOSMアクセシビリティ情報を抽出する
 * @param elements 近傍の要素群
 * @returns OsmAccessibility情報
 */
function extractOsmAccessibility(
  elements: OverpassElement[]
): OsmAccessibility {
  const accessibility: OsmAccessibility = {};

  for (const element of elements) {
    const tags = element.tags;
    if (!tags) continue;

    // 車椅子アクセス情報
    if (tags.wheelchair) {
      const value = tags.wheelchair;
      if (value === 'yes' || value === 'no' || value === 'limited') {
        accessibility.wheelchairAccessible = value;
      } else {
        accessibility.wheelchairAccessible = 'unknown';
      }
    }

    // 階段の有無
    if (tags.barrier === 'steps') {
      accessibility.hasSteps = true;
    }

    // 歩道幅
    if (tags.width) {
      const width = parseFloat(tags.width);
      if (!isNaN(width)) {
        accessibility.sidewalkWidth = width;
      }
    }

    // 路面タイプ
    if (tags.surface) {
      accessibility.surfaceType = tags.surface;
    }

    // 点字ブロック
    if (tags.tactile_paving === 'yes') {
      accessibility.tactilePaving = true;
    }
  }

  return accessibility;
}

/**
 * ルート近傍のバリア情報を抽出する
 * @param elements 全要素
 * @param routePoints ルート上の地点群
 * @returns バリア情報の配列
 */
function extractOsmBarriers(
  elements: OverpassElement[],
  routePoints: LatLng[]
): OsmBarrier[] {
  const barriers: OsmBarrier[] = [];
  const processedIds = new Set<number>();

  for (const point of routePoints) {
    const nearby = findNearbyElements(elements, point, 30);

    for (const element of nearby) {
      // 同じ要素を重複して追加しない
      if (processedIds.has(element.id)) continue;

      const tags = element.tags;
      if (!tags) continue;

      const location: LatLng = {
        lat: element.lat ?? point.lat,
        lng: element.lon ?? point.lng,
      };

      // 階段バリア
      if (tags.barrier === 'steps') {
        processedIds.add(element.id);
        barriers.push({
          type: 'steps',
          location,
          description: '階段があります。迂回が必要な場合があります。',
        });
      }

      // 高い縁石バリア
      if (tags.kerb !== undefined) {
        const heightStr = tags['kerb:height'];
        if (heightStr) {
          const heightCm = parseFloat(heightStr);
          if (!isNaN(heightCm) && heightCm > 2) {
            processedIds.add(element.id);
            barriers.push({
              type: 'kerb',
              location,
              description: `縁石の高さ${heightCm}cm。車椅子やベビーカーの通行に支障がある可能性があります。`,
            });
          }
        }
      }

      // 車椅子アクセス不可
      if (tags.wheelchair === 'no' && element.type === 'way') {
        processedIds.add(element.id);
        barriers.push({
          type: 'no_wheelchair',
          location,
          description:
            '車椅子でのアクセスが不可と報告されている区間です。',
        });
      }

      // 狭い通路
      if (tags.width) {
        const width = parseFloat(tags.width);
        if (!isNaN(width) && width < 0.9) {
          processedIds.add(element.id);
          barriers.push({
            type: 'narrow_passage',
            location,
            description: `通路幅${width}m。車椅子やベビーカーの通行が困難な可能性があります。`,
          });
        }
      }
    }
  }

  return barriers;
}

/**
 * マルチモーダルルートにOSMアクセシビリティデータを付加する
 * 徒歩区間のみ処理し、鉄道・バス等の区間はスキップする
 * @param route マルチモーダルルート
 * @returns OSMデータで補強されたルート
 */
export async function enrichRouteWithOsmData(
  route: MultiModalRoute
): Promise<MultiModalRoute> {
  // 徒歩区間を抽出
  const walkingLegs = route.legs.filter((leg) => leg.mode === 'walking');

  if (walkingLegs.length === 0) {
    return route;
  }

  // 全徒歩ステップの開始・終了地点を収集
  const allPoints: LatLng[] = [];
  for (const leg of walkingLegs) {
    for (const step of leg.steps) {
      allPoints.push(step.startLocation);
      allPoints.push(step.endLocation);
    }
  }

  if (allPoints.length === 0) {
    return route;
  }

  // バウンディングボックスを計算（50mパディング）
  const bbox = buildBoundingBox(allPoints, 50);

  // Overpass APIからデータ取得
  const elements = await queryOverpassAccessibility(bbox);

  if (elements.length === 0) {
    return route;
  }

  // 各レグの各ステップにOSMアクセシビリティ情報を付加
  const enrichedLegs = route.legs.map((leg) => {
    // 徒歩区間以外はスキップ
    if (leg.mode !== 'walking') {
      return leg;
    }

    const enrichedSteps: RouteStep[] = leg.steps.map((step) => {
      const nearbyElements = findNearbyElements(
        elements,
        step.startLocation,
        50
      );
      const osmAccessibility = extractOsmAccessibility(nearbyElements);

      return {
        ...step,
        osmAccessibility,
      };
    });

    return {
      ...leg,
      steps: enrichedSteps,
    };
  });

  // ルート全体のバリア情報を抽出
  const osmBarriers = extractOsmBarriers(elements, allPoints);

  return {
    ...route,
    legs: enrichedLegs,
    osmBarriers,
  };
}
