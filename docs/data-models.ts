// AccessRoute - 共通データ型定義
// すべてのエージェントが参照する共通インターフェース

import { Timestamp } from "firebase/firestore";

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
}

// ============================================================
// ルート関連
// ============================================================

export type RoutePriority = "shortest" | "safest" | "accessible";

export interface LatLng {
  lat: number;
  lng: number;
}

export interface RouteRequest {
  origin: LatLng;
  destination: LatLng;
  userProfileId: string;
  prioritize: RoutePriority;
}

export interface RouteStep {
  stepId: string;
  instruction: string;
  distanceMeters: number;
  durationSeconds: number;
  startLocation: LatLng;
  endLocation: LatLng;
  polyline: string; // encoded polyline
  hasStairs: boolean;
  hasSlope: boolean;
  slopeGrade?: number; // 勾配 (%)
  surfaceType?: "paved" | "gravel" | "dirt" | "unknown";
}

export interface SpotSummary {
  spotId: string;
  name: string;
  category: SpotCategory;
  location: LatLng;
  accessibilityScore: number; // 0-100
  distanceFromRoute: number; // meters
}

export interface RouteResult {
  routeId: string;
  accessibilityScore: number; // 0-100
  distanceMeters: number;
  durationMinutes: number;
  steps: RouteStep[];
  warnings: string[]; // "この区間に階段あり" 等
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
}

// ============================================================
// AIニーズ抽出関連
// ============================================================

export interface ExtractNeedsRequest {
  userId: string;
  conversationHistory: ChatMessage[];
}

// ============================================================
// 学園祭（フェスマップ）関連
// ============================================================

export type ProjectClassification = "stage_event" | "general" | "stall"; // 区分: ステージ企画、一般企画、模擬店
export type ProjectForm = "stage" | "stall" | "exhibit" | "experience" | "other"; // 形態: ステージ、模擬店、展示、体験、その他
export type ProjectLocation = "b11" | "b12" | "b14" | "ground" | "stall_road" | "stage_area" | "other"; // 場所

export interface FestivalProject {
  projectId: string;
  name: string;            // 企画名
  organization: string;    // 団体名
  description: string;     // 内容紹介
  classification: ProjectClassification;
  form: ProjectForm;
  location: ProjectLocation;
  detailedLocation: string; // 詳細（例: 「11棟203教室」）
  isAccessible: boolean;    // バリアフリー対応
  tags: string[];           // 検索用タグ
  startTime?: string;       // ステージ企画などの開始時間
  endTime?: string;
}
