// Yahoo! Open Local Platform (YOLP) API 呼び出しヘルパー

import { SpotSummary, SpotCategory } from "../types";
import { defineString } from "firebase-functions/params";
import https from "https";

// YOLP App ID は Firebase の環境変数で管理
const yolpAppId = defineString("YOLP_APP_ID");

/**
 * YOLP App ID を安全に取得する
 */
const getAppId = (): string => {
  let appId = "";
  try {
    appId = yolpAppId.value();
  } catch {
    // defineString().value() がデプロイ外で失敗する場合がある
  }
  if (!appId || appId.trim().length === 0) {
    appId = process.env.YOLP_APP_ID ?? "";
  }
  if (!appId || appId.trim().length === 0) {
    throw new Error("YOLP_APP_ID が設定されていません");
  }
  return appId;
};

// YOLP レスポンスの型定義
interface YOLPFeature {
  Id: string;
  Name?: string;
  Geometry?: {
    Coordinates?: string; // "経度,緯度"
  };
  Category?: string[];
  Property?: {
    Address?: string;
    Tel1?: string;
    Gid?: string;
  };
}

interface YOLPResponse {
  Feature?: YOLPFeature[];
  ResultInfo?: {
    Count: number;
    Total: number;
  };
}

/** HTTPSリクエストを送信してJSONレスポンスを取得する */
const fetchJson = async (url: string): Promise<unknown> => {
  return new Promise((resolve, reject) => {
    const req = https.get(url, (res) => {
      let data = "";
      res.on("data", (chunk: string) => {
        data += chunk;
      });
      res.on("end", () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(new Error(`JSONパースエラー: ${data.substring(0, 200)}`));
        }
      });
    });
    req.on("error", reject);
    req.setTimeout(15000, () => {
      req.destroy();
      reject(new Error("YOLP APIリクエストがタイムアウトしました"));
    });
  });
};

/** YOLPのカテゴリをアプリのカテゴリにマッピング */
const mapYolpCategory = (categories: string[] | undefined): SpotCategory => {
  if (!categories || categories.length === 0) return "other";
  const category = categories[0];
  if (category.includes("カフェ") || category.includes("喫茶")) return "cafe";
  if (category.includes("トイレ")) return "restroom";
  if (category.includes("レストラン") || category.includes("食堂") || category.includes("料理")) return "restaurant";
  if (category.includes("公園")) return "park";
  if (category.includes("駐車")) return "parking";
  if (category.includes("エレベーター")) return "elevator";
  if (category.includes("授乳") || category.includes("ベビー")) return "nursing_room";
  return "other";
};

/** ハバーサインの公式で2点間の距離（メートル）を計算 */
const haversineDistance = (lat1: number, lng1: number, lat2: number, lng2: number): number => {
  const R = 6371000;
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
 * YOLP ローカルサーチ API で周辺スポットを検索する
 */
export const searchNearbyYOLP = async (
  lat: number,
  lng: number,
  radiusMeters: number,
  query?: string
): Promise<SpotSummary[]> => {
  const appId = getAppId();

  // YOLP の dist パラメータは km 単位（範囲: 0.001〜50）
  const distKm = Math.min(radiusMeters / 1000, 50);

  const params = new URLSearchParams({
    appid: appId,
    lat: String(lat),
    lon: String(lng),
    dist: String(distKm),
    output: "json",
    sort: "dist",
    results: "20",
  });

  if (query) {
    params.set("query", query);
  }

  const url = `https://map.yahooapis.jp/search/local/V1/localSearch?${params.toString()}`;
  const data = (await fetchJson(url)) as YOLPResponse;

  if (!data.Feature) {
    return [];
  }

  return data.Feature.reduce<SpotSummary[]>((spots, feature) => {
    if (!feature.Name || !feature.Geometry?.Coordinates) {
      return spots;
    }

    const coordinates = feature.Geometry.Coordinates.split(",").map(Number);
    if (coordinates.length !== 2 || coordinates.some(isNaN)) {
      return spots;
    }

    // YOLP の座標は「経度,緯度」の順
    const spotLng = coordinates[0];
    const spotLat = coordinates[1];

    const distanceFromRoute = Math.round(haversineDistance(lat, lng, spotLat, spotLng));

    spots.push({
      spotId: feature.Property?.Gid ?? `yolp_${feature.Id}`,
      name: feature.Name,
      category: mapYolpCategory(feature.Category),
      location: { lat: spotLat, lng: spotLng },
      accessibilityScore: 50,
      distanceFromRoute,
    });

    return spots;
  }, []);
};
