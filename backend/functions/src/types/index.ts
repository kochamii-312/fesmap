// AccessRoute - 共通データ型定義
// docs/data-models.ts の型定義をバックエンド用に再定義

import { Timestamp } from "firebase-admin/firestore";

// ============================================================
// ユーザー関連
// ============================================================

export type MobilityType = "wheelchair" | "stroller" | "cane" | "walk" | "other";
export type Companion = "child" | "elderly" | "disability";
export type AvoidCondition = "stairs" | "slope" | "crowd" | "dark";
export type PreferCondition = "restroom" | "rest_area" | "covered";

export interface UserProfile {
  userId: string;
  mobilityType: MobilityType;
  companions: Companion[];
  maxDistanceMeters: number;
  avoidConditions: AvoidCondition[];
  preferConditions: PreferCondition[];
  createdAt: Timestamp;
  updatedAt: Timestamp;
  /** フィールドごとの最終更新タイムスタンプ */
  fieldUpdatedAt?: Record<string, Timestamp>;
  /** 矛盾検出により確認が必要なフィールド一覧 */
  conflictFlags?: string[];
}

// ============================================================
// プロファイルマージ関連
// ============================================================

/** マージオプション（confidence や呼び出し元情報） */
export interface MergeOptions {
  /** AIの抽出信頼度スコア（0.0〜1.0） */
  confidence?: number;
  /** マージ元の識別子（デバッグ・履歴用） */
  source?: string;
}

/** マージ結果の詳細情報 */
export interface MergeResult {
  /** マージ後のプロファイル */
  profile: UserProfile;
  /** マージがスキップされた場合 true */
  skipped: boolean;
  /** スキップ理由 */
  skipReason?: string;
  /** 矛盾が検出されたフィールド一覧 */
  conflicts: string[];
  /** 実際に更新されたフィールド一覧 */
  updatedFields: string[];
}

/** マージ履歴エントリ */
export interface MergeHistoryEntry {
  /** 履歴ID（自動生成） */
  historyId?: string;
  /** ユーザーID */
  userId: string;
  /** マージ前のプロファイルスナップショット */
  beforeSnapshot: Partial<UserProfile>;
  /** マージ後のプロファイルスナップショット */
  afterSnapshot: Partial<UserProfile>;
  /** 適用された変更内容 */
  appliedChanges: Record<string, unknown>;
  /** AI抽出の信頼度スコア */
  confidence: number;
  /** 検出された矛盾 */
  conflicts: string[];
  /** マージ元の識別子 */
  source: string;
  /** マージ実行日時 */
  mergedAt: Timestamp;
}

export interface UserProfileInput {
  mobilityType: MobilityType;
  companions?: Companion[];
  maxDistanceMeters?: number;
  avoidConditions?: AvoidCondition[];
  preferConditions?: PreferCondition[];
}

// ============================================================
// ルート関連
// ============================================================

export type RoutePriority = "shortest" | "safest" | "accessible";
export type TransportMode = "walking" | "transit" | "driving" | "bicycling";

export interface LatLng {
  lat: number;
  lng: number;
}

export interface RouteRequest {
  origin: LatLng;
  destination: LatLng;
  userProfileId: string;
  prioritize?: RoutePriority;
  mode?: TransportMode;  // default: 'walking'
}

export interface TransitDetail {
  lineName: string;
  lineShortName?: string;
  lineColor?: string;
  vehicleType: "train" | "subway" | "bus" | "tram" | "ferry" | "other";
  departureStop: string;
  arrivalStop: string;
  departureTime?: string;
  arrivalTime?: string;
  numStops: number;
  headSign?: string;
}

export interface RouteStep {
  stepId: string;
  instruction: string;
  distanceMeters: number;
  durationSeconds: number;
  startLocation: LatLng;
  endLocation: LatLng;
  polyline: string;
  hasStairs: boolean;
  hasSlope: boolean;
  slopeGrade?: number;
  surfaceType?: "paved" | "gravel" | "dirt" | "unknown";
  transitDetail?: TransitDetail;
}

export interface SpotSummary {
  spotId: string;
  name: string;
  category: SpotCategory;
  location: LatLng;
  accessibilityScore: number;
  /** フロントエンド向けフィールド名 */
  distanceMeters: number;
  /** 後方互換性のため残す（distanceMeters と同値） */
  distanceFromRoute: number;
  /** 車椅子アクセス可否 */
  wheelchairAccessible: boolean;
}

export interface RouteResult {
  routeId: string;
  accessibilityScore: number;
  distanceMeters: number;
  durationMinutes: number;
  steps: RouteStep[];
  warnings: string[];
  nearbySpots: SpotSummary[];
}

export interface RouteResponse {
  routes: RouteResult[];
}

// ============================================================
// スポット関連
// ============================================================

export type SpotCategory =
  | "restroom"
  | "rest_area"
  | "restaurant"
  | "cafe"
  | "park"
  | "kids_space"
  | "nursing_room"
  | "elevator"
  | "parking"
  | "other";

export interface AccessibilityInfo {
  wheelchairAccessible: boolean;
  hasElevator: boolean;
  hasAccessibleRestroom: boolean;
  hasBabyChangingStation: boolean;
  hasNursingRoom: boolean;
  floorType: "flat" | "steps" | "slope" | "mixed";
  notes: string[];
}

export interface SpotDetail {
  spotId: string;
  name: string;
  description: string;
  category: SpotCategory;
  location: LatLng;
  address: string;
  accessibilityScore: number;
  accessibility: AccessibilityInfo;
  photoUrls: string[];
  openingHours?: string;
  phoneNumber?: string;
  website?: string;
}

// ============================================================
// AIチャット関連
// ============================================================

export type ChatRole = "user" | "assistant";
export type SuggestedAction = "ask_more" | "search_route" | "show_spots" | null;

export interface ChatMessage {
  role: ChatRole;
  content: string;
}

export interface ChatRequest {
  userId: string;
  message: string;
  conversationHistory: ChatMessage[];
}

export interface ChatResponse {
  reply: string;
  extractedNeeds: Partial<UserProfile> | null;
  suggestedAction: SuggestedAction;
  /** AI抽出の信頼度スコア（0.0〜1.0、省略時は 1.0 として扱う） */
  confidence?: number;
}

export interface ExtractNeedsRequest {
  userId: string;
  conversationHistory: ChatMessage[];
}

export interface ExtractNeedsResponse {
  needs: Partial<UserProfile>;
  confidence: number;
  missingFields: string[];
}

// ============================================================
// 会話管理関連
// ============================================================

export type AIChatRole = "user" | "assistant" | "system";

export interface AIChatMessage {
  role: AIChatRole;
  content: string;
}

export interface ConversationMessage {
  role: ChatRole;
  content: string;
  timestamp: Timestamp;
}

export interface Conversation {
  conversationId: string;
  userId: string;
  messages: ConversationMessage[];
  createdAt: Timestamp;
  updatedAt: Timestamp;
  expiresAt: Timestamp;
}

// ============================================================
// AI推論サーバーレスポンス型（snake_case）
// ============================================================

export interface AIChatApiResponse {
  reply: string;
  extracted_needs?: {
    mobility_type?: string;
    companions?: string[];
    max_distance_meters?: number;
    avoid_conditions?: string[];
    prefer_conditions?: string[];
  } | null;
  suggested_action?: string | null;
  confidence?: number;
}

export interface AIExtractNeedsApiResponse {
  needs: {
    mobility_type?: string;
    companions?: string[];
    max_distance_meters?: number;
    avoid_conditions?: string[];
    prefer_conditions?: string[];
  };
  confidence: number;
  missing_fields: string[];
}

export interface AIHealthResponse {
  status: "ok" | "loading" | "error";
  model?: string;
  uptime_seconds?: number;
}
