// ユーザーニーズ統合サービス
// プロファイル設定（AsyncStorage）とチャットで抽出されたニーズを統合して返す

import AsyncStorage from '@react-native-async-storage/async-storage';
import {
  MobilityType,
  Companion,
  AvoidCondition,
  PreferCondition,
} from '../types';
import { STORAGE_KEYS } from '../constants/storageKeys';

// 統合されたユーザーニーズ
export interface UnifiedUserNeeds {
  mobilityType: MobilityType;
  companions: Companion[];
  maxDistanceMeters: number;
  avoidConditions: AvoidCondition[];
  preferConditions: PreferCondition[];
  destination?: string;
}

const VALID_MOBILITY_TYPES: MobilityType[] = ['wheelchair', 'stroller', 'cane', 'walk', 'other'];
const VALID_COMPANIONS: Companion[] = ['child', 'elderly', 'disability'];
const VALID_AVOID: AvoidCondition[] = ['stairs', 'slope', 'crowd', 'dark'];
const VALID_PREFER: PreferCondition[] = ['restroom', 'rest_area', 'covered'];

/**
 * プロファイルとチャットニーズを統合して返す
 * チャットニーズは直近の会話から抽出された即時的なニーズで、プロファイルより優先される
 */
export async function loadUnifiedNeeds(): Promise<UnifiedUserNeeds> {
  // プロファイル読み込み
  const [rawMobility, rawCompanions, rawDistance, rawAvoid, rawPrefer, rawChat] =
    await Promise.all([
      AsyncStorage.getItem(STORAGE_KEYS.mobilityType),
      AsyncStorage.getItem(STORAGE_KEYS.companions),
      AsyncStorage.getItem(STORAGE_KEYS.maxDistance),
      AsyncStorage.getItem(STORAGE_KEYS.avoidConditions),
      AsyncStorage.getItem(STORAGE_KEYS.preferConditions),
      AsyncStorage.getItem(STORAGE_KEYS.chatExtractedNeeds),
    ]);

  // プロファイル値のパース
  const profileMobility: MobilityType =
    rawMobility && VALID_MOBILITY_TYPES.includes(rawMobility as MobilityType)
      ? (rawMobility as MobilityType)
      : 'walk';

  const profileCompanions: Companion[] = rawCompanions
    ? (JSON.parse(rawCompanions) as Companion[]).filter((c) => VALID_COMPANIONS.includes(c))
    : [];

  const profileDistance = rawDistance ? Number(rawDistance) : 1000;

  const profileAvoid: AvoidCondition[] = rawAvoid
    ? (JSON.parse(rawAvoid) as AvoidCondition[]).filter((c) => VALID_AVOID.includes(c))
    : [];

  const profilePrefer: PreferCondition[] = rawPrefer
    ? (JSON.parse(rawPrefer) as PreferCondition[]).filter((c) => VALID_PREFER.includes(c))
    : [];

  // チャットニーズのパース
  let chatNeeds: Record<string, unknown> = {};
  if (rawChat) {
    try {
      chatNeeds = JSON.parse(rawChat);
    } catch {
      // パース失敗時は無視
    }
  }

  // 統合: チャットニーズを優先、プロファイルにフォールバック
  const chatMobility = chatNeeds.mobilityType as string | undefined;
  const mobilityType: MobilityType =
    chatMobility && VALID_MOBILITY_TYPES.includes(chatMobility as MobilityType)
      ? (chatMobility as MobilityType)
      : profileMobility;

  // 同行者: 両方をユニオン
  const chatCompanions = Array.isArray(chatNeeds.companions)
    ? (chatNeeds.companions as string[]).filter((c) => VALID_COMPANIONS.includes(c as Companion)) as Companion[]
    : [];
  const companions = [...new Set([...profileCompanions, ...chatCompanions])];

  // 回避条件: 両方をユニオン
  const chatAvoid = Array.isArray(chatNeeds.avoidConditions)
    ? (chatNeeds.avoidConditions as string[]).filter((c) => VALID_AVOID.includes(c as AvoidCondition)) as AvoidCondition[]
    : [];
  const avoidConditions = [...new Set([...profileAvoid, ...chatAvoid])];

  // 希望条件: 両方をユニオン
  const chatPrefer = Array.isArray(chatNeeds.preferConditions)
    ? (chatNeeds.preferConditions as string[]).filter((c) => VALID_PREFER.includes(c as PreferCondition)) as PreferCondition[]
    : [];
  const preferConditions = [...new Set([...profilePrefer, ...chatPrefer])];

  // 目的地（チャットのみ）
  const destination = typeof chatNeeds.destination === 'string' ? chatNeeds.destination : undefined;

  return {
    mobilityType,
    companions,
    maxDistanceMeters: profileDistance,
    avoidConditions,
    preferConditions,
    destination,
  };
}

/**
 * チャットから抽出されたニーズをAsyncStorageに保存
 */
export async function saveChatNeeds(needs: Record<string, unknown>): Promise<void> {
  // 既存のニーズとマージ（新しい情報で上書き）
  const existing = await AsyncStorage.getItem(STORAGE_KEYS.chatExtractedNeeds);
  let merged: Record<string, unknown> = {};
  if (existing) {
    try {
      merged = JSON.parse(existing);
    } catch {
      // パース失敗時はリセット
    }
  }
  // 新しいニーズで上書き（空でないフィールドのみ）
  for (const [key, value] of Object.entries(needs)) {
    if (value !== undefined && value !== null && value !== '') {
      merged[key] = value;
    }
  }
  await AsyncStorage.setItem(STORAGE_KEYS.chatExtractedNeeds, JSON.stringify(merged));
}

/**
 * チャットニーズをクリア（会話リセット時）
 */
export async function clearChatNeeds(): Promise<void> {
  await AsyncStorage.removeItem(STORAGE_KEYS.chatExtractedNeeds);
}
