# シナリオA: ノーコード認証（Entra ID）＋バックエンド無改修

## 🎯 目標

バックエンドにコードを入れずに、APIM ポリシーだけで **OAuth2/JWT 検証**・**スコープ/claim 検査**・**ヘッダ付与**を行います。

## ✅ 達成後の状態

- `/v1/orders/*` は **アクセストークン必須**（Entra ID 発行）
- トークンの `aud/scope` を **APIM ポリシー**で検査
- バックエンド FastAPI は **一切の認証コードなし**
- 検証済みのクレーム情報が `x-caller-id`, `x-caller-email` ヘッダーとしてバックエンドに到達

---

## 📋 前提条件

- Azure サブスクリプション
- APIM インスタンス作成済み
- **Orders サービスが Azure Functions にデプロイ済み**（デプロイ手順は [README.md](../README.md) 参照）
- Azure CLI ログイン済み (`az login`)
- Azure Functions Core Tools インストール済み

---

## 🔧 Azure 実装手順

### Step 1: Entra ID でアプリ登録（Server API）

#### 1-1. アプリケーション登録

```powershell
# Azure Portal を開く
# Entra ID → App registrations → New registration

# または CLI
az ad app create --display-name "OrdersAPI-Backend" --sign-in-audience AzureADMyOrg
```

#### 1-2. App ID URI 設定

```powershell
# Azure Portal
# アプリ → Expose an API → Set (Application ID URI)
# 推奨: api://<app-id>

# CLI
$APP_ID = "<your-app-id>"
az ad app update --id $APP_ID --identifier-uris "api://$APP_ID"
```

#### 1-3. スコープ定義

```powershell
# Azure Portal
# Expose an API → Add a scope
# Scope name: Orders.Read
# Who can consent: Admins and users
# Display name: Read Orders
# Description: Allows reading order information
```

追加スコープ:
- `Orders.ReadWrite`: 読み書き可能

結果例:
```
api://<app-id>/Orders.Read
api://<app-id>/Orders.ReadWrite
```

#### 1-4. 承認済みクライアントアプリケーションの追加

クライアントアプリケーションからの同意を事前承認します。

```powershell
# Azure Portal
# アプリ → Expose an API → Add a client application

# Client ID: <client-app-id>（Step 2で作成するクライアントアプリのID）
# Authorized scopes: Orders.Read にチェック
# Add application
```

> **注意**: この設定により、ユーザーが初回サインイン時に同意画面をスキップできます。

### Step 2: Entra ID でアプリ登録（Client App）

#### 2-1. クライアントアプリ作成

```powershell
az ad app create --display-name "OrdersAPI-Client" --sign-in-audience AzureADMyOrg
```

#### 2-2. API アクセス許可追加

```powershell
# Azure Portal
# アプリ → API permissions → Add a permission
# My APIs → OrdersAPI-Backend
# Delegated permissions → Orders.Read を選択
# Add permissions

# 管理者の同意を付与（テナント管理者のみ）
# Grant admin consent for <tenant>
```

#### 2-3. 認証設定（テスト用）

```powershell
# Azure Portal
# Authentication → Add a platform → Single-page application (SPA)
# Redirect URIs: https://jwt.ms （トークンデバッグ用）

# または Public client (for CLI testing)
# Redirect URIs: http://localhost
# Allow public client flows: Yes
```

### Step 3: APIM でバックエンド登録

#### 3-1. バックエンド作成

```powershell
# deployment-info.txt から Azure Functions の URL を確認
# 例: https://orders-api-1234.azurewebsites.net

# Azure Portal → APIM → Backends → Add

# Name: orders-backend
# Type: HTTP(s)
# Runtime URL: https://orders-api-1234.azurewebsites.net
```

CLI:
```powershell
# Azure Functions の URL を設定
$FUNCTION_APP_NAME = "orders-api-1234"  # deployment-info.txt から取得
$BACKEND_URL = "https://$FUNCTION_APP_NAME.azurewebsites.net"

az apim backend create \
  --resource-group <rg-name> \
  --service-name <apim-name> \
  --backend-id orders-backend \
  --url $BACKEND_URL \
  --protocol http
```

> **重要**: `localhost` はAPIMからアクセスできません。必ずAzure Functionsにデプロイしたエンドポイントを使用してください。

### Step 4: APIM で API 作成

#### 4-1. API 定義作成

```powershell
# Azure Portal → APIM → APIs → Add API → Blank API

# Display name: Orders API
# Name: orders-api
# Web service URL: (空欄 - バックエンドで指定)
# API URL suffix: v1/orders
```

#### 4-2. Operation 追加

```powershell
# GET /v1/orders/{id}
# Display name: Get Order by ID
# URL: GET /{id}
# Backend: orders-backend

# 注意: Azure Functions のエンドポイントは /api/orders/{id} ですが、
# APIMでは /v1/orders/{id} としてルーティングします。
# バックエンドパスの変換は次のステップで設定します。
```

#### 4-3. バックエンドパス変換設定

Azure Functions は `/api/orders/{id}` でエンドポイントを公開していますが、APIMでは `/v1/orders/{id}` としてルーティングします。ポリシーで変換を設定します:

```xml
<policies>
    <inbound>
        <base />
        <!-- バックエンドパスを /api/orders/{id} に変換 -->
        <set-backend-service base-url="https://orders-api-1234.azurewebsites.net/api" />
        <rewrite-uri template="/orders/{id}" />
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

### Step 5: JWT 検証ポリシー適用

#### 5-1. Named Values 作成（推奨）

```powershell
# Azure Portal → APIM → Named values → Add

# Name: entra-tenant-id
# Value: <your-tenant-id>

# Name: orders-api-app-id
# Value: <server-api-app-id>
```

#### 5-2. ポリシー適用

`apim/policies/01-jwt-validation.xml` を編集:

```xml
<!-- {tenant-id} と {api-app-id} を置換 -->
<openid-config url="https://login.microsoftonline.com/{{entra-tenant-id}}/v2.0/.well-known/openid-configuration" />
<audiences>
    <audience>api://{{orders-api-app-id}}</audience>
</audiences>
```

Azure Portal で適用:
```
APIs → orders-api → Design → Inbound processing → </> (Code editor)
→ XML をペースト → Save
```

---

## 🧪 テスト手順

### Test 1: トークンなしでアクセス（401 期待）

```powershell
curl -i https://<apim-name>.azure-api.net/v1/orders/1001
```

期待結果:
```
HTTP/1.1 401 Unauthorized
Content-Type: application/json

{
  "statusCode": 401,
  "message": "Unauthorized: Invalid or missing token"
}
```

### Test 2: Entra ID トークン取得

#### オプション A: ブラウザ経由（推奨・ノーコード）

**前提条件（初回のみ）**:

1. Client App のアプリ登録で以下を設定:
   - **API permissions** に `OrdersAPI-Backend` の `Delegated permissions: Orders.Read` を追加
   - 管理者同意を付与（可能であれば）
   - **Authentication** → **Add a platform** → **Single-page application (SPA)**
   - **Redirect URIs** に `https://jwt.ms` を追加
   - **Implicit grant and hybrid flows** で **Access tokens** にチェック（重要）

2. 設定確認:
   ```powershell
   # Azure Portal → Client App → Authentication
   # Implicit grant and hybrid flows セクションで
   # ☑ Access tokens (used for implicit flows) にチェックが入っていることを確認
   ```

**取得手順**:

1. 以下のURLを自分の値で置き換えて、1行にまとめてブラウザで開く:

```
https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/authorize?client_id=<client-app-id>&response_type=token&redirect_uri=https%3A%2F%2Fjwt.ms&scope=api%3A%2F%2F<server-app-id>%2FOrders.Read%20openid%20profile&state=12345&nonce=67890
```

パラメータ説明:
- `<tenant-id>`: Azure AD テナント ID
- `<client-app-id>`: OrdersAPI-Client のアプリケーション ID
- `<server-app-id>`: OrdersAPI-Backend のアプリケーション ID

2. サインインを完了すると、`https://jwt.ms` にリダイレクトされます

3. 画面上部のテキスト欄（"Encoded" タブ）に表示される生トークンをコピー

4. PowerShell で変数に格納:

```powershell
# jwt.ms からコピーしたトークンを貼り付け
$TOKEN = "eyJ0eXAiOiJKV1QiLCJhbGc..."

# 確認
echo $TOKEN
```

> **ポイント**: `response_type=token`（インプリシットフロー）を使用するため、コード交換は不要です。テスト目的に最適ですが、本番環境では Authorization Code + PKCE の使用を推奨します。

#### オプション B: Azure CLI（代替方法）

```powershell
# スコープを指定してログイン
az login --tenant "<tenant-id>" --scope "api://<server-app-id>/.default"

# トークン取得
$TOKEN = az account get-access-token --resource "api://<server-app-id>" --query accessToken -o tsv

echo $TOKEN
```

> **注意**: この方法では Azure CLI の認証フローを使用するため、Client App の設定は不要です。

---

### Test 3: トークン付きでアクセス（200 期待）

```powershell
curl -i -H "Authorization: Bearer $TOKEN" https://<apim-name>.azure-api.net/v1/orders/1001
```

期待結果:
```json
{
  "id": "1001",
  "status": "confirmed",
  "customer": "山田太郎",
  "amount": 15000,
  "items": ["商品A", "商品B"]
}
```

### Test 4: バックエンドログ確認

Orders サービスのログ:
```
INFO:     Request from authenticated user: <oid> (<email>)
INFO:     Order 1001 found
```

**重要**: バックエンドコードに認証ロジックが**一切ない**ことを確認してください。

---

## 🔄 AWS での同等実装

### Step 1: HTTP API 作成

```bash
# AWS Console → API Gateway → Create API → HTTP API

# API name: orders-api
# Integrations: Add integration (HTTP, http://localhost:8001)
```

### Step 2: JWT Authorizer 設定

```bash
# Authorizations → Manage authorizers → Create

# Name: entra-jwt-authorizer
# Identity source: $request.header.Authorization
# Issuer URL: https://login.microsoftonline.com/<tenant-id>/v2.0
# Audience: api://<app-id>
```

### Step 3: ルートに Authorizer 適用

```bash
# Routes → GET /v1/orders/{id} → Authorization
# Authorizer: entra-jwt-authorizer
# Authorization scopes: Orders.Read
```

### Step 4: クレーム抽出（Lambda Authorizer が必要）

HTTP API の JWT Authorizer は **クレーム抽出→ヘッダー付与**に対応していないため、以下が必要:

1. **Lambda Authorizer (REQUEST)** に切り替え
2. Lambda 関数で JWT を検証
3. クレームを抽出して `context` に設定
4. Integration Request でヘッダーにマッピング

実装例（Lambda Node.js）:
```javascript
// aws/lambda/authorizer.js
const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');

const client = jwksClient({
  jwksUri: `https://login.microsoftonline.com/${process.env.TENANT_ID}/discovery/v2.0/keys`
});

function getKey(header, callback) {
  client.getSigningKey(header.kid, (err, key) => {
    const signingKey = key.publicKey || key.rsaPublicKey;
    callback(null, signingKey);
  });
}

exports.handler = async (event) => {
  const token = event.headers.authorization.replace('Bearer ', '');
  
  return new Promise((resolve, reject) => {
    jwt.verify(token, getKey, {
      audience: process.env.AUDIENCE,
      issuer: `https://login.microsoftonline.com/${process.env.TENANT_ID}/v2.0`
    }, (err, decoded) => {
      if (err) {
        reject('Unauthorized');
      } else {
        resolve({
          isAuthorized: true,
          context: {
            callerId: decoded.oid,
            callerEmail: decoded.email || decoded.upn
          }
        });
      }
    });
  });
};
```

**工数差分**: 約 50～100 行のコード + Lambda デプロイ設定

---

## 📊 比較表

| 項目 | APIM | AWS HTTP API | AWS Lambda Authorizer |
|------|------|--------------|----------------------|
| **設定箇所** | 1（ポリシーXML） | 2（Authorizer + ルート） | 3（Lambda + Authorizer + ルート） |
| **JWT 検証** | ポリシー（ノーコード） | ネイティブサポート | Lambda 実装 |
| **クレーム抽出** | ポリシー（C# expression） | 非サポート | Lambda 実装必要 |
| **ヘッダー付与** | ポリシー（set-header） | 非サポート | Integration Request マッピング |
| **コード行数** | 0 | 0 | 50～100 |
| **学習コスト** | 低（XMLポリシー） | 低 | 中～高（Lambda + JWT） |
| **設定時間** | 10～15分 | 5～10分 | 30～45分 |

---

## 🎓 学習ポイント

1. **バックエンド無改修**: FastAPI は認証ロジック不要
2. **ポリシーの力**: XMLで宣言的に認証・認可を実装
3. **セキュリティ分離**: ゲートウェイレイヤーで防御
4. **クレーム活用**: トークンから情報を抽出してビジネスロジックに渡す

---

## ❌ トラブルシューティング

### 問題: 401 Unauthorized が返る（トークン付きでも）

**原因**:
- `audience` が一致していない
- トークンの有効期限切れ
- スコープ不足

**確認**:
```powershell
# トークンをデコード
echo $TOKEN | cut -d'.' -f2 | base64 -d | jq .

# audience, aud, scp を確認
```

### 問題: クレーム抽出が動作しない

**原因**:
- JWT のペイロード構造が想定と異なる

**デバッグ**:
```xml
<!-- ポリシーに追加してレスポンスヘッダーでデバッグ -->
<set-header name="X-Debug-Token" exists-action="override">
    <value>@(context.Request.Headers.GetValueOrDefault("Authorization"))</value>
</set-header>
```

---

## 📚 次のステップ

- [シナリオB: レスポンス変換とモック](SCENARIO-B.md) に進む
- [AWS 実装詳細](../aws/README-AWS.md) を確認
- [比較結果を記録](COMPARISON.md)
