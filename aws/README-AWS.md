# AWS API Gateway 実装ガイド

このドキュメントでは、Azure APIM と同等の機能を AWS API Gateway で実装する手順を説明します。

## 📋 目次

- [環境準備](#環境準備)
- [シナリオA: JWT認証](#シナリオa-jwt認証)
- [シナリオB: レスポンス変換とモック](#シナリオb-レスポンス変換とモック)
- [シナリオC: Usage PlanとDeveloper Portal](#シナリオc-usage-planとdeveloper-portal)

---

## 環境準備

### 必要なツール

- AWS CLI v2
- Python 3.10+
- Node.js 16+ (Lambda Authorizer用)
- SAM CLI (Developer Portal デプロイ用)

### AWS CLIのセットアップ

```bash
# AWS CLI のインストール確認
aws --version

# 認証情報の設定
aws configure

# プロファイル使用の場合
aws configure --profile apim-handson
export AWS_PROFILE=apim-handson
```

### バックエンドサービスのデプロイ

#### オプション1: EC2 / ECS

```bash
# EC2 インスタンスにデプロイ
# または ECS Fargate でコンテナ実行
```

#### オプション2: Lambda 関数

```bash
# Lambda 用に FastAPI をラップ
# Mangum を使用
```

`aws/lambda/orders/handler.py`:

```python
from mangum import Mangum
from services.orders.app import app

handler = Mangum(app)
```

---

## シナリオA: JWT認証

### アーキテクチャ

```
Client → API Gateway (JWT Authorizer) → Lambda/HTTP Backend
```

### Step 1: HTTP API 作成

```bash
# HTTP API 作成
aws apigatewayv2 create-api \
  --name orders-api \
  --protocol-type HTTP \
  --target http://<backend-url>
```

### Step 2: JWT Authorizer 設定

```bash
ISSUER_URL="https://login.microsoftonline.com/<tenant-id>/v2.0"
AUDIENCE="api://<app-id>"

aws apigatewayv2 create-authorizer \
  --api-id <api-id> \
  --authorizer-type JWT \
  --name entra-jwt-authorizer \
  --identity-source '$request.header.Authorization' \
  --jwt-configuration Audience=[$AUDIENCE],Issuer=$ISSUER_URL
```

### Step 3: ルートに Authorizer を紐付け

```bash
aws apigatewayv2 create-route \
  --api-id <api-id> \
  --route-key 'GET /v1/orders/{id}' \
  --target integrations/<integration-id> \
  --authorization-type JWT \
  --authorizer-id <authorizer-id> \
  --authorization-scopes 'Orders.Read'
```

### 課題: クレーム抽出

HTTP API の JWT Authorizer は **クレーム抽出→ヘッダー付与に非対応**。

#### 解決策: Lambda Authorizer (REQUEST)

`aws/lambda/authorizer/entra-jwt.js`:

```javascript
const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');

const client = jwksClient({
  jwksUri: `https://login.microsoftonline.com/${process.env.TENANT_ID}/discovery/v2.0/keys`,
  cache: true,
  rateLimit: true
});

function getKey(header, callback) {
  client.getSigningKey(header.kid, (err, key) => {
    if (err) {
      callback(err);
    } else {
      const signingKey = key.getPublicKey();
      callback(null, signingKey);
    }
  });
}

exports.handler = async (event) => {
  const token = event.headers.authorization?.replace('Bearer ', '');
  
  if (!token) {
    throw new Error('Unauthorized');
  }
  
  return new Promise((resolve, reject) => {
    jwt.verify(token, getKey, {
      audience: process.env.AUDIENCE,
      issuer: `https://login.microsoftonline.com/${process.env.TENANT_ID}/v2.0`,
      algorithms: ['RS256']
    }, (err, decoded) => {
      if (err) {
        console.error('JWT verification failed:', err);
        reject('Unauthorized');
      } else {
        // クレームを context に設定
        resolve({
          isAuthorized: true,
          context: {
            callerId: decoded.oid || 'unknown',
            callerEmail: decoded.email || decoded.upn || 'unknown'
          }
        });
      }
    });
  });
};
```

デプロイ:

```bash
cd aws/lambda/authorizer
npm install jsonwebtoken jwks-rsa
zip -r function.zip .

aws lambda create-function \
  --function-name entra-jwt-authorizer \
  --runtime nodejs18.x \
  --role arn:aws:iam::<account-id>:role/lambda-execution-role \
  --handler entra-jwt.handler \
  --zip-file fileb://function.zip \
  --environment Variables={TENANT_ID=<tenant-id>,AUDIENCE=api://<app-id>} \
  --timeout 10
```

Lambda Authorizer として設定:

```bash
aws apigatewayv2 create-authorizer \
  --api-id <api-id> \
  --authorizer-type REQUEST \
  --name entra-lambda-authorizer \
  --authorizer-uri arn:aws:apigateway:<region>:lambda:path/2015-03-31/functions/arn:aws:lambda:<region>:<account-id>:function:entra-jwt-authorizer/invocations \
  --identity-source '$request.header.Authorization' \
  --authorizer-result-ttl-in-seconds 300
```

### Integration Request でヘッダーにマッピング

HTTP API の場合、Parameter mappings を使用:

```bash
aws apigatewayv2 update-integration \
  --api-id <api-id> \
  --integration-id <integration-id> \
  --request-parameters \
    'overwrite:header.x-caller-id=$context.authorizer.callerId' \
    'overwrite:header.x-caller-email=$context.authorizer.callerEmail'
```

---

## シナリオB: レスポンス変換とモック

### REST API が必要

HTTP API は **VTL非対応**、**レスポンス変換非対応**のため、REST API を使用。

### Step 1: REST API 作成

```bash
aws apigateway create-rest-api \
  --name pricing-api \
  --description "Pricing API with response transformation"
```

### Step 2: リソースとメソッド作成

```bash
# ルートリソースID取得
ROOT_ID=$(aws apigateway get-resources --rest-api-id <api-id> --query 'items[?path==`/`].id' --output text)

# /v1 リソース作成
V1_ID=$(aws apigateway create-resource \
  --rest-api-id <api-id> \
  --parent-id $ROOT_ID \
  --path-part v1 \
  --query 'id' --output text)

# /v1/prices リソース
PRICES_ID=$(aws apigateway create-resource \
  --rest-api-id <api-id> \
  --parent-id $V1_ID \
  --path-part prices \
  --query 'id' --output text)

# /v1/prices/{sku} リソース
SKU_ID=$(aws apigateway create-resource \
  --rest-api-id <api-id> \
  --parent-id $PRICES_ID \
  --path-part '{sku}' \
  --query 'id' --output text)

# GET メソッド作成
aws apigateway put-method \
  --rest-api-id <api-id> \
  --resource-id $SKU_ID \
  --http-method GET \
  --authorization-type NONE \
  --request-parameters method.request.path.sku=true
```

### Step 3: Integration (HTTP)

```bash
aws apigateway put-integration \
  --rest-api-id <api-id> \
  --resource-id $SKU_ID \
  --http-method GET \
  --type HTTP \
  --integration-http-method GET \
  --uri 'http://<backend-url>/v1/prices/{sku}' \
  --request-parameters integration.request.path.sku=method.request.path.sku
```

### Step 4: Integration Response (VTL でレスポンス変換)

```bash
aws apigateway put-integration-response \
  --rest-api-id <api-id> \
  --resource-id $SKU_ID \
  --http-method GET \
  --status-code 200 \
  --selection-pattern ''
```

VTL テンプレート設定:

```bash
aws apigateway put-integration-response \
  --rest-api-id <api-id> \
  --resource-id $SKU_ID \
  --http-method GET \
  --status-code 200 \
  --response-templates file://aws/templates/response-transform.vtl
```

`aws/templates/response-transform.vtl`:

```vtl
#set($inputRoot = $input.path('$'))
{
  "productCode": "$inputRoot.sku",
  "amount": $inputRoot.price_jpy,
  "currency": "JPY",
  "name": "$inputRoot.product_name",
  "type": "$inputRoot.category",
  "_metadata": {
    "transformedBy": "API-Gateway-VTL",
    "transformedAt": "$context.requestTime",
    "version": "2.0"
  }
}
```

### Step 5: Mock Integration

SKU-MOCK 用の Mock 統合は複雑なため、Lambda 関数で条件分岐を推奨:

`aws/lambda/pricing-mock/index.js`:

```javascript
exports.handler = async (event) => {
  const sku = event.pathParameters.sku;
  
  if (sku === 'SKU-MOCK' || sku.startsWith('SKU-DEV-')) {
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'X-Mocked-Response': 'true'
      },
      body: JSON.stringify({
        productCode: sku,
        amount: 999,
        currency: 'JPY',
        name: 'モック商品（開発用）',
        type: 'test',
        _metadata: {
          isMock: true,
          mockedBy: 'Lambda',
          mockedAt: new Date().toISOString()
        }
      })
    };
  }
  
  // 実バックエンドにプロキシ
  // HTTP client でバックエンド呼び出し
  // ...
};
```

---

## シナリオC: Usage PlanとDeveloper Portal

### Step 1: Usage Plan 作成

```bash
# Basic Usage Plan
BASIC_PLAN_ID=$(aws apigateway create-usage-plan \
  --name "Basic" \
  --description "10 req/min, 10k req/day" \
  --throttle rateLimit=10,burstLimit=20 \
  --quota limit=10000,period=DAY \
  --query 'id' --output text)

# Partner Usage Plan
PARTNER_PLAN_ID=$(aws apigateway create-usage-plan \
  --name "Partner" \
  --description "50 req/min, 100k req/day" \
  --throttle rateLimit=50,burstLimit=100 \
  --quota limit=100000,period=DAY \
  --query 'id' --output text)
```

### Step 2: API Stage を Usage Plan に関連付け

```bash
# API をデプロイ
aws apigateway create-deployment \
  --rest-api-id <api-id> \
  --stage-name prod

# Usage Plan に Stage を追加
aws apigateway update-usage-plan \
  --usage-plan-id $BASIC_PLAN_ID \
  --patch-operations \
    op=add,path=/apiStages,value=<api-id>:prod
```

### Step 3: API Key 作成と紐付け

```bash
# API Key 作成
BASIC_KEY_ID=$(aws apigateway create-api-key \
  --name "basic-dev-001" \
  --enabled \
  --query 'id' --output text)

# Usage Plan に Key を紐付け
aws apigateway create-usage-plan-key \
  --usage-plan-id $BASIC_PLAN_ID \
  --key-type API_KEY \
  --key-id $BASIC_KEY_ID

# Key の値を取得
aws apigateway get-api-key \
  --api-key $BASIC_KEY_ID \
  --include-value \
  --query 'value' --output text
```

### Step 4: Developer Portal のデプロイ

#### SAR (Serverless Application Repository) 経由

```bash
# AWS Console → Serverless Application Repository
# "api-gateway-dev-portal" を検索してデプロイ

# または SAM CLI
sam deploy \
  --template-file aws/developer-portal/template.yaml \
  --stack-name apim-dev-portal \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    CognitoIdentityPoolName=apim-dev-portal \
    DevPortalSiteS3BucketName=apim-dev-portal-bucket
```

構成:

- **S3**: 静的サイト
- **CloudFront**: CDN
- **Cognito**: ユーザープール
- **Lambda**: カタログAPI、サブスクリプション管理
- **DynamoDB**: ユーザーデータ

デプロイ時間: **約15～30分**

---

## 📊 総合比較表

| 機能 | APIM 実装 | AWS 実装 | APIM優位度 |
|------|----------|---------|-----------|
| **JWT認証** | ポリシーXML | Lambda Authorizer必要 | ⭐⭐⭐ |
| **クレーム抽出** | ポリシー内完結 | Lambda実装 | ⭐⭐⭐ |
| **レスポンス変換** | C# expression | VTL（学習コスト高） | ⭐⭐ |
| **モック応答** | ポリシー条件分岐 | Lambda関数 | ⭐⭐ |
| **レート制限** | ポリシー | Usage Plan | ⭐ |
| **Developer Portal** | 標準搭載 | 別途デプロイ（15～30分） | ⭐⭐⭐ |
| **設定の一元管理** | 1画面で完結 | 複数サービス横断 | ⭐⭐⭐ |
| **総工数** | 2～3時間 | 5～8時間 | ⭐⭐⭐ |

---

## 🎓 まとめ

### Azure APIM の優位性

1. **ノーコード度が高い**: ポリシーXMLで大半の処理を実装
2. **学習コストが低い**: VTL不要、Lambda不要
3. **即座のポータル**: Developer Portal がすぐ使える
4. **一元管理**: 1つのサービスで完結

### AWS の課題

1. **複数サービスの組み合わせ**: Lambda + API Gateway + Cognito + S3...
2. **VTL の学習**: レスポンス変換に必須
3. **Developer Portal**: 別途デプロイとカスタマイズが必要
4. **設定の分散**: Usage Plan、Key、Authorizer が別々

### 適切な選択

- **Azure APIM**: API管理を重視、迅速な開発、ノーコード重視
- **AWS API Gateway**: AWS エコシステム統合、Lambda中心、細かい制御が必要

---

## 📚 参考リンク

- [AWS API Gateway HTTP API](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api.html)
- [JWT Authorizers](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-jwt-authorizer.html)
- [Lambda Authorizers](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-lambda-authorizer.html)
- [Developer Portal GitHub](https://github.com/awslabs/aws-api-gateway-developer-portal)
