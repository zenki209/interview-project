import os
import socket
import threading
import requests
from flask import Flask, jsonify, request

app = Flask(__name__)

PRODUCT_SERVICE_URL = os.environ.get("PRODUCT_SERVICE_URL", "http://product-service")
ORDER_SERVICE_URL = os.environ.get("ORDER_SERVICE_URL", "http://order-service")
REVIEW_SERVICE_URL = os.environ.get("REVIEW_SERVICE_URL", "http://review-service")

HOSTNAME = socket.gethostname()


def fetch_products():
    try:
        resp = requests.get(f"{PRODUCT_SERVICE_URL}/products", timeout=5)
        resp.raise_for_status()
        return resp.json(), None
    except Exception as e:
        return None, str(e)


def fetch_reviews():
    try:
        resp = requests.get(f"{REVIEW_SERVICE_URL}/reviews", timeout=5)
        resp.raise_for_status()
        return resp.json(), None
    except Exception as e:
        return None, str(e)


def render_stars(rating):
    if rating is None:
        return "<span class='stars'>&#8212;</span>"
    filled = "&#9733;" * rating
    empty = "&#9734;" * (5 - rating)
    return f"<span class='stars filled'>{filled}</span><span class='stars empty'>{empty}</span>"


def render_dashboard(products_data, products_err, reviews_data, reviews_err):
    product_served_by = products_data.get("served_by", "unknown") if products_data else "unknown"
    review_served_by = reviews_data.get("served_by", "unknown") if reviews_data else "unknown"
    review_version = reviews_data.get("version", "v1") if reviews_data else "v1"

    version_badge_style = (
        "background:#0e7490;color:#cffafe;" if review_version == "v1"
        else "background:#7c3aed;color:#ede9fe;"
    )

    # Build product cards
    if products_err:
        products_html = f"<div class='error-panel'>Error fetching products: {products_err}</div>"
    elif products_data:
        cards = ""
        for p in products_data.get("products", []):
            cards += f"""
            <div class='card product-card'>
                <div class='card-category'>{p.get('category','')}</div>
                <div class='card-name'>{p.get('name','')}</div>
                <div class='card-price'>${p.get('price', 0):.2f}</div>
                <button class='order-btn' onclick='placeOrder("{p.get("id","")}", this)'>Order</button>
            </div>"""
        products_html = f"<div class='cards-grid'>{cards}</div>"
    else:
        products_html = "<div class='error-panel'>No product data available.</div>"

    # Build review cards
    if reviews_err:
        reviews_html = f"<div class='error-panel'>Error fetching reviews: {reviews_err}</div>"
    elif reviews_data:
        cards = ""
        for r in reviews_data.get("reviews", []):
            stars_html = render_stars(r.get("rating"))
            cards += f"""
            <div class='card review-card'>
                <div class='review-user'>{r.get('user','')}</div>
                <div class='review-comment'>{r.get('comment','')}</div>
                <div class='review-stars'>{stars_html}</div>
            </div>"""
        reviews_html = f"<div class='cards-grid'>{cards}</div>"
    else:
        reviews_html = "<div class='error-panel'>No review data available.</div>"

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Service Mesh Dashboard</title>
  <style>
    *, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      background: #0f172a;
      color: #e2e8f0;
      font-family: 'Segoe UI', system-ui, sans-serif;
      min-height: 100vh;
      padding: 2rem;
    }}
    h1 {{
      font-size: 1.8rem;
      font-weight: 700;
      color: #f8fafc;
      margin-bottom: 1.5rem;
      letter-spacing: -0.5px;
    }}
    h2 {{
      font-size: 1.1rem;
      font-weight: 600;
      color: #94a3b8;
      text-transform: uppercase;
      letter-spacing: 1px;
      margin-bottom: 1rem;
    }}
    /* Call flow banner */
    .call-flow {{
      background: #1e293b;
      border: 1px solid #334155;
      border-radius: 12px;
      padding: 1rem 1.5rem;
      margin-bottom: 2rem;
      display: flex;
      align-items: center;
      flex-wrap: wrap;
      gap: 0.5rem;
      font-size: 0.85rem;
      color: #94a3b8;
    }}
    .call-flow .node {{
      background: #0f172a;
      border: 1px solid #475569;
      border-radius: 6px;
      padding: 0.3rem 0.75rem;
      color: #e2e8f0;
      font-weight: 500;
    }}
    .call-flow .arrow {{
      color: #38bdf8;
      font-size: 1.1rem;
    }}
    .call-flow .node.highlight {{
      border-color: #38bdf8;
      color: #38bdf8;
    }}
    .version-badge {{
      display: inline-block;
      border-radius: 999px;
      padding: 0.15rem 0.6rem;
      font-size: 0.75rem;
      font-weight: 700;
      margin-left: 0.35rem;
      vertical-align: middle;
      {version_badge_style}
    }}
    /* Sections */
    .sections {{
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 2rem;
      margin-bottom: 2rem;
    }}
    @media (max-width: 800px) {{
      .sections {{ grid-template-columns: 1fr; }}
    }}
    .section-box {{
      background: #1e293b;
      border: 1px solid #334155;
      border-radius: 12px;
      padding: 1.5rem;
    }}
    .section-header {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 1rem;
    }}
    .served-by {{
      font-size: 0.75rem;
      color: #64748b;
      background: #0f172a;
      border: 1px solid #334155;
      border-radius: 6px;
      padding: 0.2rem 0.6rem;
    }}
    /* Cards grid */
    .cards-grid {{
      display: flex;
      flex-direction: column;
      gap: 0.75rem;
    }}
    .card {{
      background: #0f172a;
      border: 1px solid #334155;
      border-radius: 8px;
      padding: 1rem;
    }}
    .card-category {{
      font-size: 0.7rem;
      text-transform: uppercase;
      letter-spacing: 1px;
      color: #64748b;
      margin-bottom: 0.25rem;
    }}
    .card-name {{
      font-size: 1rem;
      font-weight: 600;
      color: #f1f5f9;
      margin-bottom: 0.25rem;
    }}
    .card-price {{
      font-size: 1.1rem;
      font-weight: 700;
      color: #38bdf8;
      margin-bottom: 0.75rem;
    }}
    .order-btn {{
      background: #2563eb;
      color: #fff;
      border: none;
      border-radius: 6px;
      padding: 0.4rem 1rem;
      font-size: 0.85rem;
      font-weight: 600;
      cursor: pointer;
      transition: background 0.15s;
    }}
    .order-btn:hover {{ background: #1d4ed8; }}
    .order-btn:disabled {{ background: #475569; cursor: not-allowed; }}
    /* Review cards */
    .review-user {{
      font-weight: 600;
      color: #e2e8f0;
      margin-bottom: 0.25rem;
    }}
    .review-comment {{
      font-size: 0.9rem;
      color: #94a3b8;
      margin-bottom: 0.5rem;
    }}
    .stars {{ font-size: 1rem; }}
    .stars.filled {{ color: #fbbf24; }}
    .stars.empty {{ color: #334155; }}
    /* Order result */
    .order-section {{
      background: #1e293b;
      border: 1px solid #334155;
      border-radius: 12px;
      padding: 1.5rem;
    }}
    #order-result {{
      margin-top: 0.75rem;
      min-height: 60px;
    }}
    .order-placeholder {{
      color: #475569;
      font-size: 0.9rem;
    }}
    .order-success {{
      background: #0f172a;
      border: 1px solid #334155;
      border-radius: 8px;
      padding: 1rem;
    }}
    .order-success .order-id {{
      font-size: 0.75rem;
      color: #64748b;
      margin-bottom: 0.5rem;
    }}
    .order-success .order-product {{
      font-size: 1rem;
      font-weight: 600;
      color: #f1f5f9;
    }}
    .order-success .order-price {{
      font-size: 1.1rem;
      font-weight: 700;
      color: #34d399;
      margin: 0.25rem 0;
    }}
    .order-success .order-served {{
      font-size: 0.75rem;
      color: #64748b;
    }}
    .order-status-confirmed {{
      display: inline-block;
      background: #064e3b;
      color: #6ee7b7;
      border-radius: 999px;
      padding: 0.1rem 0.5rem;
      font-size: 0.75rem;
      font-weight: 700;
      margin-left: 0.5rem;
    }}
    .calling-msg {{
      color: #94a3b8;
      font-size: 0.9rem;
      display: flex;
      align-items: center;
      gap: 0.5rem;
    }}
    .spinner {{
      width: 14px; height: 14px;
      border: 2px solid #334155;
      border-top-color: #38bdf8;
      border-radius: 50%;
      animation: spin 0.7s linear infinite;
      display: inline-block;
    }}
    @keyframes spin {{ to {{ transform: rotate(360deg); }} }}
    .error-panel {{
      background: #1c0a0a;
      border: 1px solid #7f1d1d;
      border-radius: 8px;
      padding: 0.75rem 1rem;
      color: #fca5a5;
      font-size: 0.85rem;
    }}
  </style>
</head>
<body>
  <h1>Service Mesh Dashboard</h1>

  <div class="call-flow">
    <span class="node">Browser</span>
    <span class="arrow">&#8594;</span>
    <span class="node">IngressGateway</span>
    <span class="arrow">&#8594;</span>
    <span class="node highlight">frontend&nbsp;<small>({HOSTNAME})</small></span>
    <span class="arrow">&#8594;</span>
    <span class="node">product-service&nbsp;<small>({product_served_by})</small></span>
    <span class="arrow">&amp;</span>
    <span class="node">review-service&nbsp;<small>({review_served_by})</small><span class="version-badge">{review_version}</span></span>
  </div>

  <div class="sections">
    <div class="section-box">
      <div class="section-header">
        <h2>Products</h2>
        <span class="served-by">pod: {product_served_by}</span>
      </div>
      {products_html}
    </div>

    <div class="section-box">
      <div class="section-header">
        <h2>Reviews</h2>
        <span class="served-by">pod: {review_served_by} <span class="version-badge">{review_version}</span></span>
      </div>
      {reviews_html}
    </div>
  </div>

  <div class="order-section">
    <h2>Order Result</h2>
    <div id="order-result">
      <span class="order-placeholder">Click "Order" on a product to place an order via order-service.</span>
    </div>
  </div>

  <script>
    async function placeOrder(productId, btn) {{
      const resultDiv = document.getElementById('order-result');
      btn.disabled = true;
      btn.textContent = 'Ordering…';
      resultDiv.innerHTML = '<div class="calling-msg"><span class="spinner"></span>Calling order-service…</div>';

      try {{
        const resp = await fetch('/order/' + productId, {{
          method: 'POST',
          headers: {{ 'Content-Type': 'application/json' }}
        }});
        const data = await resp.json();

        if (!resp.ok) {{
          resultDiv.innerHTML = '<div class="error-panel">Order failed: ' + (data.error || resp.statusText) + '</div>';
        }} else {{
          const product = data.product || {{}};
          const price = product.price !== undefined ? '$' + parseFloat(product.price).toFixed(2) : '';
          resultDiv.innerHTML = `
            <div class="order-success">
              <div class="order-id">Order ID: ${{data.order_id}}</div>
              <div class="order-product">${{product.name || productId}}<span class="order-status-confirmed">${{data.status}}</span></div>
              <div class="order-price">${{price}}</div>
              <div class="order-served">Served by: ${{data.served_by}}</div>
            </div>`;
        }}
      }} catch (err) {{
        resultDiv.innerHTML = '<div class="error-panel">Network error: ' + err.message + '</div>';
      }} finally {{
        btn.disabled = false;
        btn.textContent = 'Order';
      }}
    }}
  </script>
</body>
</html>"""
    return html


@app.route("/")
def index():
    products_data = None
    products_err = None
    reviews_data = None
    reviews_err = None

    results = {}

    def get_products():
        results["products"] = fetch_products()

    def get_reviews():
        results["reviews"] = fetch_reviews()

    t1 = threading.Thread(target=get_products)
    t2 = threading.Thread(target=get_reviews)
    t1.start()
    t2.start()
    t1.join()
    t2.join()

    products_data, products_err = results.get("products", (None, "Thread error"))
    reviews_data, reviews_err = results.get("reviews", (None, "Thread error"))

    return render_dashboard(products_data, products_err, reviews_data, reviews_err)


@app.route("/order/<product_id>", methods=["POST"])
def place_order(product_id):
    try:
        resp = requests.post(
            f"{ORDER_SERVICE_URL}/orders",
            json={"product_id": product_id},
            timeout=5,
        )
        return jsonify(resp.json()), resp.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 503


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
