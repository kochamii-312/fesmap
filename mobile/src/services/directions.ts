// Google Maps Directions サービス
// WebView の DirectionsService 経由でマルチモーダル交通に対応
// REST API 直接呼び出しは API 制限により使用不可のため、
// WebView 内の Google Maps JS API DirectionsService を使用する

import {
  RouteResult,
  RouteStep,
  TransportMode,
  TransitDetail,
  WaypointLeg,
  MultiModalRoute,
} from '../types';

import { DirectionsResult, requestDirections } from '../components/MapViewWrapper';

// requestDirections を再エクスポート（呼び出し元の利便性のため）
export { requestDirections };

// 階段・坂道を示すキーワード（日本語・英語）
const STAIRS_KEYWORDS = ['階段', 'stairs', 'stairway', 'steps', 'staircase'];
const SLOPE_KEYWORDS = ['坂', '坂道', 'slope', 'hill', 'steep', '急な', '上り', '下り'];

/**
 * テキスト内に階段関連のキーワードが含まれるか判定
 */
function detectStairs(text: string): boolean {
  const lower = text.toLowerCase();
  return STAIRS_KEYWORDS.some((kw) => lower.includes(kw));
}

/**
 * テキスト内に坂道関連のキーワードが含まれるか判定
 */
function detectSlope(text: string): boolean {
  const lower = text.toLowerCase();
  return SLOPE_KEYWORDS.some((kw) => lower.includes(kw));
}

/**
 * ステップの内容からアクセシビリティスコアを算出
 * 基準: 100点満点。階段・坂道が検出されるたびに減点
 */
function calculateAccessibilityScore(steps: RouteStep[], transferCount: number = 0): number {
  let score = 100;

  for (const step of steps) {
    if (step.hasStairs) {
      score -= 15; // 階段1箇所につき-15点
    }
    if (step.hasSlope) {
      score -= 10; // 坂道1箇所につき-10点
    }
  }

  // 乗り換え1回につき-8点
  score -= transferCount * 8;

  // 最低スコアは10
  return Math.max(10, score);
}

/**
 * ステップの内容から警告メッセージを生成
 */
function generateWarnings(steps: RouteStep[]): string[] {
  const warnings: string[] = [];
  const hasAnyStairs = steps.some((s) => s.hasStairs);
  const hasAnySlope = steps.some((s) => s.hasSlope);
  const stairsCount = steps.filter((s) => s.hasStairs).length;

  if (hasAnyStairs) {
    warnings.push(
      stairsCount > 1
        ? `このルートには${stairsCount}箇所の階段があります`
        : 'このルートに階段があります',
    );
  }
  if (hasAnySlope) {
    warnings.push('坂道を含むルートです');
  }

  return warnings;
}

/**
 * HTMLタグを除去してプレーンテキストにする
 */
function stripHtml(html: string): string {
  return html.replace(/<[^>]*>/g, '');
}

/**
 * Google の vehicle type をアプリ内の型にマッピング
 */
function mapVehicleType(
  googleType: string,
): TransitDetail['vehicleType'] {
  const mapping: Record<string, TransitDetail['vehicleType']> = {
    HEAVY_RAIL: 'train',
    COMMUTER_TRAIN: 'train',
    HIGH_SPEED_TRAIN: 'train',
    LONG_DISTANCE_TRAIN: 'train',
    RAIL: 'train',
    SUBWAY: 'subway',
    METRO_RAIL: 'subway',
    BUS: 'bus',
    INTERCITY_BUS: 'bus',
    TROLLEYBUS: 'bus',
    TRAM: 'tram',
    SHARE_TAXI: 'bus',
    FERRY: 'ferry',
    CABLE_CAR: 'other',
    GONDOLA_LIFT: 'other',
    FUNICULAR: 'other',
    OTHER: 'other',
  };
  return mapping[googleType] ?? 'other';
}

/**
 * DirectionsResult のステップから TransitDetail をパースする
 */
function parseTransitDetailFromStep(transitDetails: {
  line: { name: string; short_name?: string; color?: string; vehicle: { type: string } };
  departure_stop: { name: string };
  arrival_stop: { name: string };
  departure_time?: { text: string; value?: number };
  arrival_time?: { text: string; value?: number };
  num_stops: number;
  headsign?: string;
}): TransitDetail {
  return {
    lineName: transitDetails.line.name || '不明',
    lineShortName: transitDetails.line.short_name,
    lineColor: transitDetails.line.color,
    vehicleType: mapVehicleType(transitDetails.line.vehicle?.type ?? 'OTHER'),
    departureStop: transitDetails.departure_stop?.name ?? '不明',
    arrivalStop: transitDetails.arrival_stop?.name ?? '不明',
    departureTime: transitDetails.departure_time?.text,
    arrivalTime: transitDetails.arrival_time?.text,
    numStops: transitDetails.num_stops ?? 0,
    headSign: transitDetails.headsign,
  };
}

/**
 * DirectionsResult のステップを RouteStep に変換
 */
function parseStepFromDirectionsResult(
  rawStep: DirectionsResult['routes'][0]['legs'][0]['steps'][0],
  index: number,
): RouteStep {
  const instruction = stripHtml(rawStep.instruction ?? '');
  const hasStairs = detectStairs(instruction);
  const hasSlope = detectSlope(instruction);

  const step: RouteStep = {
    stepId: `step_${index + 1}`,
    instruction,
    distanceMeters: rawStep.distance?.value ?? 0,
    durationSeconds: rawStep.duration?.value ?? 0,
    startLocation: {
      lat: rawStep.start_location?.lat ?? 0,
      lng: rawStep.start_location?.lng ?? 0,
    },
    endLocation: {
      lat: rawStep.end_location?.lat ?? 0,
      lng: rawStep.end_location?.lng ?? 0,
    },
    polyline: rawStep.polyline?.points ?? '',
    hasStairs,
    hasSlope,
  };

  // transit_details がある場合はパースして付与
  if (rawStep.transit_details) {
    step.transitDetail = parseTransitDetailFromStep(rawStep.transit_details);
  }

  return step;
}

/**
 * DirectionsResult（WebView の Google Maps JS API から返される）を
 * MultiModalRoute 配列にパースする
 *
 * WebView 内の DirectionsService を経由して取得した結果を
 * アプリ内のルート表示用データに変換する
 *
 * @param result WebView から受信した DirectionsResult
 * @param mode 検索に使用した交通手段
 * @returns MultiModalRoute の配列
 */
export function parseDirectionsResult(
  result: DirectionsResult,
  mode: TransportMode,
): MultiModalRoute[] {
  if (result.status !== 'OK' || !result.routes || result.routes.length === 0) {
    return [];
  }

  const results: MultiModalRoute[] = result.routes.map((route, routeIndex) => {
    const legs: WaypointLeg[] = [];
    let totalDistance = 0;
    let totalDuration = 0;
    const allWarnings: string[] = [];
    const allSteps: RouteStep[] = [];
    let fare: string | undefined;

    // 運賃情報の取得
    if (route.fare) {
      fare = route.fare.text;
    }

    route.legs.forEach((leg, legIndex) => {
      if (mode === 'transit') {
        // 交通機関モード: 各ステップを個別の WaypointLeg に分割
        // [徒歩, 山手線, 徒歩, 中央線, 徒歩] → 5つの WaypointLeg
        const rawSteps = leg.steps ?? [];

        rawSteps.forEach((rawStep, idx) => {
          const step = parseStepFromDirectionsResult(rawStep, idx);
          allSteps.push(step);

          const stepDistance = rawStep.distance?.value ?? 0;
          const stepDuration = Math.ceil((rawStep.duration?.value ?? 0) / 60);
          totalDistance += stepDistance;
          totalDuration += stepDuration;

          const stepOrigin = {
            lat: rawStep.start_location?.lat ?? 0,
            lng: rawStep.start_location?.lng ?? 0,
          };
          const stepDest = {
            lat: rawStep.end_location?.lat ?? 0,
            lng: rawStep.end_location?.lng ?? 0,
          };

          if (rawStep.travel_mode === 'TRANSIT' && step.transitDetail) {
            // 交通機関ステップ → transit の WaypointLeg
            const waypointLeg: WaypointLeg = {
              legIndex: legs.length,
              mode: 'transit',
              origin: stepOrigin,
              destination: stepDest,
              originName: step.transitDetail.departureStop,
              destinationName: step.transitDetail.arrivalStop,
              distanceMeters: stepDistance,
              durationMinutes: stepDuration,
              steps: [step],
              transitDetails: [step.transitDetail],
            };
            legs.push(waypointLeg);
          } else {
            // 徒歩ステップ → walking の WaypointLeg
            const waypointLeg: WaypointLeg = {
              legIndex: legs.length,
              mode: 'walking',
              origin: stepOrigin,
              destination: stepDest,
              originName: step.instruction || '徒歩',
              destinationName: '徒歩',
              distanceMeters: stepDistance,
              durationMinutes: stepDuration,
              steps: [step],
            };
            legs.push(waypointLeg);
          }
        });
      } else {
        // 非交通機関モード（walking, driving, bicycling）: 従来通り1つの WaypointLeg にまとめる
        const steps: RouteStep[] = [];
        const transitDetails: TransitDetail[] = [];

        (leg.steps ?? []).forEach((rawStep, idx) => {
          const step = parseStepFromDirectionsResult(rawStep, idx);
          steps.push(step);

          if (step.transitDetail) {
            transitDetails.push(step.transitDetail);
          }
        });

        const legDistance = leg.distance?.value ?? 0;
        const legDuration = Math.ceil((leg.duration?.value ?? 0) / 60);

        totalDistance += legDistance;
        totalDuration += legDuration;
        allSteps.push(...steps);

        // BUG #4 修正: steps が空の場合は leg レベルの start/end location を使用
        const legOrigin = (leg.steps && leg.steps.length > 0)
          ? { lat: leg.steps[0].start_location?.lat ?? 0, lng: leg.steps[0].start_location?.lng ?? 0 }
          : { lat: leg.start_location?.lat ?? 0, lng: leg.start_location?.lng ?? 0 };
        const legDest = (leg.steps && leg.steps.length > 0)
          ? { lat: leg.steps[leg.steps.length - 1].end_location?.lat ?? 0, lng: leg.steps[leg.steps.length - 1].end_location?.lng ?? 0 }
          : { lat: leg.end_location?.lat ?? 0, lng: leg.end_location?.lng ?? 0 };

        const waypointLeg: WaypointLeg = {
          legIndex,
          mode,
          origin: legOrigin,
          destination: legDest,
          originName: leg.start_address ?? '',
          destinationName: leg.end_address ?? '',
          distanceMeters: legDistance,
          durationMinutes: legDuration,
          steps,
          transitDetails: transitDetails.length > 0 ? transitDetails : undefined,
        };

        legs.push(waypointLeg);
      }
    });

    // 警告の生成
    const warnings = generateWarnings(allSteps);
    allWarnings.push(...warnings);

    // 乗換回数の算出（transit モードの場合）
    let transferCount = 0;
    if (mode === 'transit') {
      const totalTransitLegs = legs.reduce(
        (sum, leg) => sum + (leg.transitDetails?.length ?? 0),
        0,
      );
      transferCount = Math.max(0, totalTransitLegs - 1);
      if (transferCount > 0) {
        allWarnings.push(`${transferCount}回の乗り換えがあります`);
      }
    }

    // アクセシビリティスコアの算出（乗換回数を考慮）
    const accessibilityScore = calculateAccessibilityScore(allSteps, transferCount);

    // 出発・到着時刻
    const firstLeg = route.legs[0];
    const lastLeg = route.legs[route.legs.length - 1];
    const departureTime = firstLeg?.departure_time?.text;
    const arrivalTime = lastLeg?.arrival_time?.text;

    return {
      routeId: `multimodal_route_${routeIndex + 1}`,
      totalDistanceMeters: totalDistance,
      totalDurationMinutes: totalDuration,
      departureTime,
      arrivalTime,
      accessibilityScore,
      legs,
      warnings: allWarnings,
      fare,
    } as MultiModalRoute;
  });

  // アクセシビリティスコアの高い順にソート
  results.sort((a, b) => b.accessibilityScore - a.accessibilityScore);

  return results;
}

/**
 * DirectionsResult を RouteResult 配列に変換する（後方互換用）
 * 主に徒歩ルート検索の結果パースに使用
 *
 * @param result WebView から受信した DirectionsResult
 * @returns RouteResult の配列
 */
export function parseWalkingDirectionsResult(
  result: DirectionsResult,
): RouteResult[] {
  const multiModalRoutes = parseDirectionsResult(result, 'walking');

  return multiModalRoutes.map((mmRoute) => {
    const allSteps = mmRoute.legs.flatMap((leg) => leg.steps);

    return {
      routeId: mmRoute.routeId,
      accessibilityScore: mmRoute.accessibilityScore,
      distanceMeters: mmRoute.totalDistanceMeters,
      durationMinutes: mmRoute.totalDurationMinutes,
      steps: allSteps,
      warnings: mmRoute.warnings,
      nearbySpots: [],
    } as RouteResult;
  });
}
