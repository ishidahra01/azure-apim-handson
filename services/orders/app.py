"""
Orders API Service - FastAPI
受注情報を提供するシンプルなAPIサービス

このサービスは認証・変換・レート制限などのロジックを含まず、
純粋なビジネスロジックのみを実装しています。
セキュリティやポリシーはAPI Gatewayレイヤー(APIM/API Gateway)で実装します。
"""
from fastapi import FastAPI, Header
from typing import Optional
import logging

# ログ設定
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Orders API",
    description="受注情報API - バックエンド側に認証実装なし",
    version="1.0.0"
)

# シンプルなインメモリDB
ORDERS_DB = {
    "1001": {
        "id": "1001",
        "status": "confirmed",
        "customer": "山田太郎",
        "amount": 15000,
        "items": ["商品A", "商品B"]
    },
    "1002": {
        "id": "1002",
        "status": "shipped",
        "customer": "佐藤花子",
        "amount": 25000,
        "items": ["商品C"]
    },
    "1003": {
        "id": "1003",
        "status": "pending",
        "customer": "鈴木一郎",
        "amount": 8500,
        "items": ["商品D", "商品E", "商品F"]
    }
}


@app.get("/")
def root():
    """ヘルスチェック用エンドポイント"""
    return {"service": "orders", "status": "healthy", "version": "1.0.0"}


@app.get("/v1/orders/{order_id}")
def get_order(
    order_id: str,
    x_caller_id: Optional[str] = Header(None),
    x_caller_email: Optional[str] = Header(None)
):
    """
    受注情報を取得
    
    注意: このエンドポイントは認証ロジックを含みません。
    APIM/API Gatewayが認証を行い、検証済みのヘッダー(x-caller-id等)を付与します。
    バックエンドは信頼済みヘッダーを使用してビジネスロジックを実行します。
    """
    # APIM/API Gatewayから渡された認証情報をログに記録（デモ用）
    if x_caller_id:
        logger.info(f"Request from authenticated user: {x_caller_id} ({x_caller_email})")
    
    order = ORDERS_DB.get(order_id)
    
    if order:
        logger.info(f"Order {order_id} found")
        return order
    else:
        logger.warning(f"Order {order_id} not found")
        return {
            "id": order_id,
            "status": "not-found",
            "message": "指定された注文は見つかりませんでした"
        }


@app.get("/health")
def health_check():
    """詳細なヘルスチェック"""
    return {
        "status": "healthy",
        "service": "orders-api",
        "db_records": len(ORDERS_DB),
        "endpoints": ["/", "/v1/orders/{order_id}", "/health"]
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
