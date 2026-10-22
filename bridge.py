import os, time, threading
from flask import Flask, request, jsonify

API_TOKEN    = "mysupersecrettoken123"
COMMAND_TTL  = 30.0
PRESENCE_TTL = 20.0
PORT         = int(os.environ.get("PORT", 8080))

app = Flask(__name__)
_lock = threading.Lock()
_queue = []
_presence = {}

def _prune():
    now = time.time()
    with _lock:
        _queue[:] = [c for c in _queue if now - c["ts"] < COMMAND_TTL]

@app.route("/push", methods=["POST"])
def push():
    if request.headers.get("X-Token") != API_TOKEN: return jsonify(ok=False), 403
    data = request.get_json(silent=True) or {}
    cmd, target = (data.get("cmd") or "").strip(), (data.get("target") or "").strip().lower()
    with _lock: _queue.append({"cmd": cmd, "target": target, "ts": time.time()})
    return jsonify(ok=True)

@app.route("/poll", methods=["GET"])
def poll():
    if request.headers.get("X-Token") != API_TOKEN: return jsonify(ok=False), 403
    name = (request.args.get("name") or "").strip().lower()
    _prune()
    with _lock:
        mine = [c["cmd"] for c in _queue if c["target"] == name]
        _queue[:] = [c for c in _queue if c["target"] != name]
    return jsonify(ok=True, cmds=mine)

@app.route("/presence", methods=["POST"])
def presence():
    if request.headers.get("X-Token") != API_TOKEN: return jsonify(ok=False), 403
    data = request.get_json(silent=True) or {}
    with _lock: _presence[(data.get("name") or "").strip().lower()] = time.time()
    return jsonify(ok=True)

@app.route("/online", methods=["GET"])
def online():
    if request.headers.get("X-Token") != API_TOKEN: return jsonify(ok=False), 403
    now = time.time()
    with _lock: out = [n for n, t in _presence.items() if now - t < PRESENCE_TTL]
    return jsonify(ok=True, online=out)

if __name__ == "__main__":
    from waitress import serve
    serve(app, host="0.0.0.0", port=PORT)