# API 使用例・仕様補足

## 目次

- [認証フロー](#認証フロー)
- [エンドポイント一覧と使用例](#エンドポイント一覧と使用例)
  - [プロファイル取得](#プロファイル取得)
  - [プロファイル作成・更新](#プロファイル作成更新)
  - [ルート検索](#ルート検索)
  - [周辺スポット検索](#周辺スポット検索)
  - [スポット詳細取得](#スポット詳細取得)
  - [AIチャット（Phase 2）](#aiチャットphase-2)
  - [ニーズ抽出（Phase 2）](#ニーズ抽出phase-2)
- [エラーレスポンス一覧](#エラーレスポンス一覧)
- [レート制限](#レート制限)

---

## 認証フロー

すべての API エンドポイントは Firebase Auth の ID トークンによる認証が必要である。

### 認証手順

1. クライアント側で Firebase Auth を使用してユーザー認証を行う（メール/パスワード、Google サインイン等）
2. 認証後、Firebase Auth から ID トークンを取得する
3. API リクエスト時に `Authorization` ヘッダーに `Bearer {IDトークン}` を付与する

### トークン取得の例（iOS / Swift）

```swift
let user = Auth.auth().currentUser
let token = try await user?.getIDToken()
```

### リクエストヘッダー

```
Authorization: Bearer eyJhbGciOiJSUzI1NiIs...（Firebase Auth IDトークン）
Content-Type: application/json
```

### 認証エラー

トークンが無効または未指定の場合、以下のレスポンスが返される。

```json
// 401 Unauthorized - トークン未指定
{
  "error": "認証トークンが必要です"
}

// 401 Unauthorized - トークン無効
{
  "error": "無効な認証トークンです"
}
```

---

## エンドポイント一覧と使用例

ベース URL: `https://{region}-{project-id}.cloudfunctions.net/api`

### プロファイル取得

ユーザーの登録済みプロファイルを取得する。

```bash
curl -X GET \
  "https://{BASE_URL}/api/auth/profile" \
  -H "Authorization: Bearer ${ID_TOKEN}"
```

**レスポンス（200 OK）:**

```json
{
  "userId": "abc123",
  "mobilityType": "wheelchair",
  "companions": ["child"],
  "maxDistanceMeters": 1500,
  "avoidConditions": ["stairs", "slope"],
  "preferConditions": ["restroom", "rest_area"],
  "createdAt": "2026-03-01T10:00:00Z",
  "updatedAt": "2026-03-05T14:30:00Z"
}
```

**エラー（404 Not Found）:**

```json
{
  "error": "プロファイルが見つかりません"
}
```

---

### プロファイル作成・更新

ユーザープロファイルを新規作成または更新する。既存のプロファイルがある場合は上書きされる。

```bash
curl -X POST \
  "https://{BASE_URL}/api/auth/profile" \
  -H "Authorization: Bearer ${ID_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "mobilityType": "wheelchair",
    "companions": ["child", "elderly"],
    "maxDistanceMeters": 2000,
    "avoidConditions": ["stairs", "slope", "crowd"],
    "preferConditions": ["restroom", "covered"]
  }'
```

**リクエストボディの各フィールド:**

| フィールド | 型 | 必須 | 説明 |
|-----------|-----|------|------|
| mobilityType | string | はい | 移動手段。`wheelchair`, `stroller`, `cane`, `walk`, `other` のいずれか |
| companions | string[] | いいえ | 同行者。`child`, `elderly`, `disability` の配列 |
| maxDistanceMeters | number | いいえ | 最大移動距離（メートル）。100〜5000 |
| avoidConditions | string[] | いいえ | 回避条件。`stairs`, `slope`, `crowd`, `dark` の配列 |
| preferConditions | string[] | いいえ | 希望条件。`restroom`, `rest_area`, `covered` の配列 |

**レスポンス（200 OK）:**

```json
{
  "userId": "abc123",
  "mobilityType": "wheelchair",
  "companions": ["child", "elderly"],
  "maxDistanceMeters": 2000,
  "avoidConditions": ["stairs", "slope", "crowd"],
  "preferConditions": ["restroom", "covered"],
  "createdAt": "2026-03-01T10:00:00Z",
  "updatedAt": "2026-03-07T09:15:00Z"
}
```

**エラー（400 Bad Request）:**

```json
{
  "error": "mobilityType は必須です"
}
```

---

### ルート検索

出発地と目的地を指定してバリアフリールートを検索する。

```bash
curl -X POST \
  "https://{BASE_URL}/api/route/search" \
  -H "Authorization: Bearer ${ID_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "origin": {
      "lat": 35.6812,
      "lng": 139.7671
    },
    "destination": {
      "lat": 35.6586,
      "lng": 139.7454
    },
    "userProfileId": "abc123",
    "prioritize": "accessible"
  }'
```

**リクエストボディの各フィールド:**

| フィールド | 型 | 必須 | 説明 |
|-----------|-----|------|------|
| origin | LatLng | はい | 出発地の緯度経度 |
| destination | LatLng | はい | 目的地の緯度経度 |
| userProfileId | string | はい | ユーザープロファイルの ID |
| prioritize | string | はい | 優先条件。`shortest`（最短）, `safest`（安全）, `accessible`（バリアフリー） |

**レスポンス（200 OK）:**

```json
{
  "routes": [
    {
      "routeId": "route-001",
      "accessibilityScore": 85,
      "distanceMeters": 2400,
      "durationMinutes": 35,
      "steps": [
        {
          "stepId": "step-001",
          "instruction": "北に200m直進",
          "distanceMeters": 200,
          "durationSeconds": 180,
          "startLocation": { "lat": 35.6812, "lng": 139.7671 },
          "endLocation": { "lat": 35.6830, "lng": 139.7671 },
          "polyline": "encoded_polyline_string",
          "hasStairs": false,
          "hasSlope": false,
          "slopeGrade": 0,
          "surfaceType": "paved"
        },
        {
          "stepId": "step-002",
          "instruction": "右折して坂道を上る",
          "distanceMeters": 150,
          "durationSeconds": 200,
          "startLocation": { "lat": 35.6830, "lng": 139.7671 },
          "endLocation": { "lat": 35.6830, "lng": 139.7690 },
          "polyline": "encoded_polyline_string",
          "hasStairs": false,
          "hasSlope": true,
          "slopeGrade": 5.2,
          "surfaceType": "paved"
        }
      ],
      "warnings": [
        "ステップ2: 緩やかな坂道あり（勾配 5.2%）"
      ],
      "nearbySpots": [
        {
          "spotId": "spot-101",
          "name": "東京バリアフリートイレ",
          "category": "restroom",
          "location": { "lat": 35.6812, "lng": 139.7671 },
          "accessibilityScore": 92,
          "distanceFromRoute": 30
        }
      ]
    }
  ]
}
```

**エラー（400 Bad Request）:**

```json
{
  "error": "origin と destination は必須です"
}
```

```json
{
  "error": "userProfileId は必須です"
}
```

---

### 周辺スポット検索

指定した地点の周辺にあるバリアフリースポットを検索する。

```bash
curl -X GET \
  "https://{BASE_URL}/api/spots/nearby?lat=35.6812&lng=139.7671&radiusMeters=1000&category=restroom" \
  -H "Authorization: Bearer ${ID_TOKEN}"
```

**クエリパラメータ:**

| パラメータ | 型 | 必須 | デフォルト | 説明 |
|-----------|-----|------|----------|------|
| lat | number | はい | -- | 検索中心の緯度 |
| lng | number | はい | -- | 検索中心の経度 |
| radiusMeters | integer | いいえ | 500 | 検索半径（メートル） |
| category | string | いいえ | 全カテゴリ | スポットカテゴリで絞り込み。`restroom`, `rest_area`, `restaurant`, `cafe`, `park`, `kids_space`, `nursing_room`, `elevator`, `parking`, `other` |

**レスポンス（200 OK）:**

```json
{
  "spots": [
    {
      "spotId": "spot-101",
      "name": "東京バリアフリートイレ",
      "category": "restroom",
      "location": { "lat": 35.6812, "lng": 139.7671 },
      "accessibilityScore": 92,
      "distanceFromRoute": 0
    },
    {
      "spotId": "spot-102",
      "name": "丸の内休憩スペース",
      "category": "rest_area",
      "location": { "lat": 35.6820, "lng": 139.7660 },
      "accessibilityScore": 78,
      "distanceFromRoute": 150
    }
  ]
}
```

**エラー（400 Bad Request）:**

```json
{
  "error": "lat と lng は必須です"
}
```

---

### スポット詳細取得

特定のスポットの詳細情報を取得する。

```bash
curl -X GET \
  "https://{BASE_URL}/api/spots/spot-101" \
  -H "Authorization: Bearer ${ID_TOKEN}"
```

**レスポンス（200 OK）:**

```json
{
  "spotId": "spot-101",
  "name": "東京バリアフリートイレ",
  "description": "東京駅丸の内口改札内にあるバリアフリー対応トイレ。車椅子利用可能。おむつ交換台あり。",
  "category": "restroom",
  "location": { "lat": 35.6812, "lng": 139.7671 },
  "address": "東京都千代田区丸の内1-9-1",
  "accessibilityScore": 92,
  "accessibility": {
    "wheelchairAccessible": true,
    "hasElevator": true,
    "hasAccessibleRestroom": true,
    "hasBabyChangingStation": true,
    "hasNursingRoom": false,
    "floorType": "flat",
    "notes": [
      "24時間利用可能",
      "オストメイト対応"
    ]
  },
  "photoUrls": [
    "https://storage.example.com/spots/spot-101/photo1.jpg"
  ],
  "openingHours": "24時間",
  "phoneNumber": "03-1234-5678",
  "website": "https://www.example.com/spot-101"
}
```

**エラー（404 Not Found）:**

```json
{
  "error": "スポットが見つかりません"
}
```

---

### AIチャット（Phase 2）

AIとの対話メッセージを送信し、応答を取得する。

```bash
curl -X POST \
  "https://{BASE_URL}/api/chat" \
  -H "Authorization: Bearer ${ID_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "abc123",
    "message": "車椅子で東京駅から渋谷駅まで行きたいです。階段は避けたいです。",
    "conversationHistory": [
      {
        "role": "assistant",
        "content": "こんにちは。お出かけのお手伝いをします。どちらへ行かれますか？"
      }
    ]
  }'
```

**リクエストボディの各フィールド:**

| フィールド | 型 | 必須 | 説明 |
|-----------|-----|------|------|
| userId | string | はい | ユーザー ID |
| message | string | はい | ユーザーの最新メッセージ |
| conversationHistory | ChatMessage[] | はい | これまでの会話履歴（role と content の配列） |

**レスポンス（200 OK）:**

```json
{
  "reply": "東京駅から渋谷駅まで、階段を避けたバリアフリールートをお探しですね。途中に休憩できる場所は必要ですか？",
  "extractedNeeds": {
    "mobilityType": "wheelchair",
    "avoidConditions": ["stairs"]
  },
  "suggestedAction": "ask_more"
}
```

**suggestedAction の値:**

| 値 | 説明 |
|----|------|
| `ask_more` | 追加情報が必要。AIが続けて質問する |
| `search_route` | 十分な情報が揃った。ルート検索を実行すべき |
| `show_spots` | スポット情報の表示を推奨 |
| `null` | 特定のアクションは不要 |

**エラー（400 Bad Request）:**

```json
{
  "error": "message は必須です"
}
```

---

### ニーズ抽出（Phase 2）

会話履歴からユーザーのニーズを構造化データとして抽出する。

```bash
curl -X POST \
  "https://{BASE_URL}/api/extract-needs" \
  -H "Authorization: Bearer ${ID_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "abc123",
    "conversationHistory": [
      {
        "role": "user",
        "content": "車椅子で東京駅から渋谷駅まで行きたいです"
      },
      {
        "role": "assistant",
        "content": "階段や急な坂道は避けた方がよろしいですか？"
      },
      {
        "role": "user",
        "content": "はい、階段は避けてください。坂道は緩やかなら大丈夫です"
      }
    ]
  }'
```

**リクエストボディの各フィールド:**

| フィールド | 型 | 必須 | 説明 |
|-----------|-----|------|------|
| userId | string | はい | ユーザー ID |
| conversationHistory | ChatMessage[] | はい | 会話履歴全体（1件以上必須） |

**レスポンス（200 OK）:**

```json
{
  "needs": {
    "mobilityType": "wheelchair",
    "companions": [],
    "avoidConditions": ["stairs"],
    "preferConditions": []
  },
  "confidence": 0.82,
  "missingFields": ["maxDistanceMeters", "preferConditions"]
}
```

**レスポンスの各フィールド:**

| フィールド | 型 | 説明 |
|-----------|-----|------|
| needs | object | 抽出されたニーズ。UserProfile の部分型 |
| confidence | number | 抽出の確信度（0.0〜1.0） |
| missingFields | string[] | まだ情報が不足しているフィールド名のリスト |

**エラー（400 Bad Request）:**

```json
{
  "error": "conversationHistory は必須です"
}
```

---

## エラーレスポンス一覧

すべてのエラーレスポンスは以下の形式で返される。

```json
{
  "error": "エラーメッセージ"
}
```

### 共通エラー

| HTTP ステータス | error メッセージ | 原因 |
|---------------|-----------------|------|
| 401 | 認証トークンが必要です | Authorization ヘッダーが未指定、または `Bearer ` プレフィックスがない |
| 401 | 無効な認証トークンです | ID トークンの有効期限切れ、または不正なトークン |
| 500 | （各エンドポイント固有のメッセージ） | サーバー内部エラー |

### エンドポイント固有のエラー

| エンドポイント | HTTP ステータス | error メッセージ |
|--------------|---------------|-----------------|
| GET /api/auth/profile | 404 | プロファイルが見つかりません |
| POST /api/auth/profile | 400 | mobilityType は必須です |
| POST /api/auth/profile | 500 | プロファイルの保存に失敗しました |
| GET /api/auth/profile | 500 | プロファイルの取得に失敗しました |
| POST /api/route/search | 400 | origin と destination は必須です |
| POST /api/route/search | 400 | userProfileId は必須です |
| POST /api/route/search | 500 | ルート検索に失敗しました |
| GET /api/spots/nearby | 400 | lat と lng は必須です |
| GET /api/spots/nearby | 500 | スポット検索に失敗しました |
| GET /api/spots/:spotId | 404 | スポットが見つかりません |
| GET /api/spots/:spotId | 500 | スポット詳細の取得に失敗しました |
| POST /api/chat | 400 | message は必須です |
| POST /api/chat | 500 | チャット応答の取得に失敗しました |
| POST /api/extract-needs | 400 | conversationHistory は必須です |
| POST /api/extract-needs | 500 | ニーズ抽出に失敗しました |

### AI推論サーバー固有のエラー（内部 API）

| HTTP ステータス | 説明 |
|---------------|------|
| 503 | モデルロード中またはサーバー過負荷。しばらく待ってから再試行する |

---

## レート制限

### クライアント API（iOS -> Backend）

Firebase Cloud Functions のデフォルトのレート制限に準拠する。

| 項目 | 制限値 |
|------|--------|
| 同時接続数 | Cloud Functions のインスタンス設定に依存 |
| リクエストタイムアウト | 60 秒 |
| リクエストボディサイズ | 10 MB |

現時点ではアプリケーションレベルでの独自レート制限は設けていない。今後、ユーザー単位でのレート制限（例: 1分あたり30リクエスト）を導入する可能性がある。

### AI推論サーバー API（Backend -> AI Server）

AI推論サーバーは GPU リソースに依存するため、以下の制約がある。

| 項目 | 制限値 |
|------|--------|
| 同時リクエスト数 | GPU メモリに依存（目安: 1〜4 同時処理） |
| レスポンスタイムアウト | 30 秒 |
| 最大トークン数 | 1024（デフォルト、リクエストで変更可能） |

AI サーバーが過負荷の場合、503 ステータスが返される。Backend 側でリトライ処理を行う。

### ヘルスチェック

AI推論サーバーのヘルスチェックエンドポイント（認証不要）:

```bash
curl -X GET "https://ai.accessroute.example.com/health"
```

**レスポンス:**

```json
{
  "status": "ok",
  "model": "model-name",
  "uptime_seconds": 3600
}
```

`status` の値:

| 値 | 説明 |
|----|------|
| `ok` | 正常稼働中 |
| `loading` | モデルロード中。リクエストは受け付けられない |
| `error` | エラー状態 |
