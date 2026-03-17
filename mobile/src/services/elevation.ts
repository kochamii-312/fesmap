/**
 * Google Elevation API サービス
 * ルートの高低差情報を取得し、勾配プロファイルを計算する
 */

import type {
  LatLng,
  RouteStep,
  MultiModalRoute,
  ElevationProfile,
  SteepSection,
  SlopeWarningLevel,
} from '../types';

const GOOGLE_MAPS_API_KEY = process.env.EXPO_PUBLIC_GOOGLE_MAPS_API_KEY ?? '';

/** Elevation APIレスポンスのキャッシュ（ポリライン部分文字列をキーに使用） */
const elevationCache = new Map<string, number[]>();

/**
 * Googleエンコードポリラインを LatLng 配列にデコードする
 * @param encoded エンコード済みポリライン文字列
 * @returns デコードされた座標配列
 */
export function decodePolyline(encoded: string): LatLng[] {
  const points: LatLng[] = [];
  let index = 0;
  let lat = 0;
  let lng = 0;

  while (index < encoded.length) {
    // 緯度のデコード
    let shift = 0;
    let result = 0;
    let byte: number;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    const dlat = result & 1 ? ~(result >> 1) : result >> 1;
    lat += dlat;

    // 経度のデコード
    shift = 0;
    result = 0;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    const dlng = result & 1 ? ~(result >> 1) : result >> 1;
    lng += dlng;

    points.push({
      lat: lat / 1e5,
      lng: lng / 1e5,
    });
  }

  return points;
}

/**
 * Google Elevation API を呼び出して標高データを取得する
 * 最大512地点まで対応
 * @param points 座標配列
 * @returns 標高値の配列（メートル）。失敗時は空配列を返す
 */
async function fetchElevations(points: LatLng[]): Promise<number[]> {
  if (points.length === 0) return [];

  // API制限: 最大512地点
  const limitedPoints = points.slice(0, 512);

  const locations = limitedPoints
    .map((p) => `${p.lat},${p.lng}`)
    .join('|');

  const url = `https://maps.googleapis.com/maps/api/elevation/json?locations=${locations}&key=${GOOGLE_MAPS_API_KEY}`;

  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 10000); // 10秒タイムアウト

    const response = await fetch(url, { signal: controller.signal });
    clearTimeout(timeoutId);

    const data = await response.json();

    if (data.status !== 'OK' || !Array.isArray(data.results)) {
      console.warn('Elevation API エラー:', data.status);
      return [];
    }

    return data.results.map(
      (r: { elevation: number }) => r.elevation
    );
  } catch (error) {
    console.warn('Elevation API リクエスト失敗:', error);
    return [];
  }
}

/**
 * ポリライン上の点を均等にサンプリングする
 * @param points 元の座標配列
 * @param maxSamples 希望サンプル数
 * @returns サンプリングされた座標配列
 */
function samplePolylinePoints(points: LatLng[], maxSamples: number): LatLng[] {
  const count = Math.min(512, Math.max(10, maxSamples));

  if (points.length <= count) {
    return [...points];
  }

  // ポリライン全体の距離を計算
  const distances: number[] = [0];
  for (let i = 1; i < points.length; i++) {
    distances.push(distances[i - 1] + haversineDistance(points[i - 1], points[i]));
  }
  const totalDistance = distances[distances.length - 1];

  if (totalDistance === 0) {
    return [points[0]];
  }

  // 均等な間隔でサンプリング
  const sampled: LatLng[] = [points[0]];
  const interval = totalDistance / (count - 1);

  for (let i = 1; i < count - 1; i++) {
    const targetDist = interval * i;

    // targetDist に最も近いセグメントを探す
    let segIdx = 0;
    for (let j = 1; j < distances.length; j++) {
      if (distances[j] >= targetDist) {
        segIdx = j - 1;
        break;
      }
    }

    // セグメント内で線形補間
    const segLen = distances[segIdx + 1] - distances[segIdx];
    const ratio = segLen > 0 ? (targetDist - distances[segIdx]) / segLen : 0;

    sampled.push({
      lat: points[segIdx].lat + (points[segIdx + 1].lat - points[segIdx].lat) * ratio,
      lng: points[segIdx].lng + (points[segIdx + 1].lng - points[segIdx].lng) * ratio,
    });
  }

  sampled.push(points[points.length - 1]);
  return sampled;
}

/**
 * 2点間のハバーサイン距離を計算する
 * @param a 地点A
 * @param b 地点B
 * @returns 距離（メートル）
 */
function haversineDistance(a: LatLng, b: LatLng): number {
  const R = 6371000; // 地球の平均半径（メートル）
  const toRad = (deg: number) => (deg * Math.PI) / 180;

  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const sinDLat = Math.sin(dLat / 2);
  const sinDLng = Math.sin(dLng / 2);

  const h =
    sinDLat * sinDLat +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * sinDLng * sinDLng;

  return 2 * R * Math.asin(Math.sqrt(h));
}

/**
 * 座標配列と標高データから勾配プロファイルを計算する
 * @param points 座標配列
 * @param elevations 各点の標高（メートル）
 * @returns 高低差プロファイル
 */
function calculateSlopeProfile(
  points: LatLng[],
  elevations: number[]
): ElevationProfile {
  let totalAscent = 0;
  let totalDescent = 0;
  let maxGradient = 0;
  const steepSections: SteepSection[] = [];

  for (let i = 1; i < points.length; i++) {
    const horizontalDist = haversineDistance(points[i - 1], points[i]);
    const elevDiff = elevations[i] - elevations[i - 1];

    // 標高差の集計
    if (elevDiff > 0) {
      totalAscent += elevDiff;
    } else {
      totalDescent += Math.abs(elevDiff);
    }

    // 勾配の計算（水平距離が十分にある場合のみ）
    if (horizontalDist > 0.5) {
      const gradient = Math.abs((elevDiff / horizontalDist) * 100);

      if (gradient > maxGradient) {
        maxGradient = gradient;
      }

      // 5%超の急勾配区間を記録
      if (gradient > 5) {
        steepSections.push({
          startLocation: points[i - 1],
          endLocation: points[i],
          gradientPercent: Math.round(gradient * 10) / 10,
          distanceMeters: Math.round(horizontalDist),
        });
      }
    }
  }

  return {
    totalAscentMeters: Math.round(totalAscent * 10) / 10,
    totalDescentMeters: Math.round(totalDescent * 10) / 10,
    maxGradientPercent: Math.round(maxGradient * 10) / 10,
    steepSections,
  };
}

/**
 * 勾配から警告レベルを分類する
 * @param gradient 勾配（%）
 * @returns 警告レベル
 */
export function classifySlopeWarning(gradient: number): SlopeWarningLevel {
  const absGradient = Math.abs(gradient);
  if (absGradient > 8) return 'dangerous';
  if (absGradient >= 5) return 'caution';
  return 'safe';
}

/**
 * ルートに高低差情報を付与する
 * 徒歩区間のみ処理し、transit/driving 区間はスキップする
 * セッションキャッシュでポリラインの重複フェッチを防止
 * @param route マルチモーダルルート
 * @returns 高低差情報が付与されたルート
 */
export async function enrichRouteWithElevation(
  route: MultiModalRoute
): Promise<MultiModalRoute> {
  const enrichedRoute = { ...route, legs: [...route.legs] };
  let allPoints: LatLng[] = [];
  let allElevations: number[] = [];

  for (let legIdx = 0; legIdx < enrichedRoute.legs.length; legIdx++) {
    const leg = enrichedRoute.legs[legIdx];

    // 徒歩区間以外はスキップ
    if (leg.mode !== 'walking') continue;

    const enrichedSteps: RouteStep[] = [];

    for (const step of leg.steps) {
      // ポリラインをデコード
      const polylinePoints = decodePolyline(step.polyline);

      if (polylinePoints.length < 2) {
        enrichedSteps.push(step);
        continue;
      }

      // サンプル数を距離から算出（約50mに1点、最低10点）
      const estimatedSamples = Math.ceil(step.distanceMeters / 50);
      const sampledPoints = samplePolylinePoints(
        polylinePoints,
        Math.max(10, estimatedSamples)
      );

      // キャッシュキー: ポリラインの先頭20文字をキーに使用
      const cacheKey = step.polyline.substring(0, 20);
      let elevations: number[];

      if (elevationCache.has(cacheKey)) {
        elevations = elevationCache.get(cacheKey)!;
      } else {
        elevations = await fetchElevations(sampledPoints);
        if (elevations.length > 0) {
          elevationCache.set(cacheKey, elevations);
        }
      }

      if (elevations.length === 0 || elevations.length !== sampledPoints.length) {
        // 標高データが取得できない場合はそのまま返す
        enrichedSteps.push(step);
        continue;
      }

      // 勾配プロファイルの計算
      const profile = calculateSlopeProfile(sampledPoints, elevations);

      // 平均勾配の計算
      const totalDist = haversineDistance(
        sampledPoints[0],
        sampledPoints[sampledPoints.length - 1]
      );
      const totalElevChange =
        elevations[elevations.length - 1] - elevations[0];
      const avgGradient =
        totalDist > 0 ? Math.abs((totalElevChange / totalDist) * 100) : 0;

      // ステップに勾配情報を付与
      enrichedSteps.push({
        ...step,
        slopeGradient: Math.round(avgGradient * 10) / 10,
        maxSlopeGradient: profile.maxGradientPercent,
        slopeWarningLevel: classifySlopeWarning(profile.maxGradientPercent),
      });

      // ルート全体のプロファイル用に蓄積
      allPoints = allPoints.concat(sampledPoints);
      allElevations = allElevations.concat(elevations);
    }

    // レッグのステップを更新
    enrichedRoute.legs[legIdx] = {
      ...leg,
      steps: enrichedSteps,
    };
  }

  // ルート全体の高低差プロファイルを計算
  if (allPoints.length >= 2 && allElevations.length >= 2) {
    enrichedRoute.elevationProfile = calculateSlopeProfile(
      allPoints,
      allElevations
    );
  }

  return enrichedRoute;
}
