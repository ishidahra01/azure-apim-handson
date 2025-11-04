"""
Pricing API Service - FastAPI
価格照会を提供するシンプルなAPIサービス

このサービスも認証・変換・レート制限などのロジックを含まず、
純粋なビジネスロジックのみを実装しています。
"""
from fastapi import FastAPI, Header
from typing import Optional
import logging

# ログ設定
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Pricing API",
    description="価格照会API - レスポンス変換とモックのデモ用",
    version="1.0.0"
)

# シンプルなインメモリDB（旧フォーマット）
PRICES_DB = {
    "SKU-001": {
        "sku": "SKU-001",
        "price_jpy": 1200,
        "product_name": "ノートPC",
        "category": "electronics"
    },
    "SKU-002": {
        "sku": "SKU-002",
        "price_jpy": 8500,
        "product_name": "キーボード",
        "category": "accessories"
    },
    "SKU-003": {
        "sku": "SKU-003",
        "price_jpy": 3200,
        "product_name": "マウス",
        "category": "accessories"
    }
}


@app.get("/")
def root():
    """ヘルスチェック用エンドポイント"""
    return {"service": "pricing", "status": "healthy", "version": "1.0.0"}


@app.get("/v1/prices/{sku}")
def get_price(
    sku: str,
    x_caller_id: Optional[str] = Header(None)
):
    """
    価格情報を取得（旧フォーマット）
    
    注意: このエンドポイントは旧フォーマットでレスポンスを返します。
    APIM/API Gatewayのポリシーでレスポンスを変換して新フォーマットに対応できます。
    
    バックエンドのコード変更なしでAPIの仕様を変更できることを実証します。
    """
    if x_caller_id:
        logger.info(f"Price request from: {x_caller_id}")
    
    price = PRICES_DB.get(sku)
    
    if price:
        logger.info(f"Price for {sku} found: {price['price_jpy']} JPY")
        return price
    else:
        logger.warning(f"Price for {sku} not found")
        return {
            "sku": sku,
            "price_jpy": None,
            "product_name": "不明",
            "category": "unknown"
        }


@app.get("/health")
def health_check():
    """詳細なヘルスチェック"""
    return {
        "status": "healthy",
        "service": "pricing-api",
        "db_records": len(PRICES_DB),
        "endpoints": ["/", "/v1/prices/{sku}", "/health"]
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8002)
