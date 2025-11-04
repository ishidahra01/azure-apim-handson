# クイックスタートガイド

このガイドでは、最短でハンズオンを開始する手順を説明します。

## ⚡ 5分でスタート

### 1. リポジトリのクローン

```powershell
git clone https://github.com/your-org/azure-apim-handson.git
cd azure-apim-handson
```

### 2. 依存関係のインストールとサービス起動

```powershell
# 自動セットアップ（.venv仮想環境の作成 + 依存関係インストール + サービス起動 + テスト）
.\scripts\setup-local.ps1

# または個別に実行
.\scripts\setup-local.ps1 -InstallDependencies  # .venv作成 + パッケージインストール
.\scripts\setup-local.ps1 -StartServices        # サービス起動
.\scripts\setup-local.ps1 -TestAPIs             # APIテスト
```

> **Note**: スクリプトは自動的に `.venv` フォルダに仮想環境を作成し、依存関係を分離します。

### 3. 動作確認

ブラウザで以下にアクセス:
- Orders API: http://localhost:8001/docs
- Pricing API: http://localhost:8002/docs

### 4. ハンズオン開始

[シナリオA: ノーコード認証](docs/SCENARIO-A.md) から開始してください。

---

## 📚 詳細な手順

完全な手順は [README.md](README.md) を参照してください。

---

## 🆘 トラブルシューティング

### ポートが使用中

```powershell
# 使用中のポートを確認
Get-NetTCPConnection -LocalPort 8001,8002

# プロセスを停止
.\scripts\setup-local.ps1 -StopServices
```

### Python パッケージのエラー

```powershell
# 仮想環境を削除して再作成
Remove-Item -Recurse -Force .venv
.\scripts\setup-local.ps1 -InstallDependencies
```

### サービスが起動しない

```powershell
# ログを確認
Get-Job | Receive-Job

# 手動で起動してエラーを確認
cd services/orders
python -m uvicorn app:app --port 8001
```

---

## 💡 次のステップ

1. ✅ ローカル環境で動作確認
2. 📖 [シナリオA](docs/SCENARIO-A.md) を開始
3. 🔧 Azure Portal で APIM インスタンスを作成
4. 🚀 ハンズオン実施
5. 📊 [比較評価](docs/COMPARISON.md) を記録
