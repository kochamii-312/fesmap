// Google Maps Platform API 呼び出しヘルパー

import { LatLng, RouteStep, RoutePriority, TransportMode, SpotCategory, SpotSummary, SpotDetail, AccessibilityInfo } from "../types";
import { defineString } from "firebase-functions/params";
import https from "https";

// Google Maps API キーは Firebase の環境変数で管理
// defineString は Cloud Functions v2 のパラメータ機能を使用
const googleMapsApiKey = defineString("GOOGLE_MAPS_API_KEY");

/**
 * Google Maps API キーを安全に取得する
 * defineString().value() が空文字列を返す場合に process.env にフォールバック
 */
const getApiKey = (): string => {
  let key = "";
  try {
    key = googleMapsApiKey.value();
  } catch {
    // defineString().value() がデプロイ外で失敗する場合がある
  }
  if (!key || key.trim().length === 0) {
    key = process.env.GOOGLE_MAPS_API_KEY ?? "";
  }
  if (!key || key.trim().length === 0) {
    throw new Error("GOOGLE_MAPS_API_KEY が設定されていません");
  }
  return key;
};

// ============================================================
// ジオコーディングキャッシュ（インメモリ、Cloud Functions インスタンス単位）
// ============================================================

interface GeocachEntry {
  location: LatLng;
  createdAt: number;
}

const GEOCODE_CACHE = new Map<string, GeocachEntry>();
const GEOCODE_CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24時間
const GEOCODE_CACHE_MAX_SIZE = 500;

const getFromGeocodeCache = (key: string): LatLng | null => {
  const entry = GEOCODE_CACHE.get(key);
  if (!entry) return null;
  if (Date.now() - entry.createdAt > GEOCODE_CACHE_TTL_MS) {
    GEOCODE_CACHE.delete(key);
    return null;
  }
  return entry.location;
};

const setGeocodeCache = (key: string, location: LatLng): void => {
  // サイズ上限を超えたら最も古いエントリを削除
  if (GEOCODE_CACHE.size >= GEOCODE_CACHE_MAX_SIZE) {
    const firstKey = GEOCODE_CACHE.keys().next().value;
    if (firstKey !== undefined) {
      GEOCODE_CACHE.delete(firstKey);
    }
  }
  GEOCODE_CACHE.set(key, { location, createdAt: Date.now() });
};

// ============================================================
// 内部ヘルパー
// ============================================================

/** HTTPSリクエストを送信してJSONレスポンスを取得する */
const fetchJson = async (url: string): Promise<unknown> => {
  return new Promise((resolve, reject) => {
    const req = https.get(url, (res) => {
      const statusCode = res.statusCode ?? 0;
      let data = "";
      res.on("data", (chunk: string) => {
        data += chunk;
      });
      res.on("end", () => {
        try {
          const parsed = JSON.parse(data);
          // HTTPステータスが異常でもGoogle APIはJSON本文を返すためパース結果を返す
          // ただし明らかなHTTPエラー（認証失敗等）の場合はエラーにする
          if (statusCode >= 400 && statusCode !== 200) {
            const errorMsg = (parsed as Record<string, unknown>).error_message ?? data.substring(0, 200);
            reject(new Error(`Google Maps API HTTPエラー (${statusCode}): ${errorMsg}`));
            return;
          }
          resolve(parsed);
        } catch (e) {
          reject(new Error(`JSONパースエラー (HTTP ${statusCode}): ${data.substring(0, 200)}`));
        }
      });
    });
    req.on("error", reject);
    req.setTimeout(15000, () => {
      req.destroy();
      reject(new Error("Google Maps APIリクエストがタイムアウトしました"));
    });
  });
};

/** Google Places APIのカテゴリをアプリのカテゴリにマッピング */
const mapPlaceTypeToCategory = (types: string[]): SpotCategory => {
  const typeSet = new Set(types);
  if (typeSet.has("toilet") || typeSet.has("restroom")) return "restroom";
  if (typeSet.has("park")) return "park";
  if (typeSet.has("restaurant")) return "restaurant";
  if (typeSet.has("cafe")) return "cafe";
  if (typeSet.has("parking")) return "parking";
  if (typeSet.has("elevator")) return "elevator";
  return "other";
};

/** アプリのカテゴリをGoogle Places APIのタイプにマッピング */
const mapCategoryToPlaceType = (category: SpotCategory): string => {
  const mapping: Record<SpotCategory, string> = {
    restroom: "restroom",
    rest_area: "park",
    restaurant: "restaurant",
    cafe: "cafe",
    park: "park",
    kids_space: "amusement_park",
    nursing_room: "hospital",
    elevator: "transit_station",
    parking: "parking",
    other: "point_of_interest",
  };
  return mapping[category];
};

/** ステップのHTML命令文から階段・坂道を判定する */
const detectStairs = (instruction: string): boolean => {
  const stairKeywords = ["階段", "stairs", "steps", "staircase", "stairway"];
  const lower = instruction.toLowerCase();
  return stairKeywords.some((kw) => lower.includes(kw));
};

/** ステップの命令文から坂道を判定する */
const detectSlope = (instruction: string): boolean => {
  const slopeKeywords = ["坂", "slope", "hill", "incline", "gradient", "上り", "下り"];
  const lower = instruction.toLowerCase();
  return slopeKeywords.some((kw) => lower.includes(kw));
};

/** 高低差から勾配を推定する（パーセント） */
const estimateSlopeGrade = (
  startElevation: number | undefined,
  endElevation: number | undefined,
  distanceMeters: number
): number | undefined => {
  if (startElevation === undefined || endElevation === undefined || distanceMeters === 0) {
    return undefined;
  }
  const elevationDiff = Math.abs(endElevation - startElevation);
  return Math.round((elevationDiff / distanceMeters) * 100 * 10) / 10;
};

// Google Directions APIレスポンスの型定義
interface DirectionsTransitDetail {
  line: {
    name?: string;
    short_name?: string;
    color?: string;
    vehicle?: { type: string };
  };
  departure_stop: { name: string };
  arrival_stop: { name: string };
  departure_time?: { text: string };
  arrival_time?: { text: string };
  num_stops: number;
  headsign?: string;
}

interface DirectionsStep {
  html_instructions: string;
  distance: { value: number };
  duration: { value: number };
  start_location: { lat: number; lng: number };
  end_location: { lat: number; lng: number };
  polyline: { points: string };
  travel_mode: string;
  maneuver?: string;
  transit_details?: DirectionsTransitDetail;
}

interface DirectionsLeg {
  distance: { value: number };
  duration: { value: number };
  steps: DirectionsStep[];
}

interface DirectionsRoute {
  legs: DirectionsLeg[];
  overview_polyline: { points: string };
  summary: string;
}

interface DirectionsResponse {
  status: string;
  routes: DirectionsRoute[];
  error_message?: string;
}

// Google Places APIレスポンスの型定義
interface PlaceResult {
  place_id: string;
  name: string;
  geometry: { location: { lat: number; lng: number } };
  types: string[];
  vicinity?: string;
  rating?: number;
  opening_hours?: { open_now: boolean };
}

interface NearbySearchResponse {
  status: string;
  results: PlaceResult[];
  error_message?: string;
}

interface PlaceDetailResult {
  place_id: string;
  name: string;
  formatted_address: string;
  geometry: { location: { lat: number; lng: number } };
  types: string[];
  formatted_phone_number?: string;
  website?: string;
  opening_hours?: {
    weekday_text?: string[];
    open_now?: boolean;
  };
  photos?: Array<{ photo_reference: string }>;
  wheelchair_accessible_entrance?: boolean;
  reviews?: Array<{ text: string }>;
}

interface PlaceDetailsResponse {
  status: string;
  result: PlaceDetailResult;
  error_message?: string;
}

// ============================================================
// 公開API
// ============================================================

/**
 * Google Maps Directions API でルートを検索する
 * alternatives=true で複数ルートを取得し、各ステップにアクセシビリティ情報を付与
 */
export const searchRoutes = async (
  origin: LatLng,
  destination: LatLng,
  _prioritize: RoutePriority,
  mode: TransportMode = "walking"
): Promise<{ steps: RouteStep[]; distanceMeters: number; durationSeconds: number }[]> => {
  const apiKey = getApiKey();
  let url =
    `https://maps.googleapis.com/maps/api/directions/json` +
    `?origin=${origin.lat},${origin.lng}` +
    `&destination=${destination.lat},${destination.lng}` +
    `&mode=${mode}` +
    `&alternatives=true` +
    `&language=ja` +
    `&key=${apiKey}`;

  // transit モードでは departure_time が必要
  if (mode === "transit") {
    url += `&departure_time=${Math.floor(Date.now() / 1000)}`;
  }

  const data = (await fetchJson(url)) as DirectionsResponse;

  if (data.status !== "OK") {
    throw new Error(`Directions APIエラー: ${data.status} - ${data.error_message ?? "不明"}`);
  }

  return data.routes.map((route) => {
    const leg = route.legs[0];
    const steps: RouteStep[] = leg.steps.map((step, index) => {
      const instruction = step.html_instructions.replace(/<[^>]*>/g, "");
      const hasStairs = detectStairs(instruction);
      const hasSlope = detectSlope(instruction);

      // transit モードの場合、transit_details をパースする
      let transitDetail = undefined;
      if (step.transit_details) {
        const td = step.transit_details;
        const vehicleType = td.line?.vehicle?.type?.toLowerCase() ?? "other";
        const vehicleMap: Record<string, "train" | "subway" | "bus" | "tram" | "ferry" | "other"> = {
          rail: "train",
          heavy_rail: "train",
          commuter_train: "train",
          subway: "subway",
          metro_rail: "subway",
          bus: "bus",
          tram: "tram",
          trolleybus: "bus",
          ferry: "ferry",
        };
        transitDetail = {
          lineName: td.line.name ?? "",
          lineShortName: td.line.short_name,
          lineColor: td.line.color,
          vehicleType: vehicleMap[vehicleType] ?? "other" as const,
          departureStop: td.departure_stop.name,
          arrivalStop: td.arrival_stop.name,
          departureTime: td.departure_time?.text,
          arrivalTime: td.arrival_time?.text,
          numStops: td.num_stops,
          headSign: td.headsign,
        };
      }

      return {
        stepId: `step_${index}`,
        instruction,
        distanceMeters: step.distance.value,
        durationSeconds: step.duration.value,
        startLocation: {
          lat: step.start_location.lat,
          lng: step.start_location.lng,
        },
        endLocation: {
          lat: step.end_location.lat,
          lng: step.end_location.lng,
        },
        polyline: step.polyline.points,
        hasStairs,
        hasSlope,
        // 高低差データが取得できない場合、キーワードベースのデフォルト勾配を設定
        // 「急」「steep」等を含む場合は急勾配(10%)、それ以外は中程度(6%)と推定
        slopeGrade: hasSlope
          ? (estimateSlopeGrade(undefined, undefined, step.distance.value) ??
            (instruction.includes("急") || instruction.toLowerCase().includes("steep") ? 10 : 6))
          : undefined,
        surfaceType: "paved" as const,
        transitDetail,
      };
    });

    return {
      steps,
      distanceMeters: leg.distance.value,
      durationSeconds: leg.duration.value,
    };
  });
};

/**
 * Google Maps Places API (Nearby Search) で周辺スポットを検索する
 */
export const searchNearbyPlaces = async (
  lat: number,
  lng: number,
  radiusMeters: number,
  category?: SpotCategory
): Promise<SpotSummary[]> => {
  const apiKey = getApiKey();
  let url =
    `https://maps.googleapis.com/maps/api/place/nearbysearch/json` +
    `?location=${lat},${lng}` +
    `&radius=${radiusMeters}` +
    `&language=ja` +
    `&key=${apiKey}`;

  if (category) {
    url += `&type=${mapCategoryToPlaceType(category)}`;
  }

  const data = (await fetchJson(url)) as NearbySearchResponse;

  if (data.status !== "OK" && data.status !== "ZERO_RESULTS") {
    throw new Error(`Places APIエラー: ${data.status} - ${data.error_message ?? "不明"}`);
  }

  return data.results.map((place) => {
    const placeLat = place.geometry.location.lat;
    const placeLng = place.geometry.location.lng;
    // 2点間の距離を簡易計算（ハバーサイン）
    const distanceMeters = Math.round(haversineDistance(lat, lng, placeLat, placeLng));

    return {
      spotId: place.place_id,
      name: place.name,
      category: category ?? mapPlaceTypeToCategory(place.types),
      location: { lat: placeLat, lng: placeLng },
      accessibilityScore: 50, // デフォルトスコア（詳細取得時に計算）
      distanceMeters,
      distanceFromRoute: distanceMeters,
      wheelchairAccessible: false,
    };
  });
};

/**
 * Google Maps Place Details API でスポット詳細を取得する
 */
export const getPlaceDetails = async (placeId: string): Promise<SpotDetail | null> => {
  const apiKey = getApiKey();
  const fields = [
    "place_id",
    "name",
    "formatted_address",
    "geometry",
    "type",
    "formatted_phone_number",
    "website",
    "opening_hours",
    "photos",
    "wheelchair_accessible_entrance",
    "reviews",
  ].join(",");

  const url =
    `https://maps.googleapis.com/maps/api/place/details/json` +
    `?place_id=${placeId}` +
    `&fields=${fields}` +
    `&language=ja` +
    `&key=${apiKey}`;

  const data = (await fetchJson(url)) as PlaceDetailsResponse;

  if (data.status !== "OK") {
    return null;
  }

  const place = data.result;

  // レビューからアクセシビリティ情報を推測
  const accessibility = extractAccessibilityFromReviews(place);

  // 写真URLの生成
  const photoUrls = (place.photos ?? []).slice(0, 5).map(
    (photo) =>
      `https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photo_reference=${photo.photo_reference}&key=${apiKey}`
  );

  return {
    spotId: place.place_id,
    name: place.name,
    description: "",
    category: mapPlaceTypeToCategory(place.types ?? []),
    location: {
      lat: place.geometry.location.lat,
      lng: place.geometry.location.lng,
    },
    address: place.formatted_address ?? "",
    accessibilityScore: 50,
    accessibility,
    photoUrls,
    openingHours: place.opening_hours?.weekday_text?.join("\n"),
    phoneNumber: place.formatted_phone_number,
    website: place.website,
  };
};

/**
 * ジオコーディング（住所から座標を取得）
 */
export const geocode = async (address: string): Promise<LatLng | null> => {
  // キャッシュチェック
  const cacheKey = address.trim().toLowerCase();
  const cached = getFromGeocodeCache(cacheKey);
  if (cached) {
    return cached;
  }

  const apiKey = getApiKey();
  const url =
    `https://maps.googleapis.com/maps/api/geocode/json` +
    `?address=${encodeURIComponent(address)}` +
    `&language=ja` +
    `&region=jp` +
    `&key=${apiKey}`;

  const data = (await fetchJson(url)) as {
    status: string;
    results: Array<{ geometry: { location: { lat: number; lng: number } } }>;
    error_message?: string;
  };

  // REQUEST_DENIED や OVER_QUERY_LIMIT はサーバー側の問題なのでエラーとして伝播
  if (data.status === "REQUEST_DENIED" || data.status === "OVER_QUERY_LIMIT") {
    throw new Error(`Geocoding APIエラー: ${data.status} - ${data.error_message ?? "APIキーの設定を確認してください"}`);
  }

  if (data.status !== "OK" || !data.results || data.results.length === 0) {
    return null;
  }

  const location = data.results[0].geometry.location;
  const result = { lat: location.lat, lng: location.lng };

  // キャッシュに保存
  setGeocodeCache(cacheKey, result);

  return result;
};

/**
 * リバースジオコーディング（座標から住所を取得）
 */
export const reverseGeocode = async (location: LatLng): Promise<string | null> => {
  const apiKey = getApiKey();
  const url =
    `https://maps.googleapis.com/maps/api/geocode/json` +
    `?latlng=${location.lat},${location.lng}` +
    `&language=ja` +
    `&key=${apiKey}`;

  const data = (await fetchJson(url)) as {
    status: string;
    results: Array<{ formatted_address: string }>;
    error_message?: string;
  };

  // REQUEST_DENIED や OVER_QUERY_LIMIT はサーバー側の問題なのでエラーとして伝播
  if (data.status === "REQUEST_DENIED" || data.status === "OVER_QUERY_LIMIT") {
    throw new Error(`Geocoding APIエラー: ${data.status} - ${data.error_message ?? "APIキーの設定を確認してください"}`);
  }

  if (data.status !== "OK" || !data.results || data.results.length === 0) {
    return null;
  }

  return data.results[0].formatted_address;
};

// ============================================================
// ユーティリティ
// ============================================================

/** ハバーサインの公式で2点間の距離（メートル）を計算 */
const haversineDistance = (lat1: number, lng1: number, lat2: number, lng2: number): number => {
  const R = 6371000; // 地球の半径（メートル）
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
};

/**
 * Google Places Autocomplete API で場所の候補を検索する
 */
export const placesAutocomplete = async (
  input: string,
  language = "ja",
  components = "country:jp"
): Promise<Array<{ description: string; place_id: string }>> => {
  const apiKey = getApiKey();
  const url =
    `https://maps.googleapis.com/maps/api/place/autocomplete/json` +
    `?input=${encodeURIComponent(input)}` +
    `&language=${language}` +
    `&components=${components}` +
    `&key=${apiKey}`;

  const data = (await fetchJson(url)) as {
    status: string;
    predictions: Array<{ description: string; place_id: string }>;
    error_message?: string;
  };

  if (data.status !== "OK" && data.status !== "ZERO_RESULTS") {
    throw new Error(`Places Autocomplete APIエラー: ${data.status} - ${data.error_message ?? "不明"}`);
  }

  return (data.predictions ?? []).slice(0, 5).map((p) => ({
    description: p.description,
    place_id: p.place_id,
  }));
};

/** レビューテキストからアクセシビリティ情報を推測する */
const extractAccessibilityFromReviews = (place: PlaceDetailResult): AccessibilityInfo => {
  const reviews = (place.reviews ?? []).map((r) => r.text).join(" ");
  const lower = reviews.toLowerCase();

  return {
    wheelchairAccessible: (place.wheelchair_accessible_entrance ?? false) || lower.includes("車椅子") || lower.includes("wheelchair") || lower.includes("バリアフリー"),
    hasElevator: lower.includes("エレベーター") || lower.includes("elevator"),
    hasAccessibleRestroom: lower.includes("多目的トイレ") || lower.includes("バリアフリートイレ") || lower.includes("accessible restroom"),
    hasBabyChangingStation: lower.includes("おむつ") || lower.includes("おむつ替え") || lower.includes("baby changing"),
    hasNursingRoom: lower.includes("授乳") || lower.includes("nursing room"),
    floorType: lower.includes("階段") || lower.includes("steps") ? "steps" : "flat",
    notes: [],
  };
};
