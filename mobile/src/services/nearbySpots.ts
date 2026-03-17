// パーソナライズされた周辺スポット推薦サービス
// ユーザーのニーズに基づいてスポットをスコアリング・フィルタリングする

import { LatLng, SpotSummary } from '../types';
import { getNearbySpots, getNearbySpotsByYOLP } from './api';
import { searchYahooLocalSpots } from './yahooLocal';
import { UnifiedUserNeeds } from './userNeeds';

// スコア付きスポット
export interface ScoredSpot extends SpotSummary {
  relevanceScore: number;     // 0-100、ユーザーニーズとの関連度
  relevanceReason?: string;   // 関連理由（例: "車椅子対応トイレ"）
}

// カテゴリラベル
const CATEGORY_LABELS: Record<string, string> = {
  restroom: 'トイレ',
  rest_area: '休憩所',
  cafe: 'カフェ',
  elevator: 'エレベーター',
  parking: '駐車場',
  station: '駅',
  nursing_room: '授乳室',
  bench: 'ベンチ',
  covered: '屋根あり通路',
  ramp: 'スロープ',
  restaurant: 'レストラン',
};

/**
 * ユーザーニーズに基づいてスポットのスコアリング・関連理由を算出
 */
function scoreSpot(spot: SpotSummary, needs: UnifiedUserNeeds): ScoredSpot {
  let score = 0;
  const reasons: string[] = [];

  // ベーススコア: アクセシビリティスコアの30%
  score += spot.accessibilityScore * 0.3;

  // 移動手段に応じたスコアリング
  switch (needs.mobilityType) {
    case 'wheelchair':
      if (spot.wheelchairAccessible) {
        score += 30;
        reasons.push('車椅子対応');
      }
      if (spot.category === 'restroom') {
        score += 20;
        reasons.push('トイレ');
      }
      if (spot.category === 'elevator' || spot.category === 'ramp') {
        score += 15;
        reasons.push(CATEGORY_LABELS[spot.category] || spot.category);
      }
      break;

    case 'stroller':
      if (spot.category === 'nursing_room') {
        score += 25;
        reasons.push('授乳室');
      }
      if (spot.category === 'elevator') {
        score += 20;
        reasons.push('エレベーター');
      }
      if (spot.wheelchairAccessible) {
        score += 15;
        reasons.push('段差なし');
      }
      if (spot.category === 'restroom') {
        score += 10;
        reasons.push('トイレ');
      }
      break;

    case 'cane':
      if (spot.category === 'rest_area' || spot.category === 'bench') {
        score += 25;
        reasons.push('休憩可能');
      }
      if (spot.category === 'covered') {
        score += 15;
        reasons.push('屋根あり');
      }
      if (spot.accessibilityScore >= 80) {
        score += 10;
      }
      break;

    default:
      // walk / other: 一般的なスコアリング
      if (spot.accessibilityScore >= 80) {
        score += 10;
      }
      break;
  }

  // 同行者に応じた追加スコア
  if (needs.companions.includes('child')) {
    if (spot.category === 'nursing_room') {
      score += 15;
      if (!reasons.includes('授乳室')) reasons.push('授乳室');
    }
    if (spot.category === 'restroom') {
      score += 10;
    }
  }
  if (needs.companions.includes('elderly')) {
    if (spot.category === 'rest_area' || spot.category === 'bench') {
      score += 15;
      if (!reasons.includes('休憩可能')) reasons.push('休憩可能');
    }
  }

  // 希望条件に応じたブースト
  for (const pref of needs.preferConditions) {
    if (pref === 'restroom' && spot.category === 'restroom') {
      score += 20;
      if (!reasons.includes('トイレ')) reasons.push('トイレ');
    }
    if (pref === 'rest_area' && (spot.category === 'rest_area' || spot.category === 'bench')) {
      score += 20;
      if (!reasons.includes('休憩可能')) reasons.push('休憩可能');
    }
    if (pref === 'covered' && spot.category === 'covered') {
      score += 20;
      if (!reasons.includes('屋根あり')) reasons.push('屋根あり');
    }
  }

  // スコアを0-100に正規化
  const normalizedScore = Math.min(100, Math.max(0, Math.round(score)));

  return {
    ...spot,
    relevanceScore: normalizedScore,
    relevanceReason: reasons.length > 0
      ? reasons.join(' / ')
      : CATEGORY_LABELS[spot.category] || spot.category,
  };
}

/**
 * 目的地周辺のモックスポットを生成（API未接続時のフォールバック）
 */
function generateMockSpots(destination: LatLng, needs: UnifiedUserNeeds): SpotSummary[] {
  const { lat, lng } = destination;

  // ニーズに応じてスポットの種類を変える
  const spots: SpotSummary[] = [];
  let id = 1;

  const addSpot = (
    name: string,
    category: string,
    dLat: number,
    dLng: number,
    distance: number,
    score: number,
    wheelchair: boolean,
  ) => {
    spots.push({
      spotId: `rec_${id++}`,
      name,
      category,
      location: { lat: lat + dLat, lng: lng + dLng },
      distanceMeters: distance,
      accessibilityScore: score,
      wheelchairAccessible: wheelchair,
    });
  };

  // 共通スポット（全ユーザーに表示）
  addSpot('バリアフリートイレ', 'restroom', 0.0005, 0.0003, 60, 95, true);
  addSpot('エレベーター', 'elevator', -0.0003, 0.0006, 80, 90, true);
  addSpot('休憩ベンチ', 'bench', 0.0008, -0.0004, 100, 85, true);
  addSpot('カフェ', 'cafe', -0.0006, 0.0008, 120, 75, false);

  // 車椅子ユーザー向け
  if (needs.mobilityType === 'wheelchair') {
    addSpot('多機能トイレ', 'restroom', 0.001, 0.0005, 150, 98, true);
    addSpot('スロープ付き入口', 'ramp', -0.0008, -0.0005, 90, 92, true);
  }

  // ベビーカーユーザー向け
  if (needs.mobilityType === 'stroller' || needs.companions.includes('child')) {
    addSpot('授乳室・おむつ替え', 'nursing_room', 0.0004, -0.0007, 70, 90, true);
    addSpot('キッズスペース付きカフェ', 'cafe', 0.0012, 0.0003, 180, 82, true);
  }

  // 高齢者・杖ユーザー向け
  if (needs.mobilityType === 'cane' || needs.companions.includes('elderly')) {
    addSpot('屋根付き休憩所', 'rest_area', -0.0005, 0.001, 110, 88, true);
    addSpot('座れるベンチ広場', 'bench', 0.0007, 0.001, 130, 80, true);
  }

  // 希望条件に応じた追加
  if (needs.preferConditions.includes('restroom')) {
    addSpot('車椅子対応トイレ', 'restroom', -0.001, 0.0003, 140, 92, true);
  }
  if (needs.preferConditions.includes('rest_area')) {
    addSpot('公園休憩エリア', 'rest_area', 0.001, -0.001, 160, 78, true);
  }
  if (needs.preferConditions.includes('covered')) {
    addSpot('屋根あり通路', 'covered', -0.0004, -0.001, 100, 85, true);
  }

  return spots;
}

/**
 * Google と YOLP の結果をマージし、spotId ベースで重複を除去する
 */
function mergeSpots(googleSpots: SpotSummary[], yolpSpots: SpotSummary[]): SpotSummary[] {
  const seen = new Set<string>();
  const merged: SpotSummary[] = [];

  // Google の結果を優先的に追加
  for (const spot of googleSpots) {
    if (!seen.has(spot.spotId)) {
      seen.add(spot.spotId);
      merged.push(spot);
    }
  }

  // YOLP の結果を追加（名前が完全一致するものも重複として除外）
  const googleNames = new Set(googleSpots.map((s) => s.name));
  for (const spot of yolpSpots) {
    if (!seen.has(spot.spotId) && !googleNames.has(spot.name)) {
      seen.add(spot.spotId);
      merged.push(spot);
    }
  }

  return merged;
}

/**
 * 目的地周辺のパーソナライズされたスポットを取得
 * Google Places と Yahoo YOLP を並行取得してマージ
 * API未接続時はニーズに応じたモックデータにフォールバック
 */
export async function fetchPersonalizedSpots(
  destination: LatLng,
  needs: UnifiedUserNeeds,
  radiusMeters: number = 500,
): Promise<ScoredSpot[]> {
  // Google + バックエンドYOLP + クライアント直接YOLP を並行取得
  const [googleResult, backendYolpResult, clientYolpResult] = await Promise.allSettled([
    getNearbySpots(destination.lat, destination.lng, radiusMeters),
    getNearbySpotsByYOLP(destination.lat, destination.lng, radiusMeters),
    searchYahooLocalSpots(destination.lat, destination.lng, radiusMeters, 'カフェ', 'レストラン', 'コンビニ'),
  ]);

  const googleSpots = googleResult.status === 'fulfilled' ? googleResult.value : [];
  const backendYolpSpots = backendYolpResult.status === 'fulfilled' ? backendYolpResult.value : [];
  // バックエンドYOLPが取得できなかった場合はクライアント直接YOLPを使用
  const yolpSpots = backendYolpSpots.length > 0
    ? backendYolpSpots
    : (clientYolpResult.status === 'fulfilled' ? clientYolpResult.value : []);

  let rawSpots: SpotSummary[];
  if (googleSpots.length === 0 && yolpSpots.length === 0) {
    // 全て失敗時はモックデータにフォールバック
    rawSpots = generateMockSpots(destination, needs);
  } else {
    rawSpots = mergeSpots(googleSpots, yolpSpots);
  }

  // スコアリング
  const scored = rawSpots.map((spot) => scoreSpot(spot, needs));

  // スコア降順でソートし、上位10件を返す
  scored.sort((a, b) => b.relevanceScore - a.relevanceScore);

  return scored.slice(0, 10);
}
