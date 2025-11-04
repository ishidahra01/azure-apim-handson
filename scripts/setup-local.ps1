# ローカル環境セットアップスクリプト
# Azure APIM Hands-on

param(
    [switch]$InstallDependencies,
    [switch]$StartServices,
    [switch]$StopServices,
    [switch]$TestAPIs
)

$ErrorActionPreference = "Stop"

Write-Host "=== Azure APIM Hands-on - Local Setup ===" -ForegroundColor Cyan

# 現在のディレクトリを取得
$ROOT_DIR = Split-Path -Parent $PSScriptRoot
$VENV_DIR = "$ROOT_DIR\.venv"

function Install-Dependencies {
    Write-Host "`n[1/3] Setting up Python virtual environment..." -ForegroundColor Yellow
    
    # Check if Python is available
    try {
        $pythonVersion = python --version
        Write-Host "  - Python found: $pythonVersion" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Python not found. Please install Python 3.10 or higher." -ForegroundColor Red
        exit 1
    }
    
    # Create virtual environment if it doesn't exist
    if (-not (Test-Path $VENV_DIR)) {
        Write-Host "  - Creating virtual environment at $VENV_DIR..."
        python -m venv $VENV_DIR
        Write-Host "  ✓ Virtual environment created" -ForegroundColor Green
    } else {
        Write-Host "  - Virtual environment already exists" -ForegroundColor Green
    }
    
    # Activate virtual environment and install dependencies
    $activateScript = "$VENV_DIR\Scripts\Activate.ps1"
    
    Write-Host "`n[2/3] Installing Python dependencies..." -ForegroundColor Yellow
    
    # Orders service
    Write-Host "  - Installing orders service dependencies..."
    & $activateScript
    Push-Location "$ROOT_DIR\services\orders"
    python -m pip install -r requirements.txt --quiet
    Pop-Location
    
    # Pricing service
    Write-Host "  - Installing pricing service dependencies..."
    Push-Location "$ROOT_DIR\services\pricing"
    python -m pip install -r requirements.txt --quiet
    Pop-Location
    
    Write-Host "  ✓ Dependencies installed successfully" -ForegroundColor Green
}

function Start-Services {
    Write-Host "`n[3/3] Starting FastAPI services..." -ForegroundColor Yellow
    
    # Check if virtual environment exists
    if (-not (Test-Path $VENV_DIR)) {
        Write-Host "  ✗ Virtual environment not found. Run with -InstallDependencies first." -ForegroundColor Red
        exit 1
    }
    
    $pythonExe = "$VENV_DIR\Scripts\python.exe"
    
    # Orders service
    Write-Host "  - Starting Orders API on port 8001..."
    $ordersJob = Start-Job -ScriptBlock {
        Set-Location $using:ROOT_DIR\services\orders
        & $using:pythonExe -m uvicorn app:app --port 8001 --reload
    }
    
    # Pricing service
    Write-Host "  - Starting Pricing API on port 8002..."
    $pricingJob = Start-Job -ScriptBlock {
        Set-Location $using:ROOT_DIR\services\pricing
        & $using:pythonExe -m uvicorn app:app --port 8002 --reload
    }
    
    # Wait for services to start
    Start-Sleep -Seconds 3
    
    # Check if services are running
    try {
        $ordersResponse = Invoke-RestMethod -Uri "http://localhost:8001/" -TimeoutSec 5
        Write-Host "  ✓ Orders API started: $($ordersResponse.service)" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Orders API failed to start" -ForegroundColor Red
    }
    
    try {
        $pricingResponse = Invoke-RestMethod -Uri "http://localhost:8002/" -TimeoutSec 5
        Write-Host "  ✓ Pricing API started: $($pricingResponse.service)" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Pricing API failed to start" -ForegroundColor Red
    }
    
    Write-Host "`n  Services are running in background jobs." -ForegroundColor Cyan
    Write-Host "  Use 'Get-Job' to check status" -ForegroundColor Cyan
    Write-Host "  Use './scripts/setup-local.ps1 -StopServices' to stop" -ForegroundColor Cyan
}

function Stop-Services {
    Write-Host "`nStopping FastAPI services..." -ForegroundColor Yellow
    
    # Get all Python/uvicorn jobs
    Get-Job | Where-Object { $_.State -eq "Running" } | Stop-Job
    Get-Job | Remove-Job
    
    # Also kill any uvicorn processes on ports 8001/8002
    $processes = Get-NetTCPConnection -LocalPort 8001,8002 -ErrorAction SilentlyContinue | 
                 Select-Object -ExpandProperty OwningProcess -Unique
    
    foreach ($pid in $processes) {
        try {
            Stop-Process -Id $pid -Force
            Write-Host "  ✓ Stopped process $pid" -ForegroundColor Green
        } catch {
            Write-Host "  ✗ Failed to stop process $pid" -ForegroundColor Red
        }
    }
    
    Write-Host "  ✓ All services stopped" -ForegroundColor Green
}

function Test-APIs {
    Write-Host "`n[4/4] Testing APIs..." -ForegroundColor Yellow
    
    # Test Orders API
    Write-Host "`n  Testing Orders API..."
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:8001/v1/orders/1001"
        Write-Host "  ✓ GET /v1/orders/1001: $($response.status)" -ForegroundColor Green
        Write-Host "    Customer: $($response.customer), Amount: $($response.amount) JPY"
    } catch {
        Write-Host "  ✗ Orders API test failed" -ForegroundColor Red
    }
    
    # Test Pricing API
    Write-Host "`n  Testing Pricing API..."
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:8002/v1/prices/SKU-001"
        Write-Host "  ✓ GET /v1/prices/SKU-001: $($response.product_name)" -ForegroundColor Green
        Write-Host "    Price: $($response.price_jpy) JPY, Category: $($response.category)"
    } catch {
        Write-Host "  ✗ Pricing API test failed" -ForegroundColor Red
    }
    
    # Test Health endpoints
    Write-Host "`n  Testing Health endpoints..."
    try {
        $ordersHealth = Invoke-RestMethod -Uri "http://localhost:8001/health"
        Write-Host "  ✓ Orders Health: $($ordersHealth.status)" -ForegroundColor Green
        
        $pricingHealth = Invoke-RestMethod -Uri "http://localhost:8002/health"
        Write-Host "  ✓ Pricing Health: $($pricingHealth.status)" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Health check failed" -ForegroundColor Red
    }
}

# Main execution
try {
    if ($InstallDependencies) {
        Install-Dependencies
    }
    
    if ($StartServices) {
        Start-Services
    }
    
    if ($StopServices) {
        Stop-Services
        exit 0
    }
    
    if ($TestAPIs) {
        Test-APIs
    }
    
    # If no parameters, do all
    if (-not ($InstallDependencies -or $StartServices -or $StopServices -or $TestAPIs)) {
        Install-Dependencies
        Start-Services
        Test-APIs
        
        Write-Host "`n=== Setup Complete ===" -ForegroundColor Cyan
        Write-Host "Next steps:" -ForegroundColor Yellow
        Write-Host "  1. Open docs/SCENARIO-A.md to start the hands-on"
        Write-Host "  2. Access Developer Portal (if APIM is configured)"
        Write-Host "  3. Run './scripts/test-apis.ps1' for comprehensive tests"
    }
    
} catch {
    Write-Host "`n✗ Error: $_" -ForegroundColor Red
    exit 1
}
