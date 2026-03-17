/**
 * PLATEAU 3D都市モデルAPIサービス
 * 国土交通省のPLATEAUデータから道路・歩道情報を取得する
 */

/** PLATEAU道路データ */
export interface PlateauRoadData {
  id: string;
  roadType: string; // 車道, 歩道, 自転車道 etc.
  width?: number; // メートル
  surfaceType?: string; // asphalt, concrete, etc.
  hasSidewalk: boolean;
  sidewalkWidth?: number; // メートル
  curbHeight?: number; // cm
  location: { lat: number; lng: number };
}

/** PLATEAU API ベースURL */
const API_BASE = 'https://api.plateauview.mlit.go.jp';

/** APIタイムアウト（ミリ秒） */
const TIMEOUT_MS = 15000;

/** 座標グリッドキャッシュ（0.01度単位） */
const gridCache = new Map<string, { data: PlateauRoadData[]; timestamp: number }>();

/** キャッシュの有効期限（1時間） */
const CACHE_TTL_MS = 60 * 60 * 1000;

/** データセットカタログのレスポンス型 */
interface PlateauDataset {
  id: string;
  type: string;
  name?: string;
  city?: { code: string; name: string };
  url?: string;
  [key: string]: unknown;
}

interface PlateauCatalogResponse {
  datasets?: PlateauDataset[];
  [key: string]: unknown;
}

/**
 * 座標をグリッドキーに変換する（0.01度単位）
 * @param lat 緯度
 * @param lng 経度
 * @returns グリッドキー文字列
 */
function toGridKey(lat: number, lng: number): string {
  const gridLat = Math.floor(lat * 100) / 100;
  const gridLng = Math.floor(lng * 100) / 100;
  return `${gridLat},${gridLng}`;
}

/**
 * キャッシュからデータを取得する（有効期限内のもののみ）
 * @param key グリッドキー
 * @returns キャッシュされたデータ、またはnull
 */
function getCachedData(key: string): PlateauRoadData[] | null {
  const entry = gridCache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.timestamp > CACHE_TTL_MS) {
    gridCache.delete(key);
    return null;
  }
  return entry.data;
}

/**
 * PLATEAU交通データを取得する
 * データセットカタログから交通（tran）タイプのデータを検索し、
 * 道路・歩道のメタデータを返す
 * @param lat 緯度
 * @param lng 経度
 * @param radiusMeters 検索半径（メートル）
 * @returns 道路データの配列
 */
export async function fetchPlateauTransportData(
  lat: number,
  lng: number,
  radiusMeters: number
): Promise<PlateauRoadData[]> {
  // キャッシュ確認（0.01度グリッド単位）
  const cacheKey = toGridKey(lat, lng);
  const cached = getCachedData(cacheKey);
  if (cached) {
    // キャッシュ済みデータから半径内のものをフィルタ
    return filterByRadius(cached, lat, lng, radiusMeters);
  }

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    // データセットカタログを問い合わせ
    const catalogUrl = `${API_BASE}/datacatalog/plateau-datasets`;
    const response = await fetch(catalogUrl, {
      signal: controller.signal,
    });

    if (!response.ok) {
      console.warn(`PLATEAU APIエラー: ${response.status}`);
      return [];
    }

    const catalog = (await response.json()) as PlateauCatalogResponse;
    const datasets = catalog.datasets ?? [];

    // 交通（tran）タイプのデータセットをフィルタ
    const tranDatasets = datasets.filter((d) => d.type === 'tran');

    if (tranDatasets.length === 0) {
      // データなしの場合もキャッシュに保存（不要な再リクエスト防止）
      gridCache.set(cacheKey, { data: [], timestamp: Date.now() });
      return [];
    }

    // 各データセットから道路情報を抽出（簡略化版）
    const roadDataList: PlateauRoadData[] = [];

    for (const dataset of tranDatasets) {
      try {
        // 3D Tiles tileset.jsonの取得を試みる
        if (dataset.url) {
          const tilesetResponse = await fetch(dataset.url, {
            signal: controller.signal,
          });

          if (tilesetResponse.ok) {
            const tilesetData = (await tilesetResponse.json()) as Record<string, unknown>;

            // 簡略化されたメタデータ抽出
            // 実際の3D Tilesパースは複雑なため、基本メタデータのみ取得
            const roadData: PlateauRoadData = {
              id: dataset.id,
              roadType: dataset.name ?? '道路',
              hasSidewalk: false,
              location: { lat, lng },
            };

            // tilesetからバウンディングボリューム情報があれば位置を更新
            const root = tilesetData.root as Record<string, unknown> | undefined;
            if (root?.boundingVolume) {
              const bv = root.boundingVolume as Record<string, unknown>;
              const region = bv.region as number[] | undefined;
              if (region && region.length >= 4) {
                // region: [west, south, east, north, minHeight, maxHeight] (ラジアン)
                const centerLat =
                  ((region[1] + region[3]) / 2) * (180 / Math.PI);
                const centerLng =
                  ((region[0] + region[2]) / 2) * (180 / Math.PI);
                roadData.location = { lat: centerLat, lng: centerLng };
              }
            }

            roadDataList.push(roadData);
          }
        }
      } catch (innerError) {
        // 個別データセットの取得失敗は無視して続行
        console.warn(
          `PLATEAUデータセット ${dataset.id} の取得に失敗:`,
          innerError
        );
      }
    }

    // キャッシュに保存
    gridCache.set(cacheKey, { data: roadDataList, timestamp: Date.now() });

    return filterByRadius(roadDataList, lat, lng, radiusMeters);
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      console.warn('PLATEAU APIタイムアウト');
    } else {
      console.warn('PLATEAU APIリクエスト失敗:', error);
    }
    return [];
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * 指定地点に歩道データが存在するか確認する
 * CityGMLエンドポイントを使用して交通地物の有無を問い合わせる
 * @param lat 緯度
 * @param lng 経度
 * @returns 歩道情報、またはデータなしの場合はnull
 */
export async function checkSidewalkPresence(
  lat: number,
  lng: number
): Promise<{ hasSidewalk: boolean; width?: number } | null> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    // CityGMLエンドポイントで交通地物を問い合わせ
    const url = `${API_BASE}/datacatalog/citygml/r:${lng},${lat}?types=tran`;
    const response = await fetch(url, {
      signal: controller.signal,
    });

    if (!response.ok) {
      if (response.status === 404) {
        // データが存在しない地域
        return null;
      }
      console.warn(`PLATEAU CityGML APIエラー: ${response.status}`);
      return null;
    }

    const data = (await response.json()) as Record<string, unknown>;

    // レスポンスに交通地物が含まれているか確認
    const features = data.features as Array<Record<string, unknown>> | undefined;
    if (!features || features.length === 0) {
      return null;
    }

    // 歩道関連の属性を検索
    let hasSidewalk = false;
    let sidewalkWidth: number | undefined;

    for (const feature of features) {
      const properties = feature.properties as Record<string, unknown> | undefined;
      if (!properties) continue;

      // 歩道タイプの地物を検出
      const funcType = properties.function as string | undefined;
      if (funcType && funcType.includes('歩道')) {
        hasSidewalk = true;

        // 幅員情報を取得
        const width = properties.width as number | undefined;
        if (width != null) {
          sidewalkWidth = width;
        }
      }
    }

    return {
      hasSidewalk,
      width: sidewalkWidth,
    };
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      console.warn('PLATEAU CityGML APIタイムアウト');
    } else {
      console.warn('PLATEAU CityGML APIリクエスト失敗:', error);
    }
    return null;
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * 道路データを指定半径内にフィルタする
 * @param data 道路データの配列
 * @param lat 中心緯度
 * @param lng 中心経度
 * @param radiusMeters 半径（メートル）
 * @returns フィルタされた道路データ
 */
function filterByRadius(
  data: PlateauRoadData[],
  lat: number,
  lng: number,
  radiusMeters: number
): PlateauRoadData[] {
  return data.filter((road) => {
    const dLat = (road.location.lat - lat) * 111320;
    const dLng =
      (road.location.lng - lng) * 111320 * Math.cos((lat * Math.PI) / 180);
    const distance = Math.sqrt(dLat * dLat + dLng * dLng);
    return distance <= radiusMeters;
  });
}
