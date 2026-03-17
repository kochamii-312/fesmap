// アクセシビリティ情報エンリッチメントサービス
// 高低差・OSMバリア情報を統合し、ユーザープロファイルに基づいてスコア・警告を再計算する

import { MultiModalRoute, ElevationProfile, OsmBarrier, RouteStep, SlopeWarningLevel } from '../types';
import { UnifiedUserNeeds } from './userNeeds';
import { enrichRouteWithElevation } from './elevation';
import { enrichRouteWithOsmData } from './overpass';
import { getHokoukukanAccessibility, HokoukukanAccessibility } from './hokoukukan';
import { searchNearbyStations, StationAccessibility } from './stationBarrierFree';
import { searchAccessiblePlacesNearby } from './placesAccessibility';
import { getNearbyReports, UserReport } from './userReports';

/**
 * ユーザープロファイルと実データに基づいてアクセシビリティスコアを計算する
 * スコアは100から始まり、バリアに応じて減点される（下限10）
 */
export function calculateEnrichedAccessibilityScore(
  steps: RouteStep[],
  transferCount: number,
  needs: UnifiedUserNeeds,
  elevationProfile?: ElevationProfile,
  osmBarriers?: OsmBarrier[],
): number {
  let score = 100;

  const isWheelchair = needs.mobilityType === 'wheelchair';
  const isStroller = needs.mobilityType === 'stroller';
  const isCaneOrElderly =
    needs.mobilityType === 'cane' || needs.companions.includes('elderly');
  // walk/other はデフォルト扱い

  // ステップごとのバリアチェック
  for (const step of steps) {
    const hasStairsInStep = step.hasStairs || step.osmAccessibility?.hasSteps;
    const maxSlope = step.maxSlopeGradient ?? step.slopeGradient ?? 0;
    const wheelchairAccess = step.osmAccessibility?.wheelchairAccessible;
    const sidewalkWidth = step.osmAccessibility?.sidewalkWidth;

    if (isWheelchair) {
      if (hasStairsInStep) score -= 25;
      if (maxSlope > 8) score -= 25;
      else if (maxSlope > 5) score -= 15;
      if (wheelchairAccess === 'no') score -= 30;
      if (sidewalkWidth !== undefined && sidewalkWidth < 0.9) score -= 20;
      if (step.osmAccessibility?.kerbHeight !== undefined && step.osmAccessibility.kerbHeight > 0) {
        score -= 10;
      }
    } else if (isStroller) {
      if (hasStairsInStep) score -= 20;
      if (maxSlope > 8) score -= 20;
      else if (maxSlope > 5) score -= 10;
      if (sidewalkWidth !== undefined && sidewalkWidth < 0.9) score -= 15;
    } else if (isCaneOrElderly) {
      if (hasStairsInStep) score -= 15;
      if (maxSlope > 8) score -= 20;
      else if (maxSlope > 5) score -= 10;
    } else {
      // walk/other
      if (hasStairsInStep && needs.avoidConditions.includes('stairs')) score -= 10;
      if (maxSlope > 8 && needs.avoidConditions.includes('slope')) score -= 15;
    }
  }

  // OSMバリアからの追加減点
  if (osmBarriers) {
    for (const barrier of osmBarriers) {
      if (isWheelchair) {
        if (barrier.type === 'steps') score -= 25;
        if (barrier.type === 'no_wheelchair') score -= 30;
        if (barrier.type === 'narrow_passage') score -= 20;
        if (barrier.type === 'kerb') score -= 10;
      } else if (isStroller) {
        if (barrier.type === 'steps') score -= 20;
        if (barrier.type === 'narrow_passage') score -= 15;
      } else if (isCaneOrElderly) {
        if (barrier.type === 'steps') score -= 15;
      } else {
        if (barrier.type === 'steps' && needs.avoidConditions.includes('stairs')) score -= 10;
      }
    }
  }

  // 乗換による減点
  if (isWheelchair) {
    score -= transferCount * 10;
  } else if (isStroller || isCaneOrElderly) {
    score -= transferCount * 8;
  } else {
    score -= transferCount * 5;
  }

  // 10〜100にクランプ
  return Math.max(10, Math.min(100, score));
}

/**
 * 歩行空間ネットワークデータからの追加減点を計算する
 */
function applyHokoukukanPenalty(
  hokoData: HokoukukanAccessibility[],
  needs: UnifiedUserNeeds,
): { penalty: number; warnings: string[] } {
  let penalty = 0;
  const warnings: string[] = [];
  const isWheelchair = needs.mobilityType === 'wheelchair';
  const isStroller = needs.mobilityType === 'stroller';

  for (const data of hokoData) {
    // 段差チェック
    if (data.stepHeightCm > 2) {
      if (isWheelchair) penalty += 20;
      else if (isStroller) penalty += 15;
      else penalty += 5;
      warnings.push(`段差があります（約${data.stepHeightCm}cm）`);
    }
    // 勾配チェック
    if (data.slopePercent > 8) {
      if (isWheelchair) penalty += 20;
      else penalty += 10;
      warnings.push(`急な勾配があります（${data.slopePercent}%）`);
    } else if (data.slopePercent > 5 && isWheelchair) {
      penalty += 10;
      warnings.push(`勾配に注意（${data.slopePercent}%）`);
    }
    // 歩道幅チェック
    if (data.widthMeters < 0.9 && (isWheelchair || isStroller)) {
      penalty += 15;
      warnings.push(`歩道幅が狭い区間があります（約${data.widthMeters}m）`);
    }
    // 階段・スロープ
    if (data.isStairsOrRamp && isWheelchair) {
      penalty += 20;
      warnings.push('階段またはスロープがあります');
    }
    // エレベーターがあればボーナス
    if (data.hasElevator && isWheelchair) {
      penalty -= 5; // ボーナス
    }
  }

  return { penalty, warnings };
}

/**
 * 駅バリアフリー情報からの追加スコア調整
 */
function applyStationAccessibilityAdjustment(
  stations: StationAccessibility[],
  needs: UnifiedUserNeeds,
): { penalty: number; warnings: string[] } {
  let penalty = 0;
  const warnings: string[] = [];
  const isWheelchair = needs.mobilityType === 'wheelchair';
  const isStroller = needs.mobilityType === 'stroller';

  for (const station of stations) {
    if (isWheelchair || isStroller) {
      if (!station.hasElevator) {
        penalty += 15;
        warnings.push(`${station.stationName}にエレベーターがありません`);
      }
      if (!station.barrierFreeRoute) {
        penalty += 10;
        warnings.push(`${station.stationName}のバリアフリー経路が未確認です`);
      }
      if (station.hasElevator && station.barrierFreeRoute) {
        penalty -= 5; // バリアフリー完備ボーナス
      }
    }
    if (!station.hasAccessibleToilet && needs.preferConditions.includes('restroom')) {
      warnings.push(`${station.stationName}に多機能トイレがありません`);
    }
  }

  return { penalty, warnings };
}

/**
 * ユーザー投稿からの追加スコア調整
 */
function applyUserReportAdjustment(
  reports: UserReport[],
  needs: UnifiedUserNeeds,
): { penalty: number; warnings: string[] } {
  let penalty = 0;
  const warnings: string[] = [];
  const isWheelchair = needs.mobilityType === 'wheelchair';

  for (const report of reports) {
    if (report.type === 'barrier') {
      switch (report.category) {
        case 'steps':
        case 'steep_slope':
          penalty += isWheelchair ? 15 : 5;
          warnings.push(`ユーザー報告: ${report.description}`);
          break;
        case 'narrow_path':
        case 'no_sidewalk':
          penalty += isWheelchair ? 10 : 3;
          warnings.push(`ユーザー報告: ${report.description}`);
          break;
        case 'construction':
          penalty += 10;
          warnings.push(`工事情報: ${report.description}`);
          break;
        case 'elevator_broken':
          penalty += isWheelchair ? 20 : 5;
          warnings.push(`ユーザー報告: ${report.description}`);
          break;
      }
    } else if (report.type === 'accessible') {
      // アクセシブル報告はボーナス
      penalty -= 3;
    }
  }

  return { penalty, warnings };
}

/**
 * 実データに基づいて日本語の警告メッセージを生成する
 */
export function generateEnrichedWarnings(
  steps: RouteStep[],
  needs: UnifiedUserNeeds,
  elevationProfile?: ElevationProfile,
  osmBarriers?: OsmBarrier[],
): string[] {
  const warnings: string[] = [];

  // 急勾配区間の警告
  if (elevationProfile) {
    for (const section of elevationProfile.steepSections) {
      warnings.push(
        `急な坂道があります（勾配${section.gradientPercent}%、約${Math.round(section.distanceMeters)}m区間）`,
      );
    }

    // 累計高低差の警告
    const ascentThreshold = needs.mobilityType === 'wheelchair' ? 30 : 50;
    if (elevationProfile.totalAscentMeters > ascentThreshold) {
      warnings.push(
        `累計高低差が${Math.round(elevationProfile.totalAscentMeters)}mあります`,
      );
    }
  }

  // 段差の集計
  let stepsCount = 0;
  for (const step of steps) {
    if (step.hasStairs || step.osmAccessibility?.hasSteps) {
      stepsCount++;
    }
  }
  if (osmBarriers) {
    for (const barrier of osmBarriers) {
      if (barrier.type === 'steps') stepsCount++;
    }
  }
  if (stepsCount > 0) {
    warnings.push(`このルートに${stepsCount}箇所の段差があります`);
  }

  // 車椅子通行不可
  const hasNoWheelchair =
    steps.some((s) => s.osmAccessibility?.wheelchairAccessible === 'no') ||
    osmBarriers?.some((b) => b.type === 'no_wheelchair');
  if (hasNoWheelchair) {
    warnings.push('車椅子通行不可の区間が報告されています');
  }

  // 歩道幅が狭い
  for (const step of steps) {
    if (
      step.osmAccessibility?.sidewalkWidth !== undefined &&
      step.osmAccessibility.sidewalkWidth < 0.9
    ) {
      warnings.push(
        `歩道幅が狭い区間があります（約${step.osmAccessibility.sidewalkWidth}m）`,
      );
    }
  }
  if (osmBarriers) {
    for (const barrier of osmBarriers) {
      if (barrier.type === 'narrow_passage') {
        warnings.push(`歩道幅が狭い区間があります（${barrier.description}）`);
      }
    }
  }

  // 未舗装区間
  const hasUnpaved = steps.some(
    (s) =>
      s.osmAccessibility?.surfaceType &&
      ['unpaved', 'gravel', 'dirt', 'grass', 'sand'].includes(
        s.osmAccessibility.surfaceType,
      ),
  );
  if (hasUnpaved) {
    warnings.push('未舗装の区間があります');
  }

  return warnings;
}

/**
 * ルートに全データソースのアクセシビリティ情報を付加し、スコアと警告を再計算する
 * データソース: Google Elevation, OSM Overpass, 歩行空間ネットワーク, 駅バリアフリー,
 *              Google Places wheelchair, ユーザー投稿
 */
export async function enrichRouteAccessibility(
  route: MultiModalRoute,
  needs: UnifiedUserNeeds,
): Promise<MultiModalRoute> {
  // 全徒歩レッグの代表座標を取得（データクエリ用）
  const walkingPoints = route.legs
    .filter((leg) => leg.mode === 'walking')
    .flatMap((leg) => [leg.origin, leg.destination]);
  const transitStations = route.legs
    .filter((leg) => leg.mode === 'transit' && leg.transitDetails)
    .flatMap((leg) => leg.transitDetails!.map((td) => td.departureStop));

  const midPoint = walkingPoints.length > 0
    ? walkingPoints[Math.floor(walkingPoints.length / 2)]
    : route.legs[0]?.origin ?? { lat: 0, lng: 0 };

  // 6つのデータソースを並列で取得（全て失敗しても続行）
  const [
    elevationResult,
    osmResult,
    hokoResult,
    stationResult,
    userReportResult,
  ] = await Promise.allSettled([
    enrichRouteWithElevation(route),
    enrichRouteWithOsmData(route),
    getHokoukukanAccessibility(midPoint.lat, midPoint.lng, 500),
    searchNearbyStations(midPoint.lat, midPoint.lng, 1000),
    getNearbyReports(midPoint.lat, midPoint.lng, 500),
  ]);

  // 結果をマージ
  let enrichedRoute = { ...route };

  if (elevationResult.status === 'fulfilled') {
    enrichedRoute = { ...enrichedRoute, ...elevationResult.value };
  }
  if (osmResult.status === 'fulfilled') {
    enrichedRoute = { ...enrichedRoute, ...osmResult.value };
  }

  // 全レグからステップを収集
  const allSteps = enrichedRoute.legs.flatMap((leg) => leg.steps);

  // 乗換回数をカウント
  const transitLegCount = enrichedRoute.legs.filter(
    (leg) => leg.mode === 'transit',
  ).length;
  const transferCount = Math.max(0, transitLegCount - 1);

  // ベーススコア計算（Elevation + OSM）
  let score = calculateEnrichedAccessibilityScore(
    allSteps,
    transferCount,
    needs,
    enrichedRoute.elevationProfile,
    enrichedRoute.osmBarriers,
  );

  // ベース警告生成
  const warnings = generateEnrichedWarnings(
    allSteps,
    needs,
    enrichedRoute.elevationProfile,
    enrichedRoute.osmBarriers,
  );

  // 歩行空間ネットワークデータの適用
  if (hokoResult.status === 'fulfilled' && hokoResult.value.length > 0) {
    const hokoAdj = applyHokoukukanPenalty(hokoResult.value, needs);
    score -= hokoAdj.penalty;
    warnings.push(...hokoAdj.warnings);
  }

  // 駅バリアフリー情報の適用（transitルートのみ）
  if (stationResult.status === 'fulfilled' && stationResult.value.length > 0 && transitLegCount > 0) {
    // ルートで使用する駅名に一致するものだけ適用
    const routeStationNames = new Set(transitStations);
    const relevantStations = stationResult.value.filter(
      (s) => routeStationNames.has(s.stationName) || routeStationNames.has(s.stationName + '駅'),
    );
    if (relevantStations.length > 0) {
      const stationAdj = applyStationAccessibilityAdjustment(relevantStations, needs);
      score -= stationAdj.penalty;
      warnings.push(...stationAdj.warnings);
    }
  }

  // ユーザー投稿の適用
  if (userReportResult.status === 'fulfilled' && userReportResult.value.length > 0) {
    const reportAdj = applyUserReportAdjustment(userReportResult.value, needs);
    score -= reportAdj.penalty;
    warnings.push(...reportAdj.warnings);
  }

  // 最終スコアをクランプ
  enrichedRoute.accessibilityScore = Math.max(10, Math.min(100, score));
  // 重複警告を除去
  enrichedRoute.warnings = [...new Set(warnings)];

  return enrichedRoute;
}
