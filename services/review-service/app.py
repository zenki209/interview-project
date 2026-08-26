import socket
from flask import Flask, jsonify

app = Flask(__name__)

HOSTNAME = socket.gethostname()

REVIEWS = [
    {"user": "Alice",   "comment": "Solid build quality, very happy.",  "rating": None},
    {"user": "Bob",     "comment": "Fast shipping, works as expected.",  "rating": None},
    {"user": "Charlie", "comment": "Good value for the price.",          "rating": None},
]


@app.route("/reviews")
def list_reviews():
    return jsonify({
        "version": "v1",
        "served_by": HOSTNAME,
        "reviews": REVIEWS,
    })


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
