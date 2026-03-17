/**
 * 歩行空間ネットワークデータサービス
 * 国土交通省の歩行空間ネットワークデータ（CKAN）からバリアフリー情報を取得する
 *
 * リアルタイムAPIがないため、GeoJSONファイルをダウンロードし
 * メモリ上でキャッシュ・空間検索を行う
 */

// --- 型定義 ---

/** 歩行空間ネットワークのリンク（経路セグメント） */
interface HokoukukanLink {
  /** リンクID */
  linkId: string;
  /** 座標配列 [lng, lat] ペア（GeoJSON形式） */
  coordinates: Array<[number, number]>;
  /** 距離（メートル） */
  distance: number;
  /** 幅員区分コード (1=<1m, 2=1-2m, 3=2-3m, 4=>3m) */
  width: number;
  /** 勾配区分コード (1=<5%, 2=5-8%, 3=>8%) */
  slope: number;
  /** 段差区分コード (0=なし, 1=<2cm, 2=>2cm) */
  levelDiff: number;
  /** 経路種別 (1=一般道, 6=階段・スロープ) */
  routeType: number;
  /** 点字ブロックの有無 */
  hasBraileTile: boolean;
  /** エレベーターの有無 */
  hasElevator: boolean;
  /** 屋根の有無 */
  hasRoof: boolean;
  /** 信号機の有無 */
  hasTrafficSignal: boolean;
}

/** アクセシビリティ情報（変換済み） */
export interface HokoukukanAccessibility {
  /** 推定幅員（メートル） */
  widthMeters: number;
  /** 推定勾配（パーセント） */
  slopePercent: number;
  /** 推定段差高さ（センチメートル） */
  stepHeightCm: number;
  /** 路面種別 */
  surfaceType: string;
  /** 点字ブロックの有無 */
  hasBraileTile: boolean;
  /** エレベーターの有無 */
  hasElevator: boolean;
  /** 屋根の有無 */
  hasRoof: boolean;
  /** 階段・スロープかどうか */
  isStairsOrRamp: boolean;
  /** 信号機の有無 */
  hasTrafficSignal: boolean;
}

// --- 定数 ---

/** 主要エリアのCKANデータセットIDマッピング */
const AREA_DATASET_IDS: Record<string, string> = {
  shibuya: 'shibuya-hokoukukan',
  shinjuku: 'shinjuku-hokoukukan',
  ueno: 'ueno-hokoukukan',
  ikebukuro: 'ikebukuro-hokoukukan',
  tokyo_station: 'tokyo-station-hokoukukan',
};

/** エリアのバウンディングボックス定義 */
const AREA_BOUNDS: Record<
  string,
  { minLat: number; maxLat: number; minLng: number; maxLng: number }
> = {
  shibuya: { minLat: 35.654, maxLat: 35.664, minLng: 139.694, maxLng: 139.71 },
  shinjuku: {
    minLat: 35.685,
    maxLat: 35.698,
    minLng: 139.69,
    maxLng: 139.71,
  },
  ueno: { minLat: 35.708, maxLat: 35.718, minLng: 139.768, maxLng: 139.78 },
  ikebukuro: {
    minLat: 35.726,
    maxLat: 35.736,
    minLng: 139.706,
    maxLng: 139.718,
  },
  tokyo_station: {
    minLat: 35.676,
    maxLat: 35.686,
    minLng: 139.762,
    maxLng: 139.772,
  },
};

/** CKAN APIのベースURL */
const CKAN_BASE_URL = 'https://ckan.hokonavi.go.jp/api/3/action/package_show';

/** APIタイムアウト（ミリ秒） */
const FETCH_TIMEOUT_MS = 30000;

// --- キャッシュ ---

/** エリア名 → リンクデータのキャッシュ */
const dataCache = new Map<string, HokoukukanLink[]>();

// --- CKANレスポンス型 ---

/** CKANリソースの型 */
interface CkanResource {
  format: string;
  name: string;
  url: string;
}

/** CKANパッケージレスポンスの型 */
interface CkanPackageResponse {
  success: boolean;
  result: {
    resources: CkanResource[];
  };
}

/** GeoJSON Feature の型 */
interface GeoJsonFeature {
  type: 'Feature';
  properties: Record<string, unknown>;
  geometry: {
    type: string;
    coordinates: Array<[number, number]> | [number, number];
  };
}

/** GeoJSON FeatureCollection の型 */
interface GeoJsonFeatureCollection {
  type: 'FeatureCollection';
  features: GeoJsonFeature[];
}

// --- ユーティリティ ---

/**
 * 2点間の距離を簡易計算する（メートル）
 * 緯度経度差をメートルに近似変換
 * @param lat1 地点1の緯度
 * @param lng1 地点1の経度
 * @param lat2 地点2の緯度
 * @param lng2 地点2の経度
 * @returns 距離（メートル）
 */
function haversineDistance(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number
): number {
  const dLat = (lat2 - lat1) * 111111;
  const dLng =
    (lng2 - lng1) * 111111 * Math.cos((lat1 * Math.PI) / 180);
  return Math.sqrt(dLat * dLat + dLng * dLng);
}

/**
 * GeoJSON Feature からリンクデータをパースする
 * @param feature GeoJSON Feature
 * @returns パースされたリンクデータ（無効な場合はnull）
 */
function parseFeatureToLink(feature: GeoJsonFeature): HokoukukanLink | null {
  const props = feature.properties;
  const geom = feature.geometry;

  // LineString ジオメトリのみ対象
  if (geom.type !== 'LineString') {
    return null;
  }

  const coordinates = geom.coordinates as Array<[number, number]>;

  return {
    linkId: String(props['link_id'] ?? props['リンクID'] ?? ''),
    coordinates,
    distance: Number(props['distance'] ?? props['距離'] ?? 0),
    width: Number(props['width'] ?? props['幅員'] ?? 0),
    slope: Number(props['slope'] ?? props['勾配'] ?? 0),
    levelDiff: Number(props['level_diff'] ?? props['段差'] ?? 0),
    routeType: Number(props['route_type'] ?? props['経路種別'] ?? 1),
    hasBraileTile: Boolean(
      props['braile_tile'] ?? props['点字ブロック'] ?? false
    ),
    hasElevator: Boolean(
      props['elevator'] ?? props['エレベーター'] ?? false
    ),
    hasRoof: Boolean(props['roof'] ?? props['屋根'] ?? false),
    hasTrafficSignal: Boolean(
      props['traffic_signal'] ?? props['信号機'] ?? false
    ),
  };
}

// --- メイン関数 ---

/**
 * CKANカタログから歩行空間ネットワークデータを取得する
 * 結果はエリア名でキャッシュされる
 * @param areaName エリア名（shibuya, shinjuku, ueno, ikebukuro, tokyo_station）
 * @returns リンクデータの配列（失敗時は空配列）
 */
async function fetchHokoukukanData(
  areaName: string
): Promise<HokoukukanLink[]> {
  // キャッシュチェック
  const cached = dataCache.get(areaName);
  if (cached) {
    return cached;
  }

  const datasetId = AREA_DATASET_IDS[areaName];
  if (!datasetId) {
    console.warn(`未対応のエリア: ${areaName}`);
    return [];
  }

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

  try {
    // CKANパッケージ情報を取得
    const packageUrl = `${CKAN_BASE_URL}?id=${datasetId}`;
    const packageResponse = await fetch(packageUrl, {
      signal: controller.signal,
    });

    if (!packageResponse.ok) {
      console.warn(
        `CKANパッケージ取得エラー: ${packageResponse.status} (${areaName})`
      );
      return [];
    }

    const packageData =
      (await packageResponse.json()) as CkanPackageResponse;

    if (!packageData.success) {
      console.warn(`CKANパッケージレスポンスエラー: ${areaName}`);
      return [];
    }

    // GeoJSON形式かつリンクデータのリソースを検索
    const linkResource = packageData.result.resources.find(
      (r) =>
        r.format.toUpperCase() === 'GEOJSON' &&
        r.name.toLowerCase().includes('link')
    );

    if (!linkResource) {
      console.warn(`リンクGeoJSONリソースが見つかりません: ${areaName}`);
      return [];
    }

    // GeoJSONファイルをダウンロード
    const geojsonResponse = await fetch(linkResource.url, {
      signal: controller.signal,
    });

    if (!geojsonResponse.ok) {
      console.warn(
        `GeoJSONダウンロードエラー: ${geojsonResponse.status} (${areaName})`
      );
      return [];
    }

    const geojsonData =
      (await geojsonResponse.json()) as GeoJsonFeatureCollection;

    // Featureをリンクデータに変換
    const links: HokoukukanLink[] = [];
    for (const feature of geojsonData.features) {
      const link = parseFeatureToLink(feature);
      if (link) {
        links.push(link);
      }
    }

    // キャッシュに保存
    dataCache.set(areaName, links);

    console.log(
      `歩行空間データ取得完了: ${areaName} (${links.length}件のリンク)`
    );
    return links;
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      console.warn(`歩行空間データ取得タイムアウト: ${areaName}`);
    } else {
      console.warn(`歩行空間データ取得失敗: ${areaName}`, error);
    }
    return [];
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * 指定地点の近傍にあるリンクを検索する
 * リンクのジオメトリ座標のいずれかが半径内にあればマッチとする
 * @param links リンクデータの配列
 * @param point 基準地点
 * @param radiusMeters 検索半径（メートル）
 * @returns 近傍のリンクデータ配列
 */
function findNearbyLinks(
  links: HokoukukanLink[],
  point: { lat: number; lng: number },
  radiusMeters: number
): HokoukukanLink[] {
  return links.filter((link) => {
    // リンクの座標のいずれかが半径内にあるかチェック
    return link.coordinates.some((coord) => {
      // GeoJSON座標は [lng, lat] の順
      const lng = coord[0];
      const lat = coord[1];
      const dist = haversineDistance(point.lat, point.lng, lat, lng);
      return dist <= radiusMeters;
    });
  });
}

/**
 * リンクデータをアクセシビリティ情報に変換する
 * コード値を実際の数値に変換する
 * @param link リンクデータ
 * @returns アクセシビリティ情報
 */
function convertToAccessibility(
  link: HokoukukanLink
): HokoukukanAccessibility {
  // 幅員コード → メートル
  const widthMap: Record<number, number> = {
    1: 0.5,
    2: 1.5,
    3: 2.5,
    4: 3.5,
  };

  // 勾配コード → パーセント
  const slopeMap: Record<number, number> = {
    1: 3,
    2: 6.5,
    3: 10,
  };

  // 段差コード → センチメートル
  const levelDiffMap: Record<number, number> = {
    0: 0,
    1: 1,
    2: 5,
  };

  return {
    widthMeters: widthMap[link.width] ?? 0,
    slopePercent: slopeMap[link.slope] ?? 0,
    stepHeightCm: levelDiffMap[link.levelDiff] ?? 0,
    surfaceType: 'paved',
    hasBraileTile: link.hasBraileTile,
    hasElevator: link.hasElevator,
    hasRoof: link.hasRoof,
    isStairsOrRamp: link.routeType === 6,
    hasTrafficSignal: link.hasTrafficSignal,
  };
}

/**
 * 座標からエリア名を判定する
 * 各エリアのバウンディングボックスに含まれるかチェック
 * @param lat 緯度
 * @param lng 経度
 * @returns エリア名（該当なしの場合はnull）
 */
function determineAreaFromCoords(
  lat: number,
  lng: number
): string | null {
  for (const [areaName, bounds] of Object.entries(AREA_BOUNDS)) {
    if (
      lat >= bounds.minLat &&
      lat <= bounds.maxLat &&
      lng >= bounds.minLng &&
      lng <= bounds.maxLng
    ) {
      return areaName;
    }
  }
  return null;
}

/**
 * 指定座標周辺の歩行空間アクセシビリティ情報を取得する
 * メインエントリーポイント。エリア判定 → データ取得 → 近傍検索 → 変換の一連の処理を行う
 * @param lat 緯度
 * @param lng 経度
 * @param radiusMeters 検索半径（メートル）
 * @returns アクセシビリティ情報の配列（エリア外や取得失敗時は空配列）
 */
export async function getHokoukukanAccessibility(
  lat: number,
  lng: number,
  radiusMeters: number
): Promise<HokoukukanAccessibility[]> {
  // エリア判定
  const areaName = determineAreaFromCoords(lat, lng);
  if (!areaName) {
    return [];
  }

  // データ取得（キャッシュあり）
  const links = await fetchHokoukukanData(areaName);
  if (links.length === 0) {
    return [];
  }

  // 近傍リンクを検索
  const nearbyLinks = findNearbyLinks(links, { lat, lng }, radiusMeters);

  // アクセシビリティ情報に変換
  return nearbyLinks.map(convertToAccessibility);
}
