# シナリオC: プロダクト化（サブスクリプション/レート制限/クォータ）＋開発者ポータル

## 🎯 目標

**利用者ごとの鍵配布、レート制限、クォータ**を**コード改修なし**で適用し、**ドキュメント自動公開**と**サインアップ**を体験します。

## ✅ 達成後の状態

- 「**Basic**: 10req/min, 10k/day」「**Partner**: 50req/min, 100k/day」等の **Product** を作成
- **サブスクリプションキー**でアクセス制御、キーごとに**レート/クォータ**適用
- **Developer Portal** に OpenAPI が自動掲出、Try-It で即試験可能

---

## 📋 前提条件

- APIM インスタンス作成済み
- Orders API と Pricing API が作成済み
- シナリオA、Bを完了していること（推奨）

---

## 🔧 Azure 実装手順

### Step 1: Products 作成

#### 1-1. Basic Product 作成

```powershell
# Azure Portal → APIM → Products → + Add

# Display name: Basic
# Id: basic
# Description: Basic plan for individual developers
# Requires subscription: ✓
# Requires approval: (任意)
# Subscription limit: Unlimited
# Legal terms: (任意)
# State: Published
```

CLI:

```powershell
az apim product create \
  --resource-group <rg-name> \
  --service-name <apim-name> \
  --product-id basic \
  --product-name "Basic" \
  --description "Basic plan: 10 req/min, 10k req/day" \
  --subscription-required true \
  --approval-required false \
  --state published
```

#### 1-2. Partner Product 作成

```powershell
az apim product create \
  --resource-group <rg-name> \
  --service-name <apim-name> \
  --product-id partner \
  --product-name "Partner" \
  --description "Partner plan: 50 req/min, 100k req/day" \
  --subscription-required true \
  --approval-required true \
  --state published
```

### Step 2: APIs を Products に関連付け

#### 2-1. Basic Product に APIs 追加

```powershell
# Azure Portal
# Products → Basic → APIs → + Add
# orders-api と pricing-api を選択 → Select

# CLI
az apim product api add \
  --resource-group <rg-name> \
  --service-name <apim-name> \
  --product-id basic \
  --api-id orders-api

az apim product api add \
  --resource-group <rg-name> \
  --service-name <apim-name> \
  --product-id basic \
  --api-id pricing-api
```

#### 2-2. Partner Product に APIs 追加

```powershell
az apim product api add \
  --resource-group <rg-name> \
  --service-name <apim-name> \
  --product-id partner \
  --api-id orders-api

az apim product api add \
  --resource-group <rg-name> \
  --service-name <apim-name> \
  --product-id partner \
  --api-id pricing-api
```

### Step 3: レート制限/クォータポリシー適用

#### 3-1. Basic Product ポリシー

```powershell
# Azure Portal
# Products → Basic → Policies → </> (Code editor)
```

ポリシー:

```xml
<policies>
    <inbound>
        <base />
        <!-- レート制限: 10回/分 -->
        <rate-limit-by-key 
            calls="10" 
            renewal-period="60" 
            counter-key="@(context.Subscription.Key)" />
        
        <!-- クォータ: 10,000回/日 -->
        <quota-by-key 
            calls="10000" 
            renewal-period="86400" 
            counter-key="@(context.Subscription.Key)" />
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
        <!-- レート制限情報をヘッダーに追加 -->
        <set-header name="X-RateLimit-Limit" exists-action="override">
            <value>10</value>
        </set-header>
        <set-header name="X-Quota-Limit" exists-action="override">
            <value>10000</value>
        </set-header>
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

#### 3-2. Partner Product ポリシー

```xml
<policies>
    <inbound>
        <base />
        <!-- レート制限: 50回/分 -->
        <rate-limit-by-key 
            calls="50" 
            renewal-period="60" 
            counter-key="@(context.Subscription.Key)" />
        
        <!-- クォータ: 100,000回/日 -->
        <quota-by-key 
            calls="100000" 
            renewal-period="86400" 
            counter-key="@(context.Subscription.Key)" />
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
        <set-header name="X-RateLimit-Limit" exists-action="override">
            <value>50</value>
        </set-header>
        <set-header name="X-Quota-Limit" exists-action="override">
            <value>100000</value>
        </set-header>
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

または `apim/policies/04-rate-limit-quota.xml` を適用（Basic用にカスタマイズ）

### Step 4: Subscriptions 発行

#### 4-1. Basic Subscription 作成

```powershell
# Azure Portal
# Subscriptions → + Add subscription

# Name: basic-dev-001
# Display name: Basic - Developer 001
# User: (任意 - ユーザーと紐付ける場合)
# Product: Basic
# State: Active

# CLI
az apim subscription create \
  --resource-group <rg-name> \
  --service-name <apim-name> \
  --subscription-id basic-dev-001 \
  --name "Basic - Developer 001" \
  --scope /products/basic \
  --state active
```

キーの取得:

```powershell
az apim subscription show \
  --resource-group <rg-name> \
  --service-name <apim-name> \
  --subscription-id basic-dev-001 \
  --query primaryKey -o tsv

# 出力例: 1234567890abcdef1234567890abcdef
```

#### 4-2. Partner Subscription 作成

```powershell
az apim subscription create \
  --resource-group <rg-name> \
  --service-name <apim-name> \
  --subscription-id partner-corp-001 \
  --name "Partner - Corporation 001" \
  --scope /products/partner \
  --state active
```

### Step 5: Developer Portal 設定

#### 5-1. Developer Portal の有効化

APIM v2 以降はデフォルトで有効。アクセス:

```
https://<apim-name>.developer.azure-api.net
```

#### 5-2. ブランディングのカスタマイズ

```powershell
# Azure Portal → APIM → Developer portal
# Customize をクリック → Edit mode

# カスタマイズ可能項目:
# - ロゴ
# - 色
# - フォント
# - ナビゲーション
# - コンテンツページ

# 完了後: Publish をクリック
```

#### 5-3. サインアップの有効化

```powershell
# Azure Portal → APIM → Identities
# Sign-up / Sign-in → Enable sign-up: ✓
```

#### 5-4. APIs の公開設定

```powershell
# APIs → orders-api → Settings
# Subscription required: ✓
# Products: Basic, Partner を選択
```

同様に pricing-api も設定。

### Step 6: Developer Portal の体験

#### 6-1. ユーザー登録

1. `https://<apim-name>.developer.azure-api.net` にアクセス
2. **Sign up** をクリック
3. メール、パスワードを入力
4. 確認メールを確認（Entra ID 連携の場合はスキップ可能）

#### 6-2. API の発見

1. **APIs** タブをクリック
2. **Orders API** と **Pricing API** が表示される
3. **Try it** をクリック

#### 6-3. Subscription の取得

```powershell
# ユーザーダッシュボード → Products
# Basic → Subscribe をクリック
# Subscription name: My Basic Subscription
# Submit

# Subscription key が発行される
```

#### 6-4. Try-It 機能でテスト

```powershell
# Orders API → GET /v1/orders/{id}
# Parameters: id = 1001
# Subscription key: (自動入力)
# Send をクリック

# Response が表示される
```

---

## 🧪 テスト手順

### Test 1: サブスクリプションキーなしでアクセス（401 期待）

```powershell
curl -i https://<apim-name>.azure-api.net/v1/orders/1001
```

期待結果:

```
HTTP/1.1 401 Unauthorized
WWW-Authenticate: AzureApiManagementKey realm="https://<apim-name>.azure-api.net/v1/orders",name="Ocp-Apim-Subscription-Key",type="header"

{
  "statusCode": 401,
  "message": "Access denied due to missing subscription key."
}
```

### Test 2: Basic キーで正常アクセス

```powershell
$BASIC_KEY = "<basic-subscription-key>"

curl -i -H "Ocp-Apim-Subscription-Key: $BASIC_KEY" https://<apim-name>.azure-api.net/v1/orders/1001
```

期待結果:

```
HTTP/1.1 200 OK
X-RateLimit-Limit: 10
X-Quota-Limit: 10000
X-Subscription-Name: Basic - Developer 001

{
  "id": "1001",
  "status": "confirmed",
  ...
}
```

### Test 3: レート制限の確認（10回超過で 429）

```powershell
# 15回連続でリクエスト
for ($i=1; $i -le 15; $i++) {
    echo "Request $i"
    curl -i -H "Ocp-Apim-Subscription-Key: $BASIC_KEY" https://<apim-name>.azure-api.net/v1/orders/1001 2>&1 | Select-String "HTTP/|RateLimitExceeded"
    Start-Sleep -Milliseconds 100
}
```

期待結果:

```
Request 1-10: HTTP/1.1 200 OK
Request 11-15: HTTP/1.1 429 Too Many Requests

{
  "error": "RateLimitExceeded",
  "message": "レート制限を超過しました。1分あたり10リクエストまでです。",
  "retryAfter": 60
}
```

### Test 4: Partner キーで高レート制限確認

```powershell
$PARTNER_KEY = "<partner-subscription-key>"

# 30回連続でリクエスト（Partner は 50回/分）
for ($i=1; $i -le 30; $i++) {
    curl -s -H "Ocp-Apim-Subscription-Key: $PARTNER_KEY" https://<apim-name>.azure-api.net/v1/orders/1001 > $null
    echo "Request $i: OK"
}
```

期待結果: すべて 200 OK

---

## 🔄 AWS での同等実装

### Step 1: Usage Plan 作成

#### Basic Usage Plan

```bash
# AWS Console → API Gateway → Usage Plans → Create

# Name: Basic
# Description: 10 req/sec, 10k req/day
# Throttle: Rate = 10, Burst = 20
# Quota: 10000 requests per day
```

CLI:

```bash
aws apigateway create-usage-plan \
  --name "Basic" \
  --description "Basic plan" \
  --throttle rateLimit=10,burstLimit=20 \
  --quota limit=10000,period=DAY
```

#### Partner Usage Plan

```bash
aws apigateway create-usage-plan \
  --name "Partner" \
  --throttle rateLimit=50,burstLimit=100 \
  --quota limit=100000,period=DAY
```

### Step 2: API Stage を Usage Plan に関連付け

```bash
aws apigateway create-usage-plan-key \
  --usage-plan-id <usage-plan-id> \
  --key-type API_KEY \
  --key-id <api-key-id>

aws apigateway update-usage-plan \
  --usage-plan-id <usage-plan-id> \
  --patch-operations \
    op=add,path=/apiStages,value=<api-id>:<stage-name>
```

### Step 3: API Key 作成

```bash
aws apigateway create-api-key \
  --name "basic-dev-001" \
  --enabled

# Key を Usage Plan に紐付け
aws apigateway create-usage-plan-key \
  --usage-plan-id <basic-usage-plan-id> \
  --key-type API_KEY \
  --key-id <api-key-id>
```

### Step 4: Developer Portal デプロイ

#### SAR (Serverless Application Repository) から展開

```bash
# AWS Console → Serverless Application Repository
# Public applications → "api-gateway-dev-portal" を検索
# Deploy

# Parameters:
# - CognitoIdentityPoolName: apim-dev-portal
# - DevPortalSiteS3BucketName: apim-dev-portal-<random>
# - StaticAssetRebuildToken: <random>

# デプロイ時間: 約15～30分
```

構成:

- **S3**: 静的サイトホスティング
- **CloudFront**: CDN
- **Cognito**: ユーザー認証
- **Lambda**: API カタログ/サブスクリプション管理
- **DynamoDB**: ユーザーデータ

#### カスタマイズ

```bash
# S3 バケットに独自 HTML/CSS をアップロード
# Lambda 関数でビジネスロジック追加（承認フローなど）

# 学習コスト: 中～高
```

---

## 📊 比較表

| 項目 | APIM | API Gateway |
|------|------|-------------|
| **Product/Plan 管理** | Products（GUI一元管理） | Usage Plan（個別設定） |
| **設定箇所数** | 1画面で完結 | 3～4画面（Plan, Key, Stage紐付け） |
| **Developer Portal** | 標準搭載・即利用可 | 別途SAR経由でデプロイ（15～30分） |
| **Portal カスタマイズ** | GUI エディタ | S3 + HTML/CSS/JS 直接編集 |
| **Try-It 機能** | デフォルト有効 | Dev Portal 経由で可能 |
| **サインアップ** | デフォルトサポート | Cognito統合が必要 |
| **承認フロー** | Product設定で有効化 | Lambda カスタム実装 |
| **API カタログ** | OpenAPI自動公開 | Lambda経由で取得 |
| **オンボーディング時間** | 2～3分（キー発行のみ） | 10～15分（Portal含む） |
| **開発工数（Portal）** | ほぼ0（ブランディングのみ） | 数時間～数日（カスタマイズ） |

---

## 🎓 学習ポイント

1. **プロダクト中心設計**: API単位ではなくプロダクト単位で管理
2. **ノーコードポリシー**: レート/クォータをXMLで宣言的に実装
3. **即座のポータル**: デプロイ不要でDeveloper Portalが利用可能
4. **ユーザー体験**: Try-Itで開発者が即座にAPIを試験可能

---

## 📚 次のステップ

- [比較結果を評価シートに記録](COMPARISON.md)
- [AWS 実装を完了して差分を確認](../aws/README-AWS.md)
- 本番環境への適用検討
