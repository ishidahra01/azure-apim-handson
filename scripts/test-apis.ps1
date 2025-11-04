# API テストスクリプト
# APIM と AWS API Gateway の動作確認用

param(
    [string]$ApimUrl = "",
    [string]$AwsUrl = "",
    [string]$SubscriptionKey = "",
    [string]$AwsApiKey = "",
    [string]$Token = ""
)

$ErrorActionPreference = "Continue"

Write-Host "=== API Testing Script ===" -ForegroundColor Cyan

# ローカル環境のテスト
function Test-LocalAPIs {
    Write-Host "`n[Local] Testing backend services..." -ForegroundColor Yellow
    
    # Orders API
    Write-Host "`n1. Orders API - GET /v1/orders/1001"
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:8001/v1/orders/1001"
        Write-Host "   ✓ Status: $($response.status)" -ForegroundColor Green
        $response | ConvertTo-Json -Depth 3
    } catch {
        Write-Host "   ✗ Failed: $_" -ForegroundColor Red
    }
    
    # Pricing API
    Write-Host "`n2. Pricing API - GET /v1/prices/SKU-001"
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:8002/v1/prices/SKU-001"
        Write-Host "   ✓ Product: $($response.product_name)" -ForegroundColor Green
        $response | ConvertTo-Json -Depth 3
    } catch {
        Write-Host "   ✗ Failed: $_" -ForegroundColor Red
    }
}

# APIM のテスト
function Test-APIM {
    param([string]$BaseUrl, [string]$SubKey, [string]$AuthToken)
    
    Write-Host "`n[APIM] Testing Azure API Management..." -ForegroundColor Yellow
    
    $headers = @{}
    if ($SubKey) {
        $headers["Ocp-Apim-Subscription-Key"] = $SubKey
    }
    if ($AuthToken) {
        $headers["Authorization"] = "Bearer $AuthToken"
    }
    
    # Test 1: Orders API without token (should fail if JWT validation is enabled)
    Write-Host "`n1. Orders API - Without token (expecting 401 if JWT enabled)"
    try {
        $response = Invoke-WebRequest -Uri "$BaseUrl/v1/orders/1001" -Headers @{"Ocp-Apim-Subscription-Key"=$SubKey} -SkipHttpErrorCheck
        Write-Host "   Status: $($response.StatusCode)" -ForegroundColor Cyan
        if ($response.StatusCode -eq 401) {
            Write-Host "   ✓ JWT validation working" -ForegroundColor Green
        }
    } catch {
        Write-Host "   ✗ Failed: $_" -ForegroundColor Red
    }
    
    # Test 2: Orders API with token
    if ($AuthToken) {
        Write-Host "`n2. Orders API - With token"
        try {
            $response = Invoke-RestMethod -Uri "$BaseUrl/v1/orders/1001" -Headers $headers
            Write-Host "   ✓ Success" -ForegroundColor Green
            $response | ConvertTo-Json -Depth 3
        } catch {
            Write-Host "   ✗ Failed: $_" -ForegroundColor Red
        }
    }
    
    # Test 3: Pricing API - Transformation check
    Write-Host "`n3. Pricing API - Response transformation (SKU-001)"
    try {
        $response = Invoke-RestMethod -Uri "$BaseUrl/v1/prices/SKU-001" -Headers @{"Ocp-Apim-Subscription-Key"=$SubKey}
        Write-Host "   ✓ Success" -ForegroundColor Green
        
        # Check if transformed
        if ($response.PSObject.Properties["productCode"]) {
            Write-Host "   ✓ Response transformed (new format)" -ForegroundColor Green
        } else {
            Write-Host "   ⚠ Response NOT transformed (old format)" -ForegroundColor Yellow
        }
        
        $response | ConvertTo-Json -Depth 3
    } catch {
        Write-Host "   ✗ Failed: $_" -ForegroundColor Red
    }
    
    # Test 4: Pricing API - Mock response
    Write-Host "`n4. Pricing API - Mock response (SKU-MOCK)"
    try {
        $response = Invoke-WebRequest -Uri "$BaseUrl/v1/prices/SKU-MOCK" -Headers @{"Ocp-Apim-Subscription-Key"=$SubKey}
        $body = $response.Content | ConvertFrom-Json
        
        Write-Host "   ✓ Status: $($response.StatusCode)" -ForegroundColor Green
        
        # Check mock header
        $mockHeader = $response.Headers["X-Mocked-Response"]
        if ($mockHeader -eq "true") {
            Write-Host "   ✓ Mock response confirmed" -ForegroundColor Green
        }
        
        $body | ConvertTo-Json -Depth 3
    } catch {
        Write-Host "   ✗ Failed: $_" -ForegroundColor Red
    }
    
    # Test 5: Rate limiting
    Write-Host "`n5. Rate limiting test (10 requests)"
    $successCount = 0
    $rateLimitedCount = 0
    
    for ($i = 1; $i -le 12; $i++) {
        try {
            $response = Invoke-WebRequest -Uri "$BaseUrl/v1/orders/1001" -Headers @{"Ocp-Apim-Subscription-Key"=$SubKey} -SkipHttpErrorCheck
            if ($response.StatusCode -eq 200) {
                $successCount++
                Write-Host "   [$i] 200 OK" -ForegroundColor Green
            } elseif ($response.StatusCode -eq 429) {
                $rateLimitedCount++
                Write-Host "   [$i] 429 Rate Limited" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "   [$i] Error" -ForegroundColor Red
        }
        Start-Sleep -Milliseconds 100
    }
    
    Write-Host "`n   Summary: $successCount success, $rateLimitedCount rate-limited" -ForegroundColor Cyan
    if ($rateLimitedCount -gt 0) {
        Write-Host "   ✓ Rate limiting working" -ForegroundColor Green
    }
}

# AWS のテスト
function Test-AWS {
    param([string]$BaseUrl, [string]$ApiKey, [string]$AuthToken)
    
    Write-Host "`n[AWS] Testing API Gateway..." -ForegroundColor Yellow
    
    $headers = @{}
    if ($ApiKey) {
        $headers["x-api-key"] = $ApiKey
    }
    if ($AuthToken) {
        $headers["Authorization"] = "Bearer $AuthToken"
    }
    
    # Similar tests as APIM
    Write-Host "`n1. Orders API"
    try {
        $response = Invoke-RestMethod -Uri "$BaseUrl/v1/orders/1001" -Headers $headers
        Write-Host "   ✓ Success" -ForegroundColor Green
        $response | ConvertTo-Json -Depth 3
    } catch {
        Write-Host "   ✗ Failed: $_" -ForegroundColor Red
    }
    
    Write-Host "`n2. Pricing API - VTL transformation"
    try {
        $response = Invoke-RestMethod -Uri "$BaseUrl/v1/prices/SKU-001" -Headers $headers
        Write-Host "   ✓ Success" -ForegroundColor Green
        $response | ConvertTo-Json -Depth 3
    } catch {
        Write-Host "   ✗ Failed: $_" -ForegroundColor Red
    }
}

# 比較レポート
function Show-Comparison {
    Write-Host "`n=== Comparison Report ===" -ForegroundColor Cyan
    
    Write-Host "`n| Feature | APIM | AWS | Winner |"
    Write-Host "|---------|------|-----|--------|"
    Write-Host "| JWT Auth (no-code) | ✓ | ✗ (Lambda) | APIM |"
    Write-Host "| Response Transform | ✓ (C#) | ✓ (VTL) | APIM |"
    Write-Host "| Mock Response | ✓ (Policy) | ✓ (Lambda) | APIM |"
    Write-Host "| Rate Limiting | ✓ | ✓ | Tie |"
    Write-Host "| Developer Portal | ✓ (Built-in) | ✗ (Deploy) | APIM |"
    Write-Host ""
}

# Main execution
if ($ApimUrl) {
    Test-APIM -BaseUrl $ApimUrl -SubKey $SubscriptionKey -AuthToken $Token
}

if ($AwsUrl) {
    Test-AWS -BaseUrl $AwsUrl -ApiKey $AwsApiKey -AuthToken $Token
}

if (-not $ApimUrl -and -not $AwsUrl) {
    Test-LocalAPIs
}

Show-Comparison

Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan
Write-Host "`nUsage examples:"
Write-Host "  Local: ./test-apis.ps1"
Write-Host "  APIM:  ./test-apis.ps1 -ApimUrl 'https://your-apim.azure-api.net' -SubscriptionKey 'key'"
Write-Host "  AWS:   ./test-apis.ps1 -AwsUrl 'https://your-api-id.execute-api.region.amazonaws.com' -AwsApiKey 'key'"
