// アクセシビリティ情報エンリッチメントサービス
// 高低差・OSMバリア情報を統合し、ユーザープロファイルに基づいてスコア・警告を再計算する

import { MultiModalRoute, ElevationProfile, OsmBarrier, RouteStep, SlopeWarningLevel } from '../types';
import { UnifiedUserNeeds } from './userNeeds';
import { enrichRouteWithElevation } from './elevation';
import { enrichRouteWithOsmData } from './overpass';

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
 * ルートに高低差・OSMバリア情報を付加し、アクセシビリティスコアと警告を再計算する
 */
export async function enrichRouteAccessibility(
  route: MultiModalRoute,
  needs: UnifiedUserNeeds,
): Promise<MultiModalRoute> {
  // 高低差とOSMデータを並列で取得（片方が失敗しても続行）
  const [elevationResult, osmResult] = await Promise.allSettled([
    enrichRouteWithElevation(route),
    enrichRouteWithOsmData(route),
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

  // 乗換回数をカウント（transit レグの数 - 1、ただし最低0）
  const transitLegCount = enrichedRoute.legs.filter(
    (leg) => leg.mode === 'transit',
  ).length;
  const transferCount = Math.max(0, transitLegCount - 1);

  // スコア再計算
  enrichedRoute.accessibilityScore = calculateEnrichedAccessibilityScore(
    allSteps,
    transferCount,
    needs,
    enrichedRoute.elevationProfile,
    enrichedRoute.osmBarriers,
  );

  // 警告再生成
  enrichedRoute.warnings = generateEnrichedWarnings(
    allSteps,
    needs,
    enrichedRoute.elevationProfile,
    enrichedRoute.osmBarriers,
  );

  return enrichedRoute;
}
