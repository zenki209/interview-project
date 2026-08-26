import os
import socket
import uuid
import requests
from flask import Flask, jsonify, request

app = Flask(__name__)

PRODUCT_SERVICE_URL = os.environ.get("PRODUCT_SERVICE_URL", "http://product-service")
HOSTNAME = socket.gethostname()


@app.route("/orders", methods=["POST"])
def create_order():
    body = request.get_json(silent=True) or {}
    product_id = body.get("product_id")
    if not product_id:
        return jsonify({"error": "product_id is required"}), 400

    try:
        resp = requests.get(f"{PRODUCT_SERVICE_URL}/products/{product_id}", timeout=5)
        resp.raise_for_status()
        product_data = resp.json()
    except requests.HTTPError as e:
        return jsonify({"error": f"Product service error: {e.response.status_code}"}), 503
    except Exception as e:
        return jsonify({"error": f"Could not reach product service: {str(e)}"}), 503

    # Strip the served_by field from the nested product object
    product = {k: v for k, v in product_data.items() if k != "served_by"}

    order_id = uuid.uuid4().hex[:8]
    return jsonify({
        "order_id": order_id,
        "product": product,
        "status": "confirmed",
        "served_by": HOSTNAME,
    })


@app.route("/orders", methods=["GET"])
def list_orders():
    return jsonify({"orders": [], "served_by": HOSTNAME})


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
