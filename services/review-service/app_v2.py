import socket
from flask import Flask, jsonify

app = Flask(__name__)

HOSTNAME = socket.gethostname()

REVIEWS = [
    {"user": "Alice",   "comment": "Solid build quality, very happy.",  "rating": 5},
    {"user": "Bob",     "comment": "Fast shipping, works as expected.",  "rating": 4},
    {"user": "Charlie", "comment": "Good value for the price.",          "rating": 4},
]


@app.route("/reviews")
def list_reviews():
    return jsonify({
        "version": "v2",
        "served_by": HOSTNAME,
        "reviews": REVIEWS,
    })


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
