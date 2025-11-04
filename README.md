# APIM vs API Gateway Hands-on（Python×2サービス）

Azure API Management（APIM）が**設計・実装（開発）**と**運用管理**をどれだけ楽にするかを、最小の Python サービス2つを題材に**差が大きい3つのシナリオ**で体験します。

> **目的**: 短時間で "APIM だとここまでノーコード/省工数でできる" を体感し、AWS API Gateway との差分を**作業ステップと工数**で実感できるようにする。

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Python](https://img.shields.io/badge/python-3.10%2B-blue)
![Azure](https://img.shields.io/badge/azure-APIM-0078D4)

---

## 📋 目次

- [全体像](#-全体像アーキテクチャと題材)
- [クイックスタート](#-クイックスタート5分)
- [ハンズオンシナリオ](#-ハンズオン-シナリオ3本立て)
  - [シナリオA: ノーコード認証](#シナリオa-ノーコード認証entra-id)
  - [シナリオB: リクエスト/レスポンス変換＋モック応答](#シナリオb-リクエストレスポンス変換モック応答)
  - [シナリオC: プロダクト化＋開発者ポータル](#シナリオc-プロダクト化開発者ポータル)
- [評価観点](#-評価観点数値化のヒント)
- [実装指針](#-この後どう実装すべきか)
- [参考リンク](#-参考リンク)

---

## 🎯 全体像（アーキテクチャと題材）

```
┌─────────┐
│ Client  │
└────┬────┘
     │
     ▼
┌────────────────────────────────────────┐
│   Azure API Management (APIM)          │
│                                        │
│   ┌──────────────────────────────┐    │
│   │  Policies (ノーコード設定)    │    │
│   │  • JWT 認証（Entra ID）       │    │
│   │  • レスポンス変換             │    │
│   │  • モック応答                 │    │
│   │  • レート制限/クォータ        │    │
│   └──────────────────────────────┘    │
│                                        │
│   Routes:                              │
│   /v1/orders/*  → Service A (orders)   │
│   /v1/prices/*  → Service B (pricing)  │
└────────────────────────────────────────┘
            │                  │
            ▼                  ▼
    ┌──────────────┐   ┌──────────────┐
    │  Service A   │   │  Service B   │
    │   (orders)   │   │  (pricing)   │
    │              │   │              │
    │ Azure Funcs  │   │ Azure Funcs  │
    │ or Lambda    │   │ or Lambda    │
    └──────────────┘   └──────────────┘
```

### サービス概要

- **Service A (orders)**: 受注情報 API
  - エンドポイント: `GET /v1/orders/{id}`
  - **認証実装なし**（APIM が認証を担当）
  - デプロイ先: **Azure Functions** または **AWS Lambda**
  
- **Service B (pricing)**: 価格照会 API
  - エンドポイント: `GET /v1/prices/{sku}`
  - 旧フォーマットのまま（APIM でレスポンス変換）
  - デプロイ先: **Azure Functions** または **AWS Lambda**

> **注意**: ローカル開発用のFastAPIコード（`services/orders/`, `services/pricing/`）は参照実装として残していますが、実際のハンズオンではAzure FunctionsまたはAWS Lambdaにデプロイして使用します。

### 比較観点

| 機能 | APIM | AWS API Gateway |
|------|------|-----------------|
| 認証 | ポリシーXML | Lambda Authorizer |
| レスポンス変換 | C# expression | VTL |
| モック | ポリシー条件分岐 | Mock Integration / Lambda |
| レート制限 | Product ポリシー | Usage Plan |
| Developer Portal | 標準搭載 | 別途デプロイ（15～30分） |

---

## 🚀 クイックスタート（5分）

### 1. リポジトリのクローン

```powershell
git clone https://github.com/ishidahra01/azure-apim-handson.git
cd azure-apim-handson
```

### 2. バックエンドAPIのデプロイ

ハンズオンを行うには、まずバックエンドAPIをAzure FunctionsまたはAWS Lambdaにデプロイする必要があります。

#### オプション A: Azure Functions にデプロイ

```powershell
# Azure Functions にデプロイ（Azure CLIログイン済みであること）
.\scripts\deploy-azure-functions.ps1 `
    -ResourceGroupName "apim-handson-rg" `
    -Location "japaneast"

# デプロイ後、deployment-info.txt にエンドポイント情報が保存されます
```

**前提条件**:
- Azure CLI インストール済み
- Azure Functions Core Tools インストール済み (`npm install -g azure-functions-core-tools@4`)
- Azure にログイン済み (`az login`)

#### オプション B: AWS Lambda にデプロイ

```powershell
# AWS Lambda にデプロイ（AWS CLIとSAM CLI設定済みであること）
.\scripts\deploy-aws-lambda.ps1 `
    -StackName "apim-handson-apis" `
    -Region "ap-northeast-1"

# デプロイ後、deployment-info-aws.txt にエンドポイント情報が保存されます
```

**前提条件**:
- AWS CLI インストール済み
- AWS SAM CLI インストール済み
- AWS にログイン済み（`aws configure`）

#### ローカル開発（オプション）

APIの動作確認やカスタマイズをローカルで行う場合は、以下のコマンドを実行してください:

```powershell
# ローカルでFastAPIを起動（開発用）
.\scripts\setup-local.ps1
```

ブラウザで以下にアクセス:
- Orders API: <http://localhost:8001/docs>
- Pricing API: <http://localhost:8002/docs>

> **注意**: ローカル起動したAPIはAPIMのバックエンドとしては使用できません。実際のハンズオンではAzure FunctionsまたはAWS Lambdaにデプロイしてください。

### 3. ハンズオン開始

📖 [シナリオA: ノーコード認証](docs/SCENARIO-A.md) から開始してください。

---

## 📚 ハンズオン シナリオ（3本立て）

### シナリオA: ノーコード認証（Entra ID）

#### 🎯 狙い

バックエンドにコードを入れずに、APIM ポリシーだけで **OAuth2/JWT 検証**・**スコープ/claim 検査**・**ヘッダ付与**を行います。

#### ✅ 達成後の状態

- `/v1/orders/*` は **アクセストークン必須**（Entra ID 発行）
- トークンの `aud/scope` を **APIM ポリシー**で検査
- バックエンド FastAPI は **一切の認証コードなし**（要求は信頼済みヘッダで到達）

#### 📊 Azure vs AWS

| 項目 | APIM | AWS |
|------|------|-----|
| 設定箇所 | 1（ポリシーXML） | 2～3（Authorizer + ルート + Lambda） |
| コード行数 | 0 | 50～100（Lambda Authorizer） |
| クレーム抽出→ヘッダー | ポリシー内完結 | Lambda 実装必要 |
| 設定時間 | 10～15分 | 30～45分 |

📄 **詳細手順**: [docs/SCENARIO-A.md](docs/SCENARIO-A.md)

---

### シナリオB: リクエスト/レスポンス変換＋モック応答

#### 🎯 狙い

仕様変更時に **バックエンド無改修**で API の形を合わせ、**バックエンド未完成でも**モックでフロント開発を推進。

#### ✅ 達成後の状態

- `GET /v1/prices/{sku}` → **レスポンスシェイプを変換**
  - 旧: `{"sku", "price_jpy", "product_name", "category"}`
  - 新: `{"productCode", "amount", "currency", "name", "type"}`
- 一部の SKU (`SKU-MOCK`) は **モック応答**
- **Revision** 機能で新旧定義を安全に並行運用

#### 📊 Azure vs AWS

| 項目 | APIM | AWS |
|------|------|-----|
| レスポンス変換 | C# expression（直感的） | VTL（学習コスト高） |
| モック設定 | ポリシー条件分岐 | Lambda 関数必要 |
| 段階リリース | Revision（並行運用） | Stage（別URL） |
| 設定時間 | 15～20分 | 30～45分 |

📄 **詳細手順**: [docs/SCENARIO-B.md](docs/SCENARIO-B.md)

---

### シナリオC: プロダクト化＋開発者ポータル

#### 🎯 狙い

**利用者ごとの鍵配布、レート制限、クォータ**を**コード改修なし**で適用し、**ドキュメント自動公開**と**サインアップ**を体験。

#### ✅ 達成後の状態

- 「**Basic**: 10req/min, 10k/day」「**Partner**: 50req/min, 100k/day」等の **Product** を作成
- **サブスクリプションキー**でアクセス制御、キーごとに**レート/クォータ**適用
- **Developer Portal** に OpenAPI が自動掲出、Try-It で即試験可能

#### 📊 Azure vs AWS

| 項目 | APIM | AWS |
|------|------|-----|
| プロダクト管理 | Products（GUI一元） | Usage Plan（個別設定） |
| Developer Portal | 標準搭載 | 別途デプロイ（SAR） |
| Portal セットアップ | 0分（即利用可） | 15～30分 |
| Try-It 機能 | 標準装備 | 追加実装 |

📄 **詳細手順**: [docs/SCENARIO-C.md](docs/SCENARIO-C.md)

---

## 📊 評価観点（数値化のヒント）

### 総合比較（実測例）

| 項目 | APIM | AWS API Gateway | 差分 |
|------|-----:|----------------:|-----:|
| **総実装時間** | 2～3時間 | 5～8時間 | **60～70%削減** |
| **設定箇所数** | 5箇所 | 15箇所 | **3倍** |
| **コード行数** | 0行 | 150～200行 | **APIM完全ノーコード** |
| **ノーコード度** | 95% | 60% | **+35%** |
| **学習コスト** | 低 | 中～高 | **VTL/Lambda** |

### 評価シート

詳細な評価シートは [docs/COMPARISON.md](docs/COMPARISON.md) を使用して記録してください。

---

## 🛠️ 前提条件

### 必要なツール

- **Python 3.10+**
- **Azure CLI** (`az` コマンド)
- **Azure Portal** アクセス
- **Git**
- **PowerShell** (Windows) または **Bash** (macOS/Linux)
- **REST クライアント**（curl / Postman / VS Code REST Client）

### Azure リソース

- Azure サブスクリプション
- APIM インスタンス（Developer/Standard/Premium）
- Entra ID テナント（シナリオA用）
- （オプション）App Service / Container Apps（バックエンドデプロイ用）

### AWS リソース（比較用）

- AWS アカウント
- API Gateway（HTTP API / REST API）
- Lambda（Authorizer, Mock用）
- （オプション）Cognito（Developer Portal用）

---

## 📂 リポジトリ構成

```
azure-apim-handson/
├── services/              # バックエンドサービス（ローカル開発用）
│   ├── orders/           # FastAPI: 受注API（ローカル開発用）
│   ├── pricing/          # FastAPI: 価格API（ローカル開発用）
│   ├── orders-func/      # Azure Functions: 受注API
│   └── pricing-func/     # Azure Functions: 価格API
├── apim/
│   └── policies/         # APIM ポリシーXML
│       ├── 01-jwt-validation.xml
│       ├── 02-response-transformation.xml
│       ├── 03-mock-response.xml
│       └── 04-rate-limit-quota.xml
├── aws/                  # AWS 実装サンプル
│   ├── lambda/           # Lambda Functions
│   │   ├── authorizer/   # Lambda Authorizer（Entra ID JWT検証）
│   │   ├── orders/       # 受注API Lambda
│   │   └── pricing/      # 価格API Lambda
│   ├── templates/        # VTL テンプレート（レスポンス変換用）
│   └── README-AWS.md     # AWS 実装手順
├── docs/                 # ドキュメント
│   ├── SCENARIO-A.md     # シナリオA詳細
│   ├── SCENARIO-B.md     # シナリオB詳細
│   ├── SCENARIO-C.md     # シナリオC詳細
│   └── COMPARISON.md     # 評価シート
├── scripts/              # 自動化スクリプト
│   ├── setup-local.ps1   # ローカル環境セットアップ（開発用）
│   ├── deploy-azure-functions.ps1  # Azure Functions デプロイ
│   ├── deploy-aws-lambda.ps1       # AWS Lambda デプロイ
│   └── test-apis.ps1     # APIテスト
├── README.md             # このファイル
├── QUICKSTART.md         # クイックスタート
└── LICENSE               # MITライセンス
```

---

## 🚀 デプロイ詳細

### Azure Functions デプロイ

```powershell
# リソースグループ、ストレージアカウント、Function Appを自動作成
.\scripts\deploy-azure-functions.ps1 `
    -ResourceGroupName "apim-handson-rg" `
    -Location "japaneast" `
    -OrdersFunctionAppName "orders-api-1234" `    # オプション（指定しない場合はランダム生成）
    -PricingFunctionAppName "pricing-api-1234"    # オプション（指定しない場合はランダム生成）
```

デプロイ後のエンドポイント:
- Orders API: `https://{function-app-name}.azurewebsites.net/api/orders/{order_id}`
- Pricing API: `https://{function-app-name}.azurewebsites.net/api/prices/{sku}`

### AWS Lambda デプロイ

```powershell
# SAM を使用して Lambda + API Gateway をデプロイ
.\scripts\deploy-aws-lambda.ps1 `
    -StackName "apim-handson-apis" `
    -Region "ap-northeast-1"
```

デプロイ後のエンドポイント:
- Orders API: `https://{api-id}.execute-api.{region}.amazonaws.com/Prod/v1/orders/{order_id}`
- Pricing API: `https://{api-id}.execute-api.{region}.amazonaws.com/Prod/v1/prices/{sku}`

---

## 🎓 この後どう実装すべきか

### アーキテクチャ原則

1. **コードは極力シンプルに**
   - バックエンドAPIはビジネスロジックのみ
   - 認証・変換・レートは APIM/API Gateway ポリシーへ委譲

2. **サーバーレスアーキテクチャ**
   - Azure Functions / AWS Lambda でコスト効率化
   - スケーリングは自動、インフラ管理不要

3. **ポリシーの再利用**
   - 共通ポリシー（JWT検証・CORS）を **Policy Fragments** 化
   - API 間で継承・再利用

4. **環境分離**
   - Dev/Stg/Prod で **APIM 多インスタンス** または
   - 同一インスタンス＋**複数 Revision/Named Values**

### CI/CD

```powershell
# Azure DevOps / GitHub Actions でポリシー適用
az apim api operation policy create \
  --resource-group <rg> \
  --service-name <apim> \
  --api-id <api-id> \
  --operation-id <op-id> \
  --xml-policy @policy.xml
```

- **IaC**: Bicep / Terraform で APIM 定義管理
- **ポリシーバージョン管理**: Git で XML ポリシーを管理

### 可観測性

- **Application Insights 統合**: 相関 ID で E2E トレース
- **診断ログ**: Log Analytics Workspace に送信
- **ダッシュボード**: レート制限・認証失敗・レイテンシを可視化

### セキュリティ

- **Private Link / VNet 統合**: バックエンドをプライベート化
- **Azure Front Door + WAF**: フロントに配置
- **Managed Identity**: バックエンドへの認証
- **Credential Manager**: API キー/シークレット管理

---

## 🧹 クリーンアップ

### ローカル環境

```powershell
# サービス停止
.\scripts\setup-local.ps1 -StopServices
```

### Azure リソース削除

```powershell
# リソースグループごと削除
az group delete --name <resource-group-name> --yes --no-wait

# 個別削除
az apim delete --name <apim-name> --resource-group <resource-group-name>
```

### Entra ID アプリ登録削除

```powershell
az ad app delete --id <app-id>
```

---

## 📚 参考リンク

### Azure ドキュメント

- [API Management 概要](https://learn.microsoft.com/azure/api-management/api-management-key-concepts)
- [ポリシーリファレンス](https://learn.microsoft.com/azure/api-management/api-management-policies)
- [validate-jwt ポリシー](https://learn.microsoft.com/azure/api-management/validate-jwt-policy)
- [Entra ID での OAuth 2.0](https://learn.microsoft.com/azure/api-management/api-management-howto-protect-backend-with-aad)
- [Developer Portal カスタマイズ](https://learn.microsoft.com/azure/api-management/api-management-howto-developer-portal-customize)

### AWS ドキュメント

- [API Gateway 概要](https://docs.aws.amazon.com/apigateway/latest/developerguide/welcome.html)
- [HTTP API JWT Authorizer](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-jwt-authorizer.html)
- [REST API Mapping Templates](https://docs.aws.amazon.com/apigateway/latest/developerguide/models-mappings.html)
- [Developer Portal GitHub](https://github.com/awslabs/aws-api-gateway-developer-portal)

### 関連リソース

- [FastAPI ドキュメント](https://fastapi.tiangolo.com/)
- [Azure CLI リファレンス](https://learn.microsoft.com/cli/azure/)
- [Bicep ドキュメント](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)

---

## 🤝 コントリビューション

改善提案や追加シナリオの PR を歓迎します！

1. このリポジトリをフォーク
2. フィーチャーブランチを作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'Add amazing feature'`)
4. ブランチにプッシュ (`git push origin feature/amazing-feature`)
5. Pull Request を作成

---

## ❓ FAQ

### Q: APIM のコストは？

**A**: Developer tier（開発用）は約 $50/月。Standard tier（本番用）は約 $700/月。詳細は[価格ページ](https://azure.microsoft.com/pricing/details/api-management/)参照。

### Q: バックエンドを Azure 外にデプロイできる？

**A**: 可能です。APIM は任意の HTTP(S) エンドポイントをバックエンドに設定できます（オンプレミス、AWS、GCP など）。

### Q: AWS との連携は？

**A**: APIM から AWS のサービス（Lambda、EC2 など）を呼び出すことも可能です。認証は AWS Signature v4 を使用。

### Q: 本番環境での推奨構成は？

**A**: 
- APIM: Standard 以上（SLA 99.95%）
- VNet 統合でバックエンドをプライベート化
- Azure Front Door + WAF でセキュリティ強化
- Application Insights で可観測性
- Private Link で Entra ID 連携

---

## 📄 ライセンス

MIT License - 詳細は [LICENSE](LICENSE) を参照してください。

---

## 🎉 まとめ

このハンズオンを通じて、以下を体験できます:

✅ **バックエンド無改修**で認証・変換・レート制限を実装  
✅ **ノーコード/ローコード**で API 管理を実現  
✅ **APIM の優位性**を定量的に評価  
✅ **即座の Developer Portal** でユーザー体験向上  

**Next Steps**:
1. 📖 [QUICKSTART.md](QUICKSTART.md) でローカル環境構築
2. 🎯 [SCENARIO-A.md](docs/SCENARIO-A.md) で認証を実装
3. 📊 [COMPARISON.md](docs/COMPARISON.md) で評価を記録
4. 🚀 本番環境への適用を検討

---

**Happy Coding! 🚀**