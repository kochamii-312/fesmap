import React, { useEffect, useState, useCallback, useRef, useMemo } from 'react';
import {
  View,
  Text,
  ScrollView,
  Pressable,
  StyleSheet,
  Alert,
  ActivityIndicator,
  Platform,
  Animated,
} from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import {
  MobilityType,
  Companion,
  AvoidCondition,
  PreferCondition,
  MOBILITY_LABELS,
  COMPANION_LABELS,
  AVOID_LABELS,
  PREFER_LABELS,
} from '../../src/types';
import { saveProfile as saveProfileApi } from '../../src/services/api';
import { getCurrentUserId, signOut } from '../../src/services/auth';
import { STORAGE_KEYS } from '../../src/constants/storageKeys';

const MOBILITY_TYPES: MobilityType[] = ['wheelchair', 'stroller', 'cane', 'walk', 'other'];
const COMPANIONS: Companion[] = ['child', 'elderly', 'disability'];
const AVOID_CONDITIONS: AvoidCondition[] = ['stairs', 'slope', 'crowd', 'dark'];
const PREFER_CONDITIONS: PreferCondition[] = ['restroom', 'rest_area', 'covered'];

const MIN_DISTANCE = 100;
const MAX_DISTANCE = 5000;
const DISTANCE_STEP = 100;

const HIT_SLOP = { top: 8, bottom: 8, left: 8, right: 8 };

// モビリティタイプごとのアイコン絵文字と説明
const MOBILITY_ICONS: Record<MobilityType, string> = {
  wheelchair: '\u267F',
  stroller: '\U0001F6BC',
  cane: '\U0001F9AF',
  walk: '\U0001F6B6',
  other: '\u2699\uFE0F',
};

const MOBILITY_DESCRIPTIONS: Record<MobilityType, string> = {
  wheelchair: 'スロープやエレベーターを優先案内',
  stroller: '段差の少ないルートを優先案内',
  cane: '歩きやすい平坦なルートを案内',
  walk: '標準的なルート案内',
  other: 'カスタム条件でルート案内',
};

// 同行者のアイコン
const COMPANION_ICONS: Record<Companion, string> = {
  child: '\U0001F9D2',
  elderly: '\U0001F9D3',
  disability: '\U0001F9D1\u200D\U0001F9BD',
};

// 回避条件のアイコン
const AVOID_ICONS: Record<AvoidCondition, string> = {
  stairs: '\U0001FA9C',
  slope: '\u26F0\uFE0F',
  crowd: '\U0001F465',
  dark: '\U0001F311',
};

// 希望条件のアイコン
const PREFER_ICONS: Record<PreferCondition, string> = {
  restroom: '\U0001F6BB',
  rest_area: '\U0001F4BA',
  covered: '\u2602\uFE0F',
};

// 距離の目安テキスト
function getDistanceGuide(meters: number): string {
  if (meters <= 300) return '短距離（駅構内程度）';
  if (meters <= 800) return 'やや短距離（バス停1〜2区間）';
  if (meters <= 1500) return '中距離（徒歩10〜15分程度）';
  if (meters <= 3000) return 'やや長距離（徒歩20〜30分程度）';
  return '長距離（徒歩30分以上）';
}

function formatDistance(meters: number): string {
  if (meters >= 1000) {
    return `${(meters / 1000).toFixed(1)}km`;
  }
  return `${meters}m`;
}

// 距離スライダーの目盛り生成
function getDistanceRatio(value: number): number {
  return (value - MIN_DISTANCE) / (MAX_DISTANCE - MIN_DISTANCE);
}

// トースト通知コンポーネント
function Toast({
  visible,
  message,
  type,
}: {
  visible: boolean;
  message: string;
  type: 'success' | 'error';
}) {
  const opacity = useRef(new Animated.Value(0)).current;
  const translateY = useRef(new Animated.Value(-20)).current;

  useEffect(() => {
    if (visible) {
      Animated.parallel([
        Animated.timing(opacity, {
          toValue: 1,
          duration: 300,
          useNativeDriver: true,
        }),
        Animated.timing(translateY, {
          toValue: 0,
          duration: 300,
          useNativeDriver: true,
        }),
      ]).start();
    } else {
      Animated.parallel([
        Animated.timing(opacity, {
          toValue: 0,
          duration: 300,
          useNativeDriver: true,
        }),
        Animated.timing(translateY, {
          toValue: -20,
          duration: 300,
          useNativeDriver: true,
        }),
      ]).start();
    }
  }, [visible, opacity, translateY]);

  if (!visible) return null;

  return (
    <Animated.View
      style={[
        styles.toast,
        type === 'success' ? styles.toastSuccess : styles.toastError,
        { opacity, transform: [{ translateY }] },
      ]}
      accessibilityRole="alert"
      accessibilityLiveRegion="assertive"
    >
      <Text style={styles.toastIcon}>
        {type === 'success' ? '\u2705' : '\u274C'}
      </Text>
      <Text style={styles.toastText}>{message}</Text>
    </Animated.View>
  );
}

// プロファイル完了度の計算
function calculateCompletionRate(
  mobilityType: MobilityType,
  companions: Companion[],
  maxDistance: number,
  avoidConditions: AvoidCondition[],
  preferConditions: PreferCondition[],
): number {
  let score = 0;
  const totalSections = 5;

  // 移動手段は常に選択済み（デフォルト値があるため）
  score += 1;

  // 同行者（任意だが設定すると完了度アップ）
  if (companions.length > 0) score += 1;

  // 距離はデフォルトから変更されていれば完了
  if (maxDistance !== 1000) score += 1;
  else score += 0.5; // デフォルトでも半分

  // 回避条件
  if (avoidConditions.length > 0) score += 1;

  // 希望条件
  if (preferConditions.length > 0) score += 1;

  return Math.round((score / totalSections) * 100);
}

// バリデーション結果の型
interface ValidationResult {
  isValid: boolean;
  errors: string[];
}

// 入力バリデーション
function validateProfile(
  mobilityType: MobilityType,
  companions: Companion[],
  maxDistance: number,
  avoidConditions: AvoidCondition[],
  preferConditions: PreferCondition[],
): ValidationResult {
  const errors: string[] = [];

  // 移動手段の妥当性チェック
  if (!MOBILITY_TYPES.includes(mobilityType)) {
    errors.push('無効な移動手段が選択されています');
  }

  // 同行者の重複チェック
  const uniqueCompanions = new Set(companions);
  if (uniqueCompanions.size !== companions.length) {
    errors.push('同行者の選択に重複があります');
  }

  // 距離の範囲チェック
  if (maxDistance < MIN_DISTANCE || maxDistance > MAX_DISTANCE) {
    errors.push(`移動距離は${formatDistance(MIN_DISTANCE)}〜${formatDistance(MAX_DISTANCE)}の範囲で設定してください`);
  }

  // 距離のステップ整合性チェック
  if ((maxDistance - MIN_DISTANCE) % DISTANCE_STEP !== 0) {
    errors.push('移動距離の値が不正です');
  }

  // 回避条件の妥当性チェック
  for (const c of avoidConditions) {
    if (!AVOID_CONDITIONS.includes(c)) {
      errors.push(`無効な回避条件が含まれています: ${c}`);
    }
  }

  // 希望条件の妥当性チェック
  for (const c of preferConditions) {
    if (!PREFER_CONDITIONS.includes(c)) {
      errors.push(`無効な希望条件が含まれています: ${c}`);
    }
  }

  // 矛盾チェック: 車椅子で階段回避が未設定の場合の警告（エラーではなく注意）
  // ※ここではエラーとしないが将来的に活用可能

  return {
    isValid: errors.length === 0,
    errors,
  };
}

export default function ProfileScreen() {
  const [mobilityType, setMobilityType] = useState<MobilityType>('walk');
  const [companions, setCompanions] = useState<Companion[]>([]);
  const [maxDistance, setMaxDistance] = useState(1000);
  const [avoidConditions, setAvoidConditions] = useState<AvoidCondition[]>([]);
  const [preferConditions, setPreferConditions] = useState<PreferCondition[]>([]);
  const [isSaving, setIsSaving] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [userId, setUserId] = useState<string | null>(null);

  // トースト表示用ステート
  const [toastVisible, setToastVisible] = useState(false);
  const [toastMessage, setToastMessage] = useState('');
  const [toastType, setToastType] = useState<'success' | 'error'>('success');
  const toastTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // トースト表示関数
  const showToast = useCallback((message: string, type: 'success' | 'error') => {
    // 既存のタイマーをクリア
    if (toastTimerRef.current) {
      clearTimeout(toastTimerRef.current);
    }
    setToastMessage(message);
    setToastType(type);
    setToastVisible(true);
    toastTimerRef.current = setTimeout(() => {
      setToastVisible(false);
    }, 3000);
  }, []);

  // タイマーのクリーンアップ
  useEffect(() => {
    return () => {
      if (toastTimerRef.current) {
        clearTimeout(toastTimerRef.current);
      }
    };
  }, []);

  // プロファイル完了度の計算
  const completionRate = useMemo(
    () => calculateCompletionRate(mobilityType, companions, maxDistance, avoidConditions, preferConditions),
    [mobilityType, companions, maxDistance, avoidConditions, preferConditions],
  );

  // 完了度に応じた色を返す
  const completionColor = useMemo(() => {
    if (completionRate >= 80) return '#34C759';
    if (completionRate >= 50) return '#FF9500';
    return '#FF3B30';
  }, [completionRate]);

  // ローカルからプロファイルを読み込み
  const loadProfile = useCallback(async () => {
    setIsLoading(true);
    try {
      const uid = await getCurrentUserId();
      setUserId(uid);

      const [rawMobility, rawCompanions, rawDistance, rawAvoid, rawPrefer] = await Promise.all([
        AsyncStorage.getItem(STORAGE_KEYS.mobilityType),
        AsyncStorage.getItem(STORAGE_KEYS.companions),
        AsyncStorage.getItem(STORAGE_KEYS.maxDistance),
        AsyncStorage.getItem(STORAGE_KEYS.avoidConditions),
        AsyncStorage.getItem(STORAGE_KEYS.preferConditions),
      ]);

      if (rawMobility && MOBILITY_TYPES.includes(rawMobility as MobilityType)) {
        setMobilityType(rawMobility as MobilityType);
      }
      if (rawCompanions) {
        const parsed: Companion[] = JSON.parse(rawCompanions);
        setCompanions(parsed.filter((c) => COMPANIONS.includes(c)));
      }
      if (rawDistance) {
        const d = Number(rawDistance);
        if (d >= MIN_DISTANCE && d <= MAX_DISTANCE) setMaxDistance(d);
      }
      if (rawAvoid) {
        const parsed: AvoidCondition[] = JSON.parse(rawAvoid);
        setAvoidConditions(parsed.filter((c) => AVOID_CONDITIONS.includes(c)));
      }
      if (rawPrefer) {
        const parsed: PreferCondition[] = JSON.parse(rawPrefer);
        setPreferConditions(parsed.filter((c) => PREFER_CONDITIONS.includes(c)));
      }
    } catch {
      // 初回起動時はデフォルト値を使用
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    loadProfile();
  }, [loadProfile]);

  // ローカルに保存
  const saveToStorage = async () => {
    await Promise.all([
      AsyncStorage.setItem(STORAGE_KEYS.mobilityType, mobilityType),
      AsyncStorage.setItem(STORAGE_KEYS.companions, JSON.stringify(companions)),
      AsyncStorage.setItem(STORAGE_KEYS.maxDistance, String(maxDistance)),
      AsyncStorage.setItem(STORAGE_KEYS.avoidConditions, JSON.stringify(avoidConditions)),
      AsyncStorage.setItem(STORAGE_KEYS.preferConditions, JSON.stringify(preferConditions)),
    ]);
  };

  // 保存処理
  const handleSave = async () => {
    setErrorMessage(null);

    // バリデーション実行
    const validation = validateProfile(
      mobilityType,
      companions,
      maxDistance,
      avoidConditions,
      preferConditions,
    );

    if (!validation.isValid) {
      const errorMsg = validation.errors.join('\n');
      setErrorMessage(errorMsg);
      showToast('入力内容にエラーがあります', 'error');
      return;
    }

    setIsSaving(true);
    try {
      await saveToStorage();

      // サーバーへの保存も試行（失敗してもローカル保存は完了）
      let serverSaved = true;
      try {
        await saveProfileApi({
          mobilityType,
          companions,
          maxDistanceMeters: maxDistance,
          avoidConditions,
          preferConditions,
        });
      } catch {
        // サーバー未接続時はローカル保存のみで成功とする
        serverSaved = false;
      }

      if (serverSaved) {
        showToast('プロファイルを保存しました', 'success');
      } else {
        showToast('ローカルに保存しました（サーバー同期は次回接続時）', 'success');
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : '保存に失敗しました';
      setErrorMessage(msg);
      showToast('保存に失敗しました', 'error');
    } finally {
      setIsSaving(false);
    }
  };

  // 同行者トグル
  const toggleCompanion = useCallback((c: Companion) => {
    setCompanions((prev) =>
      prev.includes(c) ? prev.filter((v) => v !== c) : [...prev, c],
    );
  }, []);

  // 回避条件トグル
  const toggleAvoid = useCallback((c: AvoidCondition) => {
    setAvoidConditions((prev) =>
      prev.includes(c) ? prev.filter((v) => v !== c) : [...prev, c],
    );
  }, []);

  // 希望条件トグル
  const togglePrefer = useCallback((c: PreferCondition) => {
    setPreferConditions((prev) =>
      prev.includes(c) ? prev.filter((v) => v !== c) : [...prev, c],
    );
  }, []);

  // 距離の増減
  const decreaseDistance = useCallback(() => {
    setMaxDistance((prev) => Math.max(MIN_DISTANCE, prev - DISTANCE_STEP));
  }, []);

  const increaseDistance = useCallback(() => {
    setMaxDistance((prev) => Math.min(MAX_DISTANCE, prev + DISTANCE_STEP));
  }, []);

  const handleSignOut = useCallback(async () => {
    Alert.alert('サインアウト', 'サインアウトしますか？', [
      { text: 'キャンセル', style: 'cancel' },
      {
        text: 'サインアウト',
        style: 'destructive',
        onPress: async () => {
          try {
            await signOut();
            setUserId(null);
            showToast('サインアウトしました', 'success');
          } catch {
            showToast('サインアウトに失敗しました', 'error');
          }
        },
      },
    ]);
  }, [showToast]);

  if (isLoading) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color="#007AFF" />
      </View>
    );
  }

  const distanceRatio = getDistanceRatio(maxDistance);

  return (
    <View style={styles.screenContainer}>
      {/* トースト通知 */}
      <Toast visible={toastVisible} message={toastMessage} type={toastType} />

      <ScrollView
        style={styles.container}
        contentContainerStyle={styles.content}
        keyboardShouldPersistTaps="handled"
        bounces={true}
      >
        {/* プロファイル完了度 */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>プロファイル完了度</Text>
          <Text style={styles.helpText}>
            各項目を設定するほど、より適切なルート案内が可能になります
          </Text>
          <View style={styles.completionBarContainer}>
            <View style={styles.completionBarTrack}>
              <View
                style={[
                  styles.completionBarFill,
                  { width: `${completionRate}%`, backgroundColor: completionColor },
                ]}
              />
            </View>
            <Text
              style={[styles.completionText, { color: completionColor }]}
              accessibilityLabel={`プロファイル完了度 ${completionRate}パーセント`}
            >
              {completionRate}%
            </Text>
          </View>
          {completionRate < 100 && (
            <Text style={styles.completionHint}>
              {companions.length === 0 && avoidConditions.length === 0
                ? '同行者や回避条件を設定すると、より安全なルートを案内できます'
                : preferConditions.length === 0
                  ? '希望条件を設定すると、快適なルートを案内できます'
                  : '各項目を見直して、プロファイルを完成させましょう'}
            </Text>
          )}
        </View>

        {/* 移動手段 */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>移動手段</Text>
          <Text style={styles.helpText}>
            普段の移動方法を選択してください。選択に応じてルート案内が最適化されます
          </Text>
          {MOBILITY_TYPES.map((type) => {
            const selected = mobilityType === type;
            return (
              <Pressable
                key={type}
                style={({ pressed }) => [
                  styles.radioRow,
                  selected && styles.selectedRow,
                  pressed && styles.pressedRow,
                ]}
                onPress={() => setMobilityType(type)}
                hitSlop={HIT_SLOP}
                accessibilityRole="radio"
                accessibilityState={{ selected }}
                accessibilityLabel={`${MOBILITY_LABELS[type]}を選択`}
              >
                <View
                  style={[
                    styles.radioOuter,
                    selected && styles.radioOuterSelected,
                  ]}
                >
                  {selected && <View style={styles.radioInner} />}
                </View>
                <Text style={styles.optionIcon}>{MOBILITY_ICONS[type]}</Text>
                <View style={styles.optionTextContainer}>
                  <Text style={styles.optionLabel}>{MOBILITY_LABELS[type]}</Text>
                  <Text style={styles.optionDescription}>{MOBILITY_DESCRIPTIONS[type]}</Text>
                </View>
              </Pressable>
            );
          })}
        </View>

        {/* 同行者 */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>同行者</Text>
          <Text style={styles.helpText}>
            一緒に移動する方がいる場合に選択してください（複数選択可）
          </Text>
          {COMPANIONS.map((c) => {
            const checked = companions.includes(c);
            return (
              <Pressable
                key={c}
                style={({ pressed }) => [
                  styles.checkboxRow,
                  pressed && styles.pressedRow,
                ]}
                onPress={() => toggleCompanion(c)}
                hitSlop={HIT_SLOP}
                accessibilityRole="checkbox"
                accessibilityState={{ checked }}
                accessibilityLabel={`${COMPANION_LABELS[c]}の同行`}
              >
                <View style={[styles.checkbox, checked && styles.checkboxChecked]}>
                  {checked && <Text style={styles.checkmark}>{'\u2713'}</Text>}
                </View>
                <Text style={styles.optionIcon}>{COMPANION_ICONS[c]}</Text>
                <Text style={styles.optionLabel}>{COMPANION_LABELS[c]}</Text>
              </Pressable>
            );
          })}
        </View>

        {/* 最大移動距離 */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>最大移動距離</Text>
          <Text style={styles.helpText}>
            一度に移動できる最大距離を設定してください。無理のない範囲で設定しましょう
          </Text>
          <Text
            style={styles.distanceValue}
            accessibilityLabel={`現在の最大移動距離: ${formatDistance(maxDistance)}`}
          >
            {formatDistance(maxDistance)}
          </Text>
          <Text style={styles.distanceGuide}>
            {getDistanceGuide(maxDistance)}
          </Text>

          {/* スライダー風バー + ステッパーボタン */}
          <View style={styles.sliderRow}>
            <Pressable
              style={({ pressed }) => [
                styles.stepButton,
                maxDistance <= MIN_DISTANCE && styles.stepButtonDisabled,
                pressed && !(maxDistance <= MIN_DISTANCE) && styles.stepButtonPressed,
              ]}
              onPress={decreaseDistance}
              disabled={maxDistance <= MIN_DISTANCE}
              hitSlop={HIT_SLOP}
              accessibilityLabel="距離を減らす"
              accessibilityRole="button"
            >
              <Text style={[styles.stepButtonText, maxDistance <= MIN_DISTANCE && styles.stepButtonTextDisabled]}>
                -
              </Text>
            </Pressable>

            <View
              style={styles.sliderTrackContainer}
              accessibilityLabel="最大移動距離"
              accessibilityValue={{ text: formatDistance(maxDistance) }}
            >
              <View style={styles.sliderTrack}>
                <View style={[styles.sliderFill, { width: `${distanceRatio * 100}%` }]} />
              </View>
              <View style={styles.sliderLabelsRow}>
                <Text style={styles.sliderLabel}>100m</Text>
                <Text style={styles.sliderLabel}>5km</Text>
              </View>
            </View>

            <Pressable
              style={({ pressed }) => [
                styles.stepButton,
                maxDistance >= MAX_DISTANCE && styles.stepButtonDisabled,
                pressed && !(maxDistance >= MAX_DISTANCE) && styles.stepButtonPressed,
              ]}
              onPress={increaseDistance}
              disabled={maxDistance >= MAX_DISTANCE}
              hitSlop={HIT_SLOP}
              accessibilityLabel="距離を増やす"
              accessibilityRole="button"
            >
              <Text style={[styles.stepButtonText, maxDistance >= MAX_DISTANCE && styles.stepButtonTextDisabled]}>
                +
              </Text>
            </Pressable>
          </View>
        </View>

        {/* 回避したい条件 */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>回避したい条件</Text>
          <Text style={styles.helpText}>
            ルート上で避けたい条件を選択してください（複数選択可）
          </Text>
          {AVOID_CONDITIONS.map((c) => {
            const checked = avoidConditions.includes(c);
            return (
              <Pressable
                key={c}
                style={({ pressed }) => [
                  styles.checkboxRow,
                  pressed && styles.pressedRow,
                ]}
                onPress={() => toggleAvoid(c)}
                hitSlop={HIT_SLOP}
                accessibilityRole="checkbox"
                accessibilityState={{ checked }}
                accessibilityLabel={`${AVOID_LABELS[c]}を回避`}
              >
                <View style={[styles.checkbox, checked && styles.checkboxChecked]}>
                  {checked && <Text style={styles.checkmark}>{'\u2713'}</Text>}
                </View>
                <Text style={styles.optionIcon}>{AVOID_ICONS[c]}</Text>
                <Text style={styles.optionLabel}>{AVOID_LABELS[c]}</Text>
              </Pressable>
            );
          })}
        </View>

        {/* 希望条件 */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>希望条件</Text>
          <Text style={styles.helpText}>
            ルート沿いにあると便利な施設を選択してください（複数選択可）
          </Text>
          {PREFER_CONDITIONS.map((c) => {
            const checked = preferConditions.includes(c);
            return (
              <Pressable
                key={c}
                style={({ pressed }) => [
                  styles.checkboxRow,
                  pressed && styles.pressedRow,
                ]}
                onPress={() => togglePrefer(c)}
                hitSlop={HIT_SLOP}
                accessibilityRole="checkbox"
                accessibilityState={{ checked }}
                accessibilityLabel={`${PREFER_LABELS[c]}を希望`}
              >
                <View style={[styles.checkbox, checked && styles.checkboxChecked]}>
                  {checked && <Text style={styles.checkmark}>{'\u2713'}</Text>}
                </View>
                <Text style={styles.optionIcon}>{PREFER_ICONS[c]}</Text>
                <Text style={styles.optionLabel}>{PREFER_LABELS[c]}</Text>
              </Pressable>
            );
          })}
        </View>

        {/* エラー表示 */}
        {errorMessage && (
          <View style={styles.errorContainer}>
            <Text style={styles.errorText}>{errorMessage}</Text>
          </View>
        )}

        {/* 保存ボタン */}
        <Pressable
          style={({ pressed }) => [
            styles.saveButton,
            isSaving && styles.saveButtonDisabled,
            pressed && !isSaving && styles.saveButtonPressed,
          ]}
          onPress={handleSave}
          disabled={isSaving}
          hitSlop={HIT_SLOP}
          accessibilityRole="button"
          accessibilityLabel="プロファイルを保存"
        >
          {isSaving && <ActivityIndicator size="small" color="#fff" style={styles.saveSpinner} />}
          <Text style={styles.saveButtonText}>保存する</Text>
        </Pressable>

        {/* ユーザー情報・サインアウト */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>アカウント</Text>
          <View style={styles.checkboxRow}>
            <Text style={styles.optionLabel}>
              {userId ? `ユーザーID: ${userId.slice(0, 12)}...` : 'ログインしていません'}
            </Text>
          </View>
          {userId && (
            <Pressable
              style={({ pressed }) => [
                styles.signOutButton,
                pressed && styles.signOutButtonPressed,
              ]}
              onPress={handleSignOut}
              hitSlop={HIT_SLOP}
              accessibilityRole="button"
              accessibilityLabel="サインアウト"
            >
              <Text style={styles.signOutButtonText}>サインアウト</Text>
            </Pressable>
          )}
        </View>

        <View style={styles.bottomSpacer} />
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  screenContainer: {
    flex: 1,
    backgroundColor: '#F2F2F7',
  },
  container: {
    flex: 1,
    backgroundColor: '#F2F2F7',
  },
  content: {
    padding: 16,
    paddingBottom: 48,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#F2F2F7',
  },
  // トースト通知
  toast: {
    position: 'absolute',
    top: Platform.OS === 'ios' ? 60 : 40,
    left: 16,
    right: 16,
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderRadius: 12,
    zIndex: 1000,
    ...Platform.select({
      ios: {
        shadowColor: '#000',
        shadowOffset: { width: 0, height: 4 },
        shadowOpacity: 0.15,
        shadowRadius: 8,
      },
      android: {
        elevation: 6,
      },
    }),
  },
  toastSuccess: {
    backgroundColor: '#E8F5E9',
    borderLeftWidth: 4,
    borderLeftColor: '#34C759',
  },
  toastError: {
    backgroundColor: '#FFEBEE',
    borderLeftWidth: 4,
    borderLeftColor: '#FF3B30',
  },
  toastIcon: {
    fontSize: 18,
    marginRight: 8,
  },
  toastText: {
    fontSize: 15,
    fontWeight: '500',
    color: '#333',
    flexShrink: 1,
  },
  // プロファイル完了度
  completionBarContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 8,
  },
  completionBarTrack: {
    flex: 1,
    height: 10,
    borderRadius: 5,
    backgroundColor: '#E5E5EA',
    overflow: 'hidden',
  },
  completionBarFill: {
    height: '100%',
    borderRadius: 5,
  },
  completionText: {
    fontSize: 18,
    fontWeight: '700',
    marginLeft: 12,
    minWidth: 48,
    textAlign: 'right',
  },
  completionHint: {
    fontSize: 13,
    color: '#8E8E93',
    marginTop: 8,
    lineHeight: 18,
  },
  // セクション
  section: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    marginBottom: 16,
  },
  sectionTitle: {
    fontSize: 15,
    fontWeight: '600',
    color: '#6D6D72',
    textTransform: 'uppercase',
    marginBottom: 4,
  },
  helpText: {
    fontSize: 13,
    color: '#8E8E93',
    marginBottom: 12,
    lineHeight: 18,
  },
  sectionFooter: {
    fontSize: 13,
    color: '#8E8E93',
    marginBottom: 12,
  },
  radioRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
    paddingHorizontal: 4,
    minHeight: 48,
    borderRadius: 8,
  },
  selectedRow: {
    backgroundColor: '#F0F7FF',
  },
  pressedRow: {
    backgroundColor: '#E8E8ED',
  },
  radioOuter: {
    width: 24,
    height: 24,
    borderRadius: 12,
    borderWidth: 2,
    borderColor: '#C7C7CC',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 8,
  },
  radioOuterSelected: {
    borderColor: '#007AFF',
  },
  radioInner: {
    width: 12,
    height: 12,
    borderRadius: 6,
    backgroundColor: '#007AFF',
  },
  checkboxRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
    paddingHorizontal: 4,
    minHeight: 48,
    borderRadius: 8,
  },
  checkbox: {
    width: 24,
    height: 24,
    borderRadius: 4,
    borderWidth: 2,
    borderColor: '#C7C7CC',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 8,
  },
  checkboxChecked: {
    backgroundColor: '#007AFF',
    borderColor: '#007AFF',
  },
  checkmark: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '700',
  },
  optionIcon: {
    fontSize: 22,
    marginRight: 8,
  },
  optionLabel: {
    fontSize: 17,
    color: '#000',
    flexShrink: 1,
  },
  optionTextContainer: {
    flex: 1,
    flexShrink: 1,
  },
  optionDescription: {
    fontSize: 12,
    color: '#8E8E93',
    marginTop: 2,
  },
  distanceValue: {
    fontSize: 28,
    fontWeight: '700',
    color: '#000',
    marginBottom: 4,
  },
  distanceGuide: {
    fontSize: 14,
    color: '#007AFF',
    fontWeight: '500',
    marginBottom: 12,
  },
  sliderRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  stepButton: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: '#E5E5EA',
    justifyContent: 'center',
    alignItems: 'center',
  },
  stepButtonPressed: {
    backgroundColor: '#C7C7CC',
  },
  stepButtonDisabled: {
    opacity: 0.4,
  },
  stepButtonText: {
    fontSize: 24,
    fontWeight: '600',
    color: '#007AFF',
    lineHeight: Platform.OS === 'android' ? 28 : 26,
    textAlign: 'center',
  },
  stepButtonTextDisabled: {
    color: '#8E8E93',
  },
  sliderTrackContainer: {
    flex: 1,
    marginHorizontal: 12,
  },
  sliderTrack: {
    height: 6,
    borderRadius: 3,
    backgroundColor: '#D1D1D6',
    overflow: 'hidden',
  },
  sliderFill: {
    height: '100%',
    backgroundColor: '#007AFF',
    borderRadius: 3,
  },
  sliderLabelsRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 4,
  },
  sliderLabel: {
    fontSize: 12,
    color: '#8E8E93',
  },
  errorContainer: {
    backgroundColor: '#FFF0F0',
    borderRadius: 8,
    padding: 12,
    marginBottom: 16,
  },
  errorText: {
    color: '#FF3B30',
    fontSize: 14,
  },
  saveButton: {
    backgroundColor: '#007AFF',
    borderRadius: 12,
    paddingVertical: 16,
    alignItems: 'center',
    justifyContent: 'center',
    flexDirection: 'row',
    marginBottom: 8,
    minHeight: 52,
  },
  saveButtonPressed: {
    backgroundColor: '#0056B3',
  },
  saveButtonDisabled: {
    opacity: 0.6,
  },
  saveButtonText: {
    color: '#fff',
    fontSize: 17,
    fontWeight: '600',
  },
  saveSpinner: {
    marginRight: 8,
  },
  signOutButton: {
    marginTop: 8,
    paddingVertical: 12,
    borderRadius: 8,
    backgroundColor: '#FF3B30',
    alignItems: 'center',
    minHeight: 44,
    justifyContent: 'center',
  },
  signOutButtonPressed: {
    backgroundColor: '#CC2F27',
  },
  signOutButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  bottomSpacer: {
    height: 32,
  },
});
