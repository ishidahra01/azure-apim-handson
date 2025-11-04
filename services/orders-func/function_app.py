"""
Orders API Service - Azure Functions
受注情報を提供するHTTP Trigger Function

このサービスは認証・変換・レート制限などのロジックを含まず、
純粋なビジネスロジックのみを実装しています。
セキュリティやポリシーはAPI Management (APIM)で実装します。
"""
import azure.functions as func
import logging
import json
from typing import Optional

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

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


@app.route(route="health", methods=["GET"])
def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """ヘルスチェック用エンドポイント"""
    logging.info('Health check requested.')
    
    return func.HttpResponse(
        json.dumps({
            "status": "healthy",
            "service": "orders-api",
            "db_records": len(ORDERS_DB),
            "endpoints": ["/api/health", "/api/orders/{order_id}"]
        }),
        mimetype="application/json",
        status_code=200
    )


@app.route(route="orders/{order_id}", methods=["GET"])
def get_order(req: func.HttpRequest) -> func.HttpResponse:
    """
    受注情報を取得
    
    注意: このエンドポイントは認証ロジックを含みません。
    APIMが認証を行い、検証済みのヘッダー(x-caller-id等)を付与します。
    バックエンドは信頼済みヘッダーを使用してビジネスロジックを実行します。
    """
    order_id = req.route_params.get('order_id')
    
    # APIMから渡された認証情報を取得（デモ用）
    x_caller_id = req.headers.get('x-caller-id')
    x_caller_email = req.headers.get('x-caller-email')
    
    if x_caller_id:
        logging.info(f"Request from authenticated user: {x_caller_id} ({x_caller_email})")
    
    order = ORDERS_DB.get(order_id)
    
    if order:
        logging.info(f"Order {order_id} found")
        return func.HttpResponse(
            json.dumps(order, ensure_ascii=False),
            mimetype="application/json",
            status_code=200
        )
    else:
        logging.warning(f"Order {order_id} not found")
        return func.HttpResponse(
            json.dumps({
                "id": order_id,
                "status": "not-found",
                "message": "指定された注文は見つかりませんでした"
            }, ensure_ascii=False),
            mimetype="application/json",
            status_code=404
        )
