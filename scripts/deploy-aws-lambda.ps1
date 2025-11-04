# AWS Lambda デプロイスクリプト
# このスクリプトはOrders/Pricing APIをAWS Lambdaにデプロイします

param(
    [Parameter(Mandatory=$true)]
    [string]$StackName = "apim-handson-apis",
    
    [Parameter(Mandatory=$true)]
    [string]$Region = "ap-northeast-1",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

Write-Host "=== AWS Lambda デプロイ開始 ===" -ForegroundColor Green

# 1. 依存関係パッケージング（Orders）
if (-not $SkipBuild) {
    Write-Host "1. Orders Lambda パッケージング..." -ForegroundColor Cyan
    Push-Location "$PSScriptRoot\..\aws\lambda\orders"
    
    if (Test-Path "package") {
        Remove-Item -Recurse -Force "package"
    }
    New-Item -ItemType Directory -Path "package" | Out-Null
    
    pip install -r requirements.txt -t package/
    Copy-Item app.py package/
    
    Push-Location "package"
    Compress-Archive -Path * -DestinationPath "../orders-lambda.zip" -Force
    Pop-Location
    Pop-Location
    
    # 2. 依存関係パッケージング（Pricing）
    Write-Host "2. Pricing Lambda パッケージング..." -ForegroundColor Cyan
    Push-Location "$PSScriptRoot\..\aws\lambda\pricing"
    
    if (Test-Path "package") {
        Remove-Item -Recurse -Force "package"
    }
    New-Item -ItemType Directory -Path "package" | Out-Null
    
    pip install -r requirements.txt -t package/
    Copy-Item app.py package/
    
    Push-Location "package"
    Compress-Archive -Path * -DestinationPath "../pricing-lambda.zip" -Force
    Pop-Location
    Pop-Location
}

# 3. SAM/CloudFormationテンプレート作成
Write-Host "3. CloudFormation テンプレート作成..." -ForegroundColor Cyan
$TemplateContent = @"
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Description: APIM Handson - Orders and Pricing APIs

Resources:
  OrdersFunction:
    Type: AWS::Serverless::Function
    Properties:
      FunctionName: !Sub '\${AWS::StackName}-orders'
      Runtime: python3.11
      Handler: app.handler
      CodeUri: ../../aws/lambda/orders/orders-lambda.zip
      MemorySize: 256
      Timeout: 30
      Events:
        GetOrder:
          Type: Api
          Properties:
            Path: /v1/orders/{order_id}
            Method: GET
        Health:
          Type: Api
          Properties:
            Path: /health
            Method: GET

  PricingFunction:
    Type: AWS::Serverless::Function
    Properties:
      FunctionName: !Sub '\${AWS::StackName}-pricing'
      Runtime: python3.11
      Handler: app.handler
      CodeUri: ../../aws/lambda/pricing/pricing-lambda.zip
      MemorySize: 256
      Timeout: 30
      Events:
        GetPrice:
          Type: Api
          Properties:
            Path: /v1/prices/{sku}
            Method: GET
        Health:
          Type: Api
          Properties:
            Path: /health
            Method: GET

Outputs:
  OrdersApiUrl:
    Description: Orders API Gateway URL
    Value: !Sub 'https://\${ServerlessRestApi}.execute-api.\${AWS::Region}.amazonaws.com/Prod/v1/orders'
  
  PricingApiUrl:
    Description: Pricing API Gateway URL
    Value: !Sub 'https://\${ServerlessRestApi}.execute-api.\${AWS::Region}.amazonaws.com/Prod/v1/prices'
  
  OrdersFunctionArn:
    Description: Orders Lambda Function ARN
    Value: !GetAtt OrdersFunction.Arn
  
  PricingFunctionArn:
    Description: Pricing Lambda Function ARN
    Value: !GetAtt PricingFunction.Arn
"@

$TemplateFile = "$PSScriptRoot\..\aws\cloudformation-template.yaml"
$TemplateContent | Out-File -FilePath $TemplateFile -Encoding UTF8

# 4. SAM デプロイ
Write-Host "4. SAM デプロイ実行..." -ForegroundColor Cyan
Push-Location "$PSScriptRoot\.."
sam deploy `
    --template-file aws/cloudformation-template.yaml `
    --stack-name $StackName `
    --region $Region `
    --capabilities CAPABILITY_IAM `
    --no-confirm-changeset `
    --no-fail-on-empty-changeset
Pop-Location

# 5. 結果取得
Write-Host "`n=== デプロイ完了 ===" -ForegroundColor Green
$Outputs = aws cloudformation describe-stacks `
    --stack-name $StackName `
    --region $Region `
    --query 'Stacks[0].Outputs' `
    --output json | ConvertFrom-Json

foreach ($Output in $Outputs) {
    Write-Host "$($Output.Description): $($Output.OutputValue)" -ForegroundColor Yellow
}

# 6. 環境変数を出力ファイルに保存
$OutputFile = "$PSScriptRoot\..\deployment-info-aws.txt"
$OrdersUrl = ($Outputs | Where-Object { $_.OutputKey -eq "OrdersApiUrl" }).OutputValue
$PricingUrl = ($Outputs | Where-Object { $_.OutputKey -eq "PricingApiUrl" }).OutputValue

@"
=== AWS Lambda デプロイ情報 ===
作成日時: $(Get-Date)
スタック名: $StackName
リージョン: $Region

Orders API:
  URL: $OrdersUrl
  Example: $OrdersUrl/1001

Pricing API:
  URL: $PricingUrl
  Example: $PricingUrl/SKU-001

=== API Gateway 設定用 ===
Orders Backend URL: $OrdersUrl
Pricing Backend URL: $PricingUrl
"@ | Out-File -FilePath $OutputFile -Encoding UTF8

Write-Host "デプロイ情報を $OutputFile に保存しました" -ForegroundColor Green
