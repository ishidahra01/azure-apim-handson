# Azure Functions デプロイスクリプト (Flex Consumption + Managed Identity)
# このスクリプトはOrders/Pricing APIをAzure Functionsにデプロイします

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$Location = "japaneast",
    
    [Parameter(Mandatory=$false)]
    [string]$OrdersFunctionAppName,
    
    [Parameter(Mandatory=$false)]
    [string]$PricingFunctionAppName,
    
    [Parameter(Mandatory=$false)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

Write-Host "=== Azure Functions デプロイ開始 (Flex Consumption + Managed Identity) ===" -ForegroundColor Green

# Function App名が指定されていない場合はランダム生成
if (-not $OrdersFunctionAppName) {
    $OrdersFunctionAppName = "orders-api-$(Get-Random -Minimum 1000 -Maximum 9999)"
}
if (-not $PricingFunctionAppName) {
    $PricingFunctionAppName = "pricing-api-$(Get-Random -Minimum 1000 -Maximum 9999)"
}
if (-not $StorageAccountName) {
    $StorageAccountName = "apimhandson$(Get-Random -Minimum 1000 -Maximum 9999)"
}

# 1. リソースグループ作成（存在する場合はスキップ）
Write-Host "1. リソースグループ確認/作成: $ResourceGroupName" -ForegroundColor Cyan
$rgExists = az group exists --name $ResourceGroupName
if ($rgExists -eq "false") {
    az group create --name $ResourceGroupName --location $Location
    Write-Host "  リソースグループを作成しました" -ForegroundColor Green
} else {
    Write-Host "  リソースグループは既に存在します" -ForegroundColor Yellow
}

# 2. Storage Account作成または確認（Function App用）
Write-Host "2. Storage Account確認/作成: $StorageAccountName" -ForegroundColor Cyan
$storageExists = az storage account check-name --name $StorageAccountName --query "nameAvailable" -o tsv
if ($storageExists -eq "true") {
    az storage account create `
        --name $StorageAccountName `
        --resource-group $ResourceGroupName `
        --location $Location `
        --sku Standard_LRS `
        --kind StorageV2 `
        --min-tls-version TLS1_2 `
        --allow-blob-public-access false
    Write-Host "  Storage Accountを作成しました" -ForegroundColor Green
} else {
    Write-Host "  Storage Accountは既に存在します" -ForegroundColor Yellow
}

# 3. Orders Function App作成または更新 (Flex Consumption)
Write-Host "3. Orders Function App確認/作成: $OrdersFunctionAppName" -ForegroundColor Cyan
$ordersExists = az functionapp show --name $OrdersFunctionAppName --resource-group $ResourceGroupName 2>$null
if (-not $ordersExists) {
    az functionapp create `
        --resource-group $ResourceGroupName `
        --name $OrdersFunctionAppName `
        --storage-account $StorageAccountName `
        --runtime python `
        --runtime-version 3.11 `
        --functions-version 4 `
        --flexconsumption-location $Location `
        --os-type Linux `
        --assign-identity [system]
    Write-Host "  Orders Function Appを作成しました (Flex Consumption)" -ForegroundColor Green
} else {
    Write-Host "  Orders Function Appは既に存在します" -ForegroundColor Yellow
}

# Orders Function AppにManaged Identityが有効でない場合は有効化
Write-Host "  Orders Function App: Managed Identity確認..." -ForegroundColor Cyan
$ordersIdentity = az functionapp identity show --name $OrdersFunctionAppName --resource-group $ResourceGroupName 2>$null
if (-not $ordersIdentity) {
    az functionapp identity assign --name $OrdersFunctionAppName --resource-group $ResourceGroupName
    Write-Host "  System Managed Identityを有効化しました" -ForegroundColor Green
}

# 4. Pricing Function App作成または更新 (Flex Consumption)
Write-Host "4. Pricing Function App確認/作成: $PricingFunctionAppName" -ForegroundColor Cyan
$pricingExists = az functionapp show --name $PricingFunctionAppName --resource-group $ResourceGroupName 2>$null
if (-not $pricingExists) {
    az functionapp create `
        --resource-group $ResourceGroupName `
        --name $PricingFunctionAppName `
        --storage-account $StorageAccountName `
        --runtime python `
        --runtime-version 3.11 `
        --functions-version 4 `
        --flexconsumption-location $Location `
        --os-type Linux `
        --assign-identity [system]
    Write-Host "  Pricing Function Appを作成しました (Flex Consumption)" -ForegroundColor Green
} else {
    Write-Host "  Pricing Function Appは既に存在します" -ForegroundColor Yellow
}

# Pricing Function AppにManaged Identityが有効でない場合は有効化
Write-Host "  Pricing Function App: Managed Identity確認..." -ForegroundColor Cyan
$pricingIdentity = az functionapp identity show --name $PricingFunctionAppName --resource-group $ResourceGroupName 2>$null
if (-not $pricingIdentity) {
    az functionapp identity assign --name $PricingFunctionAppName --resource-group $ResourceGroupName
    Write-Host "  System Managed Identityを有効化しました" -ForegroundColor Green
}

# 5. Storage AccountへのManaged Identityアクセス権付与
Write-Host "5. Storage Accountアクセス権設定 (Managed Identity)..." -ForegroundColor Cyan

# Storage AccountのリソースIDを取得
$storageId = az storage account show --name $StorageAccountName --resource-group $ResourceGroupName --query "id" -o tsv

# Orders Function AppのManaged Identity (Principal ID)を取得
$ordersPrincipalId = az functionapp identity show --name $OrdersFunctionAppName --resource-group $ResourceGroupName --query "principalId" -o tsv

# Pricing Function AppのManaged Identity (Principal ID)を取得
$pricingPrincipalId = az functionapp identity show --name $PricingFunctionAppName --resource-group $ResourceGroupName --query "principalId" -o tsv

# ロール割り当て: Storage Blob Data Owner (デプロイ管理用)
az role assignment create `
    --assignee $ordersPrincipalId `
    --role "Storage Blob Data Owner" `
    --scope $storageId `
    2>$null
Write-Host "  Orders Function App: Storage Blob Data Owner 権限を付与しました" -ForegroundColor Green

az role assignment create `
    --assignee $pricingPrincipalId `
    --role "Storage Blob Data Owner" `
    --scope $storageId `
    2>$null
Write-Host "  Pricing Function App: Storage Blob Data Owner 権限を付与しました" -ForegroundColor Green

# 接続文字列をManaged Identity方式に変更
Write-Host "6. 接続文字列をManaged Identity方式に更新..." -ForegroundColor Cyan
az functionapp config appsettings set `
    --name $OrdersFunctionAppName `
    --resource-group $ResourceGroupName `
    --settings "AzureWebJobsStorage__accountName=$StorageAccountName" `
    2>$null

az functionapp config appsettings set `
    --name $PricingFunctionAppName `
    --resource-group $ResourceGroupName `
    --settings "AzureWebJobsStorage__accountName=$StorageAccountName" `
    2>$null
Write-Host "  Managed Identity接続を設定しました" -ForegroundColor Green

# 7. Orders Function デプロイ
Write-Host "`n7. Orders Function デプロイ中..." -ForegroundColor Cyan
Push-Location "$PSScriptRoot\..\services\orders-func"
try {
    func azure functionapp publish $OrdersFunctionAppName --python
    Write-Host "  Orders Function デプロイ完了" -ForegroundColor Green
} catch {
    Write-Host "  警告: Orders Function デプロイに失敗しました: $_" -ForegroundColor Red
}
Pop-Location

# 8. Pricing Function デプロイ
Write-Host "8. Pricing Function デプロイ中..." -ForegroundColor Cyan
Push-Location "$PSScriptRoot\..\services\pricing-func"
try {
    func azure functionapp publish $PricingFunctionAppName --python
    Write-Host "  Pricing Function デプロイ完了" -ForegroundColor Green
} catch {
    Write-Host "  警告: Pricing Function デプロイに失敗しました: $_" -ForegroundColor Red
}
Pop-Location

# 9. 結果表示
Write-Host "`n=== デプロイ完了 ===" -ForegroundColor Green
Write-Host "Orders API: https://$OrdersFunctionAppName.azurewebsites.net" -ForegroundColor Yellow
Write-Host "  - Health: https://$OrdersFunctionAppName.azurewebsites.net/api/health" -ForegroundColor Yellow
Write-Host "  - Get Order: https://$OrdersFunctionAppName.azurewebsites.net/api/orders/{order_id}" -ForegroundColor Yellow
Write-Host ""
Write-Host "Pricing API: https://$PricingFunctionAppName.azurewebsites.net" -ForegroundColor Yellow
Write-Host "  - Health: https://$PricingFunctionAppName.azurewebsites.net/api/health" -ForegroundColor Yellow
Write-Host "  - Get Price: https://$PricingFunctionAppName.azurewebsites.net/api/prices/{sku}" -ForegroundColor Yellow
Write-Host ""
Write-Host "APIMのバックエンド設定で上記URLを使用してください" -ForegroundColor Cyan

# 10. 環境変数を出力ファイルに保存（APIM設定用）
$OutputFile = "$PSScriptRoot\..\deployment-info.txt"
@"
=== Azure Functions デプロイ情報 (Flex Consumption + Managed Identity) ===
作成日時: $(Get-Date)
リソースグループ: $ResourceGroupName
リージョン: $Location
Storage Account: $StorageAccountName

Orders Function App:
  名前: $OrdersFunctionAppName
  URL: https://$OrdersFunctionAppName.azurewebsites.net
  Health: https://$OrdersFunctionAppName.azurewebsites.net/api/health
  プラン: Flex Consumption
  認証: System Managed Identity

Pricing Function App:
  名前: $PricingFunctionAppName
  URL: https://$PricingFunctionAppName.azurewebsites.net
  Health: https://$PricingFunctionAppName.azurewebsites.net/api/health
  プラン: Flex Consumption
  認証: System Managed Identity

=== APIM バックエンド設定用 ===
Orders Backend URL: https://$OrdersFunctionAppName.azurewebsites.net
Pricing Backend URL: https://$PricingFunctionAppName.azurewebsites.net

=== 再デプロイ用コマンド ===
.\scripts\deploy-azure-functions.ps1 `
    -ResourceGroupName "$ResourceGroupName" `
    -Location "$Location" `
    -OrdersFunctionAppName "$OrdersFunctionAppName" `
    -PricingFunctionAppName "$PricingFunctionAppName" `
    -StorageAccountName "$StorageAccountName"
"@ | Out-File -FilePath $OutputFile -Encoding UTF8

Write-Host "`nデプロイ情報を $OutputFile に保存しました" -ForegroundColor Green
Write-Host "`n=== 再デプロイ時の注意 ===" -ForegroundColor Cyan
Write-Host "既存リソースを使用する場合は、上記ファイルに記載されたコマンドを使用してください" -ForegroundColor Cyan
