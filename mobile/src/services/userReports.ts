/**
 * ユーザーレポートサービス
 * アクセシビリティのバリアや確認情報をユーザーが報告するための機能
 * AsyncStorageでローカル保存（バックエンド未接続）
 */

import AsyncStorage from '@react-native-async-storage/async-storage';

/** ユーザー報告データ */
export interface UserReport {
  id: string;
  location: { lat: number; lng: number };
  type: 'barrier' | 'accessible' | 'info';
  category:
    | 'steps'
    | 'steep_slope'
    | 'narrow_path'
    | 'no_sidewalk'
    | 'construction'
    | 'accessible_route'
    | 'elevator_working'
    | 'elevator_broken'
    | 'other';
  description: string;
  timestamp: number; // Unix ms
  expiresAt?: number; // Unix ms - 工事等の一時的な問題用
}

/** AsyncStorageのキー */
const STORAGE_KEY = 'user_accessibility_reports';

/** 保存する最大レポート数 */
const MAX_REPORTS = 500;

/** 工事レポートの有効期限（30日） */
const CONSTRUCTION_EXPIRY_MS = 30 * 24 * 60 * 60 * 1000;

/**
 * AsyncStorageからレポート一覧を読み込む
 * @returns 保存済みレポートの配列
 */
async function loadReports(): Promise<UserReport[]> {
  const raw = await AsyncStorage.getItem(STORAGE_KEY);
  if (!raw) return [];
  try {
    return JSON.parse(raw) as UserReport[];
  } catch {
    return [];
  }
}

/**
 * AsyncStorageにレポート一覧を保存する
 * @param reports 保存するレポートの配列
 */
async function saveReports(reports: UserReport[]): Promise<void> {
  await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(reports));
}

/**
 * アクセシビリティレポートを投稿する
 * IDとタイムスタンプを自動生成し、AsyncStorageに保存する
 * @param report レポートデータ（ID・タイムスタンプを除く）
 */
export async function submitReport(
  report: Omit<UserReport, 'id' | 'timestamp'>
): Promise<void> {
  const now = Date.now();
  const id = `report_${now}_${Math.random().toString(36).slice(2, 6)}`;

  const newReport: UserReport = {
    ...report,
    id,
    timestamp: now,
  };

  // 工事カテゴリの場合は30日後に期限切れにする
  if (report.category === 'construction') {
    newReport.expiresAt = now + CONSTRUCTION_EXPIRY_MS;
  }

  // 既存レポートを読み込み、新しいレポートを追加
  const existing = await loadReports();
  existing.push(newReport);

  // 最大数を超えた場合、古いレポートから削除（タイムスタンプ昇順でソートして先頭を削る）
  if (existing.length > MAX_REPORTS) {
    existing.sort((a, b) => a.timestamp - b.timestamp);
    existing.splice(0, existing.length - MAX_REPORTS);
  }

  await saveReports(existing);
}

/**
 * 指定地点の近傍にあるレポートを取得する
 * 簡易的な緯度経度距離近似を使用（1度 ≈ 111320m）
 * @param lat 緯度
 * @param lng 経度
 * @param radiusMeters 検索半径（メートル）
 * @returns 近傍のレポート（新しい順）
 */
export async function getNearbyReports(
  lat: number,
  lng: number,
  radiusMeters: number
): Promise<UserReport[]> {
  const reports = await loadReports();
  const now = Date.now();

  return reports
    .filter((report) => {
      // 期限切れレポートを除外
      if (report.expiresAt != null && report.expiresAt < now) {
        return false;
      }

      // 距離フィルタ（簡易近似: 1度 ≈ 111320m）
      const dLat = (report.location.lat - lat) * 111320;
      const dLng =
        (report.location.lng - lng) *
        111320 *
        Math.cos((lat * Math.PI) / 180);
      const distance = Math.sqrt(dLat * dLat + dLng * dLng);

      return distance <= radiusMeters;
    })
    .sort((a, b) => b.timestamp - a.timestamp); // 新しい順
}

/**
 * レポートをIDで削除する
 * @param reportId 削除するレポートのID
 */
export async function deleteReport(reportId: string): Promise<void> {
  const reports = await loadReports();
  const filtered = reports.filter((r) => r.id !== reportId);
  await saveReports(filtered);
}

/**
 * 期限切れのレポートをすべて削除する
 */
export async function clearExpiredReports(): Promise<void> {
  const reports = await loadReports();
  const now = Date.now();
  const active = reports.filter(
    (r) => r.expiresAt == null || r.expiresAt >= now
  );
  await saveReports(active);
}
