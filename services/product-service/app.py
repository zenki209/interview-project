import socket
from flask import Flask, jsonify

app = Flask(__name__)

PRODUCTS = [
    {"id": "1", "name": "Laptop Pro",         "price": 1299.99, "category": "Electronics"},
    {"id": "2", "name": "Wireless Mouse",      "price":   29.99, "category": "Accessories"},
    {"id": "3", "name": "Mechanical Keyboard", "price":   89.99, "category": "Accessories"},
    {"id": "4", "name": "4K Monitor",          "price":  499.99, "category": "Electronics"},
]

HOSTNAME = socket.gethostname()


@app.route("/products")
def list_products():
    return jsonify({"products": PRODUCTS, "served_by": HOSTNAME})


@app.route("/products/<product_id>")
def get_product(product_id):
    for product in PRODUCTS:
        if product["id"] == product_id:
            return jsonify({**product, "served_by": HOSTNAME})
    return jsonify({"error": f"Product {product_id!r} not found"}), 404


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
