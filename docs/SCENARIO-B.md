# シナリオB: リクエスト/レスポンス変換＋モック応答＋段階的リリース

## 🎯 目標

仕様変更時に **バックエンド無改修**で API の形を合わせ、**バックエンド未完成でも**モックでフロント開発を推進します。さらに **Revision（改訂）** で段階公開を実現します。

## ✅ 達成後の状態

- `GET /v1/prices/{sku}` → **レスポンスシェイプを変換**
  - 旧: `{"sku", "price_jpy", "product_name", "category"}`
  - 新: `{"productCode", "amount", "currency", "name", "type"}`
- 一部の SKU (`SKU-MOCK`, `SKU-DEV-*`) は **モック応答**
- **Revision** 機能で新旧定義を安全に並行運用可能

---

## 📋 前提条件

- APIM インスタンス作成済み
- Pricing サービスがデプロイ済み（または `localhost:8002` で起動中）
- シナリオAを完了していること（推奨）

---

## 🔧 Azure 実装手順

### Step 1: APIM で Pricing API 作成

#### 1-1. バックエンド作成

```powershell
az apim backend create \
  --resource-group <rg-name> \
  --service-name <apim-name> \
  --backend-id pricing-backend \
  --url http://localhost:8002 \
  --protocol http
```

#### 1-2. API 定義作成

```powershell
# Azure Portal → APIM → APIs → Add API → Blank API

# Display name: Pricing API
# Name: pricing-api
# Web service URL: (空欄)
# API URL suffix: v1/prices
```

#### 1-3. Operation 追加

```
GET /v1/prices/{sku}
Display name: Get Price by SKU
URL: GET /{sku}
Backend: pricing-backend
```

### Step 2: レスポンス変換ポリシー適用

#### 2-1. ポリシー適用前のテスト（旧フォーマット確認）

```powershell
curl http://localhost:8002/v1/prices/SKU-001
```

期待結果（旧フォーマット）:

```json
{
  "sku": "SKU-001",
  "price_jpy": 1200,
  "product_name": "ノートPC",
  "category": "electronics"
}
```

#### 2-2. 変換ポリシー適用

`apim/policies/02-response-transformation.xml` を適用:

```powershell
# Azure Portal
# APIs → pricing-api → Design → All operations
# Outbound processing → </> (Code editor)
# XMLをペースト → Save
```

#### 2-3. 変換後のテスト（新フォーマット確認）

```powershell
curl https://<apim-name>.azure-api.net/v1/prices/SKU-001
```

期待結果（新フォーマット）:

```json
{
  "productCode": "SKU-001",
  "amount": 1200,
  "currency": "JPY",
  "name": "ノートPC",
  "type": "electronics",
  "_metadata": {
    "transformedBy": "APIM",
    "transformedAt": "2025-01-15T10:30:00Z",
    "version": "2.0"
  }
}
```

**重要**: バックエンドコードは一切変更していません！

### Step 3: モック応答ポリシー適用

#### 3-1. モックポリシー追加

`apim/policies/03-mock-response.xml` を適用:

```powershell
# 変換ポリシーと組み合わせる場合は、inboundセクションにモックポリシーを追加
```

#### 3-2. モック応答のテスト

```powershell
# SKU-MOCK へアクセス
curl https://<apim-name>.azure-api.net/v1/prices/SKU-MOCK
```

期待結果:

```json
{
  "productCode": "SKU-MOCK",
  "amount": 999,
  "currency": "JPY",
  "name": "モック商品（開発用）",
  "type": "test",
  "_metadata": {
    "isMock": true,
    "mockedBy": "APIM",
    "mockedAt": "2025-01-15T10:35:00Z",
    "note": "これはモック応答です。実際のバックエンドは呼び出されていません。"
  }
}
```

レスポンスヘッダー確認:

```powershell
curl -i https://<apim-name>.azure-api.net/v1/prices/SKU-MOCK | grep "X-Mocked"
# X-Mocked-Response: true
# X-Mock-Version: 1.0
```

#### 3-3. 開発用モック（SKU-DEV-*）のテスト

```powershell
curl https://<apim-name>.azure-api.net/v1/prices/SKU-DEV-001
curl https://<apim-name>.azure-api.net/v1/prices/SKU-DEV-NEW-FEATURE
```

どちらも固定レスポンスを返し、バックエンドは呼ばれません。

### Step 4: Revisions で段階的リリース

#### 4-1. 新しい Revision 作成

```powershell
# Azure Portal → APIM → APIs → pricing-api
# Revisions タブ → + Add Revision

# Revision ID: rev-2
# Description: Add advanced transformation and caching
```

#### 4-2. 新 Revision で変更を加える

```powershell
# rev-2 を選択
# Policies を編集（例：キャッシュ追加）
```

追加ポリシー例（キャッシュ）:

```xml
<inbound>
    <base />
    <!-- 価格情報を60秒キャッシュ -->
    <cache-lookup vary-by-developer="false" vary-by-developer-groups="false" downstream-caching-type="none" />
</inbound>

<outbound>
    <base />
    <cache-store duration="60" />
</outbound>
```

#### 4-3. Revision のテスト

```powershell
# rev-2 専用URLでテスト
curl https://<apim-name>.azure-api.net/v1/prices/SKU-001;rev=2
```

#### 4-4. Revision を既定に昇格

```powershell
# Azure Portal
# Revisions タブ → rev-2 → Make current

# または CLI
az apim api release create \
  --resource-group <rg-name> \
  --service-name <apim-name> \
  --api-id pricing-api \
  --api-revision 2 \
  --notes "Promoted rev-2 with caching"
```

**利点**: ゼロダウンタイムで新バージョンに切り替え。問題があれば即座にロールバック可能。

---

## 🔄 AWS での同等実装

### オプション 1: REST API + Mapping Templates (VTL)

#### Step 1: REST API 作成

```bash
# AWS Console → API Gateway → Create API → REST API

# API name: pricing-api
# Endpoint Type: Regional
```

#### Step 2: リソースとメソッド作成

```bash
# Resources → Create Resource
# Resource Name: {sku}
# Resource Path: {sku}

# Actions → Create Method → GET
```

#### Step 3: Integration 設定

```bash
# Integration type: HTTP
# HTTP method: GET
# Endpoint URL: http://<backend-url>/v1/prices/{sku}
# Use Path Override: /v1/prices/{sku}
```

#### Step 4: Mapping Template 設定（レスポンス変換）

```bash
# Integration Response → Mapping Templates
# Content-Type: application/json
```

VTL テンプレート:

```vtl
#set($inputRoot = $input.path('$'))
{
  "productCode": "$inputRoot.sku",
  "amount": $inputRoot.price_jpy,
  "currency": "JPY",
  "name": "$inputRoot.product_name",
  "type": "$inputRoot.category",
  "_metadata": {
    "transformedBy": "API-Gateway",
    "transformedAt": "$context.requestTime",
    "version": "2.0"
  }
}
```

**課題**:
- VTL の学習コスト
- デバッグが困難
- 型変換の複雑さ

### オプション 2: HTTP API + Parameter Mapping（限定的）

HTTP API は VTL をサポートせず、**Parameter mapping** のみ:
- ヘッダー、クエリパラメータの変換は可能
- **ボディの変換は不可**

→ レスポンス変換には Lambda が必要

### モック統合

#### Step 1: Mock Integration 作成

```bash
# Method Execution → Integration Request
# Integration type: Mock

# Integration Response
# Mapping Template:
```

```json
{
  "productCode": "SKU-MOCK",
  "amount": 999,
  "currency": "JPY",
  "name": "モック商品（開発用）",
  "type": "test",
  "_metadata": {
    "isMock": true
  }
}
```

**課題**:
- メソッドごとにMock統合を設定
- 条件分岐（SKU-MOCK の場合のみ）が複雑
- Method Request → Integration Request で条件判定が必要

### 段階的リリース（Stage）

#### Step 1: 新 Stage 作成

```bash
# Stages → Create
# Stage name: v2
# Deployment: Latest
```

#### Step 2: Canary デプロイメント

```bash
# Stages → v1 → Canary
# Canary percentage: 10%
# Deploy changes to Canary
```

**課題**:
- Stage ごとに異なる URL
- Canary はトラフィック比率のみ（機能フラグ不可）

---

## 📊 比較表

| 項目 | APIM | AWS REST API | AWS HTTP API |
|------|------|--------------|--------------|
| **レスポンス変換** | C# expression（直感的） | VTL（学習コスト高） | 非サポート（Lambda必要） |
| **変換の柔軟性** | 高（JSONオブジェクト操作可） | 中（VTL制約） | 低 |
| **モック設定** | ポリシー条件分岐 | メソッドごとMock統合 | メソッドごとMock統合 |
| **条件付きモック** | 簡単（choose要素） | 複雑（リクエストバリデータ） | 複雑 |
| **段階リリース** | Revision（並行運用） | Stage（別URL） | Stage（別URL） |
| **ロールバック** | 即座（Revision切替） | Deploy必要 | Deploy必要 |
| **設定時間** | 15～20分 | 30～45分（VTL習得含む） | 不可能（Lambda必要） |
| **コード行数** | 0 | 0（VTL除く） | 50～100（Lambda） |

---

## 🧪 詳細テストシナリオ

### テスト 1: 変換前後の比較

```powershell
# バックエンド直接（変換前）
curl http://localhost:8002/v1/prices/SKU-001 | jq .

# APIM経由（変換後）
curl https://<apim-name>.azure-api.net/v1/prices/SKU-001 | jq .

# 差分確認
diff <(curl -s http://localhost:8002/v1/prices/SKU-001 | jq -S .) \
     <(curl -s https://<apim-name>.azure-api.net/v1/prices/SKU-001 | jq -S .)
```

### テスト 2: モック vs 実データ

```powershell
# 実データ（バックエンド呼び出し）
$response1 = curl -s https://<apim-name>.azure-api.net/v1/prices/SKU-001
echo $response1 | jq '._metadata.isMock'
# null（モックではない）

# モックデータ（バックエンド呼び出しなし）
$response2 = curl -s https://<apim-name>.azure-api.net/v1/prices/SKU-MOCK
echo $response2 | jq '._metadata.isMock'
# true
```

### テスト 3: Revision切り替えパフォーマンス

```powershell
# 切り替え前の時刻記録
$startTime = Get-Date

# Revision切り替え（Azure Portal または CLI）
az apim api release create --resource-group <rg> --service-name <apim> --api-id pricing-api --api-revision 2

# 切り替え後の時刻
$endTime = Get-Date
$duration = ($endTime - $startTime).TotalSeconds

echo "Revision切り替え時間: $duration 秒"
# 期待: 1～2秒
```

---

## 🎓 学習ポイント

1. **バックエンド不変**: 既存コードを保護しながらAPI進化
2. **モックの威力**: バックエンド開発とフロントエンド開発の並行化
3. **Revisionの安全性**: 本番影響なしでテスト→即時切替
4. **変換の柔軟性**: C# expression で複雑な変換も可能

---

## 📚 次のステップ

- [シナリオC: プロダクト化とレート制限](SCENARIO-C.md) に進む
- [比較結果を記録](COMPARISON.md)
- [AWS 実装詳細](../aws/README-AWS.md) を確認
