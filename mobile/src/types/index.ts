// 移動手段
export type MobilityType = 'wheelchair' | 'stroller' | 'cane' | 'walk' | 'other';

// 同行者
export type Companion = 'child' | 'elderly' | 'disability';

// 回避条件
export type AvoidCondition = 'stairs' | 'slope' | 'crowd' | 'dark';

// 希望条件
export type PreferCondition = 'restroom' | 'rest_area' | 'covered';

// ルート優先度
export type RoutePriority = 'shortest' | 'safest' | 'accessible';

// ユーザープロファイル
export interface UserProfile {
  userId: string;
  mobilityType: MobilityType;
  companions: Companion[];
  maxDistanceMeters: number;
  avoidConditions: AvoidCondition[];
  preferConditions: PreferCondition[];
  createdAt?: string;
  updatedAt?: string;
}

// ルート
export interface LatLng {
  lat: number;
  lng: number;
}

// OSMから取得したアクセシビリティ情報
export interface OsmAccessibility {
  wheelchairAccessible?: 'yes' | 'no' | 'limited' | 'unknown';
  hasSteps?: boolean;
  sidewalkWidth?: number;       // メートル
  kerbHeight?: number;          // cm
  surfaceType?: string;         // paved, unpaved, cobblestone 等
  tactilePaving?: boolean;
}

// 勾配の警告レベル
export type SlopeWarningLevel = 'safe' | 'caution' | 'dangerous';

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
  transitDetail?: TransitDetail;
  slopeGradient?: number;              // 平均勾配（%）
  maxSlopeGradient?: number;           // 最大勾配（%）
  slopeWarningLevel?: SlopeWarningLevel;
  osmAccessibility?: OsmAccessibility;
}

// 急勾配区間
export interface SteepSection {
  startLocation: LatLng;
  endLocation: LatLng;
  gradientPercent: number;
  distanceMeters: number;
}

// ルートの高低差プロファイル
export interface ElevationProfile {
  totalAscentMeters: number;
  totalDescentMeters: number;
  maxGradientPercent: number;
  steepSections: SteepSection[];
}

// OSMバリア情報
export interface OsmBarrier {
  type: 'steps' | 'kerb' | 'narrow_passage' | 'no_wheelchair';
  location: LatLng;
  description: string;
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

export interface RouteRequest {
  origin: LatLng;
  destination: LatLng;
  userProfileId: string;
  prioritize?: RoutePriority;
  mode?: TransportMode;  // default: 'walking'
}

export interface RouteResponse {
  routes: RouteResult[];
}

// スポット
export interface SpotSummary {
  spotId: string;
  name: string;
  category: string;
  location: LatLng;
  distanceMeters: number;
  accessibilityScore: number;
  wheelchairAccessible: boolean;
}

export interface SpotDetail extends SpotSummary {
  address: string;
  phoneNumber?: string;
  openingHours?: string[];
  hasElevator: boolean;
  hasAccessibleRestroom: boolean;
  hasAutomaticDoor: boolean;
  description?: string;
}

// チャット
export interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
}

export interface ChatResponse {
  reply: string;
  suggestedAction?: string;
  extractedNeeds?: Record<string, unknown>;
}

// ラベル定義
export const MOBILITY_LABELS: Record<MobilityType, string> = {
  wheelchair: '車椅子',
  stroller: 'ベビーカー',
  cane: '杖',
  walk: '徒歩',
  other: 'その他',
};

export const COMPANION_LABELS: Record<Companion, string> = {
  child: '子ども',
  elderly: '高齢者',
  disability: '障がい者',
};

export const AVOID_LABELS: Record<AvoidCondition, string> = {
  stairs: '階段',
  slope: '急な坂道',
  crowd: '混雑',
  dark: '暗い道',
};

export const PREFER_LABELS: Record<PreferCondition, string> = {
  restroom: 'トイレ',
  rest_area: '休憩所',
  covered: '屋根あり',
};

// 交通手段
export type TransportMode = 'walking' | 'transit' | 'driving' | 'bicycling';

// 乗換の詳細情報
export interface TransitDetail {
  lineName: string;        // 路線名（例: "山手線", "東京メトロ銀座線"）
  lineShortName?: string;  // 短縮名
  lineColor?: string;      // 路線カラー（例: "#80C241"）
  vehicleType: 'train' | 'subway' | 'bus' | 'tram' | 'ferry' | 'other';
  departureStop: string;   // 乗車駅/停留所
  arrivalStop: string;     // 降車駅/停留所
  departureTime?: string;  // 発車時刻
  arrivalTime?: string;    // 到着時刻
  numStops: number;        // 停車駅数
  headSign?: string;       // 行先表示
}

// 経由地点（乗換ポイント）
export interface WaypointLeg {
  legIndex: number;
  mode: TransportMode;
  origin: LatLng;
  destination: LatLng;
  originName: string;
  destinationName: string;
  distanceMeters: number;
  durationMinutes: number;
  steps: RouteStep[];
  transitDetails?: TransitDetail[];  // transit mode の場合のみ
}

// マルチモーダルルート結果
export interface MultiModalRoute {
  routeId: string;
  totalDistanceMeters: number;
  totalDurationMinutes: number;
  departureTime?: string;
  arrivalTime?: string;
  accessibilityScore: number;
  legs: WaypointLeg[];
  warnings: string[];
  fare?: string;  // 運賃
  elevationProfile?: ElevationProfile;
  osmBarriers?: OsmBarrier[];
}
