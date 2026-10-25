from flask import Flask

app = Flask(__name__)


@app.route("/api/sa")
def hello():
    return "Hello from Service A!\n"


@app.route("/healthz")
def healthz():
    # A readiness és liveness probe ide kérdez
    return "ok\n"


if __name__ == "__main__":
    # Csak helyi fejlesztéshez; a konténerben gunicorn futtatja
    app.run(host="0.0.0.0", port=8080)
