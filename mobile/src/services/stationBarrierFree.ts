// 駅バリアフリー情報サービス
// ODPT（公共交通オープンデータ）APIを利用した駅のアクセシビリティ情報取得

/** 駅のアクセシビリティ情報 */
export interface StationAccessibility {
  stationName: string;
  operatorName: string;
  hasElevator: boolean;
  hasEscalator: boolean;
  hasAccessibleToilet: boolean;
  hasWheelchairRamp: boolean;
  hasTactilePaving: boolean;
  barrierFreeRoute: boolean; // 入口からホームまでのバリアフリールート有無
  note?: string;
}

// ODPT APIベースURL・認証キー
const ODPT_API_BASE = 'https://api.odpt.org/api/v4/';
const ODPT_API_KEY = process.env.EXPO_PUBLIC_ODPT_API_KEY ?? '';

// タイムアウト（ミリ秒）
const REQUEST_TIMEOUT_MS = 10_000;

// キャッシュ（座標グリッド0.01度単位）
const nearbyCache = new Map<string, { data: StationAccessibility[]; timestamp: number }>();
const CACHE_TTL_MS = 5 * 60 * 1000; // 5分

/**
 * 座標をグリッドキーに変換（0.01度単位）
 */
function toGridKey(lat: number, lng: number): string {
  const gridLat = Math.round(lat / 0.01) * 0.01;
  const gridLng = Math.round(lng / 0.01) * 0.01;
  return `${gridLat.toFixed(2)}_${gridLng.toFixed(2)}`;
}

// -------------------------------------------------------
// 主要駅の組み込みバリアフリーデータ（APIフォールバック用）
// -------------------------------------------------------
const BUILTIN_STATIONS: StationAccessibility[] = [
  {
    stationName: '東京駅',
    operatorName: 'JR東日本',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: true,
    hasWheelchairRamp: true,
    hasTactilePaving: true,
    barrierFreeRoute: true,
  },
  {
    stationName: '新宿駅',
    operatorName: 'JR東日本',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: true,
    hasWheelchairRamp: true,
    hasTactilePaving: true,
    barrierFreeRoute: true,
  },
  {
    stationName: '渋谷駅',
    operatorName: 'JR東日本',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: true,
    hasWheelchairRamp: false,
    hasTactilePaving: true,
    barrierFreeRoute: false,
    note: '駅構造が複雑なため一部ルートでバリアフリー経路なし',
  },
  {
    stationName: '池袋駅',
    operatorName: 'JR東日本',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: true,
    hasWheelchairRamp: true,
    hasTactilePaving: true,
    barrierFreeRoute: true,
  },
  {
    stationName: '上野駅',
    operatorName: 'JR東日本',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: true,
    hasWheelchairRamp: true,
    hasTactilePaving: true,
    barrierFreeRoute: true,
  },
  {
    stationName: '品川駅',
    operatorName: 'JR東日本',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: true,
    hasWheelchairRamp: true,
    hasTactilePaving: true,
    barrierFreeRoute: true,
  },
  {
    stationName: '秋葉原駅',
    operatorName: 'JR東日本',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: true,
    hasWheelchairRamp: true,
    hasTactilePaving: true,
    barrierFreeRoute: true,
  },
  {
    stationName: '有楽町駅',
    operatorName: 'JR東日本',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: true,
    hasWheelchairRamp: true,
    hasTactilePaving: true,
    barrierFreeRoute: true,
  },
  {
    stationName: '浜松町駅',
    operatorName: 'JR東日本',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: true,
    hasWheelchairRamp: true,
    hasTactilePaving: true,
    barrierFreeRoute: true,
  },
  {
    stationName: '田町駅',
    operatorName: 'JR東日本',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: true,
    hasWheelchairRamp: true,
    hasTactilePaving: true,
    barrierFreeRoute: true,
  },
  {
    stationName: '六本木駅',
    operatorName: '東京メトロ',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: true,
    hasWheelchairRamp: false,
    hasTactilePaving: true,
    barrierFreeRoute: false,
    note: '地下深い駅のためバリアフリー経路が限定的',
  },
  {
    stationName: '銀座駅',
    operatorName: '東京メトロ',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: true,
    hasWheelchairRamp: true,
    hasTactilePaving: true,
    barrierFreeRoute: true,
  },
  {
    stationName: '表参道駅',
    operatorName: '東京メトロ',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: true,
    hasWheelchairRamp: true,
    hasTactilePaving: true,
    barrierFreeRoute: true,
  },
  {
    stationName: '大手町駅',
    operatorName: '東京メトロ',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: true,
    hasWheelchairRamp: true,
    hasTactilePaving: true,
    barrierFreeRoute: true,
    note: '出口が多数あるため利用する路線に注意',
  },
  {
    stationName: '中野駅',
    operatorName: 'JR東日本',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: true,
    hasWheelchairRamp: true,
    hasTactilePaving: true,
    barrierFreeRoute: true,
  },
  {
    stationName: '吉祥寺駅',
    operatorName: 'JR東日本',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: true,
    hasWheelchairRamp: true,
    hasTactilePaving: true,
    barrierFreeRoute: true,
  },
  {
    stationName: '横浜駅',
    operatorName: 'JR東日本',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: true,
    hasWheelchairRamp: true,
    hasTactilePaving: true,
    barrierFreeRoute: true,
  },
  {
    stationName: '新橋駅',
    operatorName: 'JR東日本',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: true,
    hasWheelchairRamp: true,
    hasTactilePaving: true,
    barrierFreeRoute: true,
  },
  {
    stationName: '神田駅',
    operatorName: 'JR東日本',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: false,
    hasWheelchairRamp: true,
    hasTactilePaving: true,
    barrierFreeRoute: true,
    note: '多機能トイレは改札外のみ',
  },
  {
    stationName: '飯田橋駅',
    operatorName: 'JR東日本',
    hasElevator: true,
    hasEscalator: true,
    hasAccessibleToilet: true,
    hasWheelchairRamp: true,
    hasTactilePaving: true,
    barrierFreeRoute: true,
  },
];

// ODPT APIレスポンスの型定義（必要なフィールドのみ）
interface OdptStationResponse {
  'odpt:stationName'?: string;
  'dc:title'?: string;
  'odpt:operator'?: string;
  'odpt:stationFacility'?: string;
}

interface OdptFacilityResponse {
  'odpt:barrierfreeFacility'?: OdptBarrierFreeFacility[];
}

interface OdptBarrierFreeFacility {
  'odpt:barrierfreeFacilityType'?: string;
  '@type'?: string;
}

/**
 * ODPT APIレスポンスから駅名を抽出
 */
function extractStationName(station: OdptStationResponse): string {
  return station['odpt:stationName'] ?? station['dc:title'] ?? '不明';
}

/**
 * ODPT APIレスポンスから事業者名を抽出
 */
function extractOperatorName(station: OdptStationResponse): string {
  const operator = station['odpt:operator'] ?? '';
  // odpt.Operator:JR-East のような形式からラベルを生成
  if (operator.includes('JR-East')) return 'JR東日本';
  if (operator.includes('TokyoMetro')) return '東京メトロ';
  if (operator.includes('Toei')) return '都営地下鉄';
  if (operator.includes('Tokyu')) return '東急電鉄';
  if (operator.includes('Odakyu')) return '小田急電鉄';
  if (operator.includes('Keio')) return '京王電鉄';
  if (operator.includes('Seibu')) return '西武鉄道';
  if (operator.includes('Tobu')) return '東武鉄道';
  return operator;
}

/**
 * バリアフリー施設情報をパース
 */
function parseFacilities(facilities: OdptBarrierFreeFacility[]): Partial<StationAccessibility> {
  const result: Partial<StationAccessibility> = {
    hasElevator: false,
    hasEscalator: false,
    hasAccessibleToilet: false,
    hasWheelchairRamp: false,
    hasTactilePaving: false,
    barrierFreeRoute: false,
  };

  for (const facility of facilities) {
    const type = facility['odpt:barrierfreeFacilityType'] ?? facility['@type'] ?? '';
    if (type.includes('Elevator')) result.hasElevator = true;
    if (type.includes('Escalator')) result.hasEscalator = true;
    if (type.includes('Toilet') || type.includes('Restroom')) result.hasAccessibleToilet = true;
    if (type.includes('Ramp') || type.includes('Slope')) result.hasWheelchairRamp = true;
    if (type.includes('TactilePaving') || type.includes('Braille')) result.hasTactilePaving = true;
    if (type.includes('Link') || type.includes('Route')) result.barrierFreeRoute = true;
  }

  return result;
}

/**
 * タイムアウト付きfetch
 */
async function fetchWithTimeout(url: string, timeoutMs: number): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { signal: controller.signal });
    return response;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * 指定座標周辺の駅バリアフリー情報を検索
 *
 * ODPT APIキーが設定されていない場合は組み込みデータセットにフォールバック。
 * 結果は座標グリッド（0.01度）単位でキャッシュされる。
 *
 * @param lat - 緯度
 * @param lng - 経度
 * @param radiusMeters - 検索半径（メートル）
 * @returns 周辺駅のアクセシビリティ情報配列
 */
export async function searchNearbyStations(
  lat: number,
  lng: number,
  radiusMeters: number,
): Promise<StationAccessibility[]> {
  // キャッシュチェック
  const cacheKey = toGridKey(lat, lng);
  const cached = nearbyCache.get(cacheKey);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL_MS) {
    return cached.data;
  }

  // APIキー未設定の場合は組み込みデータを返す
  if (!ODPT_API_KEY) {
    return BUILTIN_STATIONS;
  }

  try {
    const url =
      `${ODPT_API_BASE}places/odpt:Station` +
      `?lat=${lat}&lon=${lng}&radius=${radiusMeters}` +
      `&acl:consumerKey=${ODPT_API_KEY}`;

    const response = await fetchWithTimeout(url, REQUEST_TIMEOUT_MS);
    if (!response.ok) {
      console.warn(`ODPT API エラー: ${response.status}`);
      return BUILTIN_STATIONS;
    }

    const stations: OdptStationResponse[] = await response.json();
    if (!Array.isArray(stations) || stations.length === 0) {
      return BUILTIN_STATIONS;
    }

    // 各駅の施設情報を取得
    const results: StationAccessibility[] = [];
    for (const station of stations) {
      const stationName = extractStationName(station);
      const operatorName = extractOperatorName(station);

      // 施設情報URLがあればフェッチ
      let facilityInfo: Partial<StationAccessibility> = {};
      const facilityUrl = station['odpt:stationFacility'];
      if (facilityUrl) {
        try {
          const facilityFullUrl = facilityUrl.startsWith('http')
            ? `${facilityUrl}?acl:consumerKey=${ODPT_API_KEY}`
            : `${ODPT_API_BASE}${facilityUrl}?acl:consumerKey=${ODPT_API_KEY}`;
          const facResponse = await fetchWithTimeout(facilityFullUrl, REQUEST_TIMEOUT_MS);
          if (facResponse.ok) {
            const facData: OdptFacilityResponse[] = await facResponse.json();
            if (Array.isArray(facData) && facData.length > 0) {
              const facilities = facData[0]['odpt:barrierfreeFacility'] ?? [];
              facilityInfo = parseFacilities(facilities);
            }
          }
        } catch {
          // 施設情報取得失敗は無視してデフォルト値を使用
        }
      }

      results.push({
        stationName,
        operatorName,
        hasElevator: facilityInfo.hasElevator ?? false,
        hasEscalator: facilityInfo.hasEscalator ?? false,
        hasAccessibleToilet: facilityInfo.hasAccessibleToilet ?? false,
        hasWheelchairRamp: facilityInfo.hasWheelchairRamp ?? false,
        hasTactilePaving: facilityInfo.hasTactilePaving ?? false,
        barrierFreeRoute: facilityInfo.barrierFreeRoute ?? false,
      });
    }

    // キャッシュに保存
    nearbyCache.set(cacheKey, { data: results, timestamp: Date.now() });
    return results;
  } catch (error) {
    console.warn('ODPT API 呼び出し失敗、組み込みデータにフォールバック:', error);
    return BUILTIN_STATIONS;
  }
}

/**
 * 駅名で特定の駅のアクセシビリティ情報を取得
 *
 * 組み込みデータセットを先に検索し、見つからない場合はAPIを使用。
 *
 * @param stationName - 検索する駅名（例: "東京駅"、"東京"）
 * @returns 該当駅のアクセシビリティ情報、見つからない場合はnull
 */
export async function getStationAccessibility(
  stationName: string,
): Promise<StationAccessibility | null> {
  // 「駅」の有無を正規化して組み込みデータを検索
  const normalizedQuery = stationName.replace(/駅$/, '');

  const builtinMatch = BUILTIN_STATIONS.find((s) => {
    const normalizedName = s.stationName.replace(/駅$/, '');
    return normalizedName === normalizedQuery || s.stationName === stationName;
  });

  if (builtinMatch) {
    return builtinMatch;
  }

  // APIキー未設定の場合はnull
  if (!ODPT_API_KEY) {
    return null;
  }

  // ODPT APIで検索
  try {
    const url =
      `${ODPT_API_BASE}odpt:Station` +
      `?dc:title=${encodeURIComponent(normalizedQuery)}` +
      `&acl:consumerKey=${ODPT_API_KEY}`;

    const response = await fetchWithTimeout(url, REQUEST_TIMEOUT_MS);
    if (!response.ok) {
      return null;
    }

    const stations: OdptStationResponse[] = await response.json();
    if (!Array.isArray(stations) || stations.length === 0) {
      return null;
    }

    const station = stations[0];
    const name = extractStationName(station);
    const operatorName = extractOperatorName(station);

    // 施設情報を取得
    let facilityInfo: Partial<StationAccessibility> = {};
    const facilityUrl = station['odpt:stationFacility'];
    if (facilityUrl) {
      try {
        const facilityFullUrl = facilityUrl.startsWith('http')
          ? `${facilityUrl}?acl:consumerKey=${ODPT_API_KEY}`
          : `${ODPT_API_BASE}${facilityUrl}?acl:consumerKey=${ODPT_API_KEY}`;
        const facResponse = await fetchWithTimeout(facilityFullUrl, REQUEST_TIMEOUT_MS);
        if (facResponse.ok) {
          const facData: OdptFacilityResponse[] = await facResponse.json();
          if (Array.isArray(facData) && facData.length > 0) {
            const facilities = facData[0]['odpt:barrierfreeFacility'] ?? [];
            facilityInfo = parseFacilities(facilities);
          }
        }
      } catch {
        // 施設情報取得失敗は無視
      }
    }

    return {
      stationName: name.includes('駅') ? name : `${name}駅`,
      operatorName,
      hasElevator: facilityInfo.hasElevator ?? false,
      hasEscalator: facilityInfo.hasEscalator ?? false,
      hasAccessibleToilet: facilityInfo.hasAccessibleToilet ?? false,
      hasWheelchairRamp: facilityInfo.hasWheelchairRamp ?? false,
      hasTactilePaving: facilityInfo.hasTactilePaving ?? false,
      barrierFreeRoute: facilityInfo.barrierFreeRoute ?? false,
    };
  } catch (error) {
    console.warn('ODPT API 駅検索失敗:', error);
    return null;
  }
}
