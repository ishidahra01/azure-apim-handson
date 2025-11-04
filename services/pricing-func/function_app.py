"""
Pricing API Service - Azure Functions
価格照会を提供するHTTP Trigger Function

このサービスも認証・変換・レート制限などのロジックを含まず、
純粋なビジネスロジックのみを実装しています。
"""
import azure.functions as func
import logging
import json
from typing import Optional

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

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


@app.route(route="health", methods=["GET"])
def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """ヘルスチェック用エンドポイント"""
    logging.info('Health check requested.')
    
    return func.HttpResponse(
        json.dumps({
            "status": "healthy",
            "service": "pricing-api",
            "db_records": len(PRICES_DB),
            "endpoints": ["/api/health", "/api/prices/{sku}"]
        }),
        mimetype="application/json",
        status_code=200
    )


@app.route(route="prices/{sku}", methods=["GET"])
def get_price(req: func.HttpRequest) -> func.HttpResponse:
    """
    価格情報を取得（旧フォーマット）
    
    注意: このエンドポイントは旧フォーマットでレスポンスを返します。
    APIMのポリシーでレスポンスを変換して新フォーマットに対応できます。
    
    バックエンドのコード変更なしでAPIの仕様を変更できることを実証します。
    """
    sku = req.route_params.get('sku')
    
    # APIMから渡された認証情報を取得（デモ用）
    x_caller_id = req.headers.get('x-caller-id')
    
    if x_caller_id:
        logging.info(f"Price request from: {x_caller_id}")
    
    price = PRICES_DB.get(sku)
    
    if price:
        logging.info(f"Price for {sku} found: {price['price_jpy']} JPY")
        return func.HttpResponse(
            json.dumps(price, ensure_ascii=False),
            mimetype="application/json",
            status_code=200
        )
    else:
        logging.warning(f"Price for {sku} not found")
        return func.HttpResponse(
            json.dumps({
                "sku": sku,
                "price_jpy": None,
                "product_name": "不明",
                "category": "unknown"
            }, ensure_ascii=False),
            mimetype="application/json",
            status_code=404
        )
