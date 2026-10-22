import os, time, threading
from flask import Flask, request, jsonify
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

# Pull token from Render environment variables
API_TOKEN    = os.environ.get("BRIDGE_TOKEN", "mysupersecrettoken123")
COMMAND_TTL  = 30.0
PRESENCE_TTL = 20.0
PORT         = int(os.environ.get("PORT", 8080))

app = Flask(__name__)
# Rate limiter: max 60 requests per minute per IP
limiter = Limiter(
    get_remote_address,
    app=app,
    default_limits=["60 per minute"]
)

_lock = threading.Lock()
_queue = []
_presence = {}

def _prune():
    now = time.time()
    with _lock:
        _queue[:] = [c for c in _queue if now - c["ts"] < COMMAND_TTL]

@app.route("/push", methods=["POST"])
@limiter.limit("30 per minute")
def push():
    if request.headers.get("X-Token") != API_TOKEN: return jsonify(ok=False, err="bad token"), 403
    data = request.get_json(silent=True) or {}
    cmd, target = (data.get("cmd") or "").strip(), (data.get("target") or "").strip().lower()
    if not cmd or len(cmd) > 200 or not target: return jsonify(ok=False, err="bad payload"), 400
    cid = data.get("id") or str(int(time.time() * 1000))
    with _lock: _queue.append({"cmd": cmd, "target": target, "ts": time.time(), "id": cid})
    return jsonify(ok=True, id=cid)

@app.route("/poll", methods=["GET"])
@limiter.limit("60 per minute")
def poll():
    if request.headers.get("X-Token") != API_TOKEN: return jsonify(ok=False, err="bad token"), 403
    name = (request.args.get("name") or "").strip().lower()
    if not name: return jsonify(ok=False, err="no name"), 400
    _prune()
    with _lock:
        mine = [c["cmd"] for c in _queue if c["target"] == name]
        _queue[:] = [c for c in _queue if c["target"] != name]
    return jsonify(ok=True, cmds=mine)

@app.route("/presence", methods=["POST"])
def presence():
    if request.headers.get("X-Token") != API_TOKEN: return jsonify(ok=False, err="bad token"), 403
    data = request.get_json(silent=True) or {}
    name = (data.get("name") or "").strip().lower()
    if not name: return jsonify(ok=False, err="no name"), 400
    with _lock: _presence[name] = time.time()
    return jsonify(ok=True)

@app.route("/online", methods=["GET"])
def online():
    if request.headers.get("X-Token") != API_TOKEN: return jsonify(ok=False, err="bad token"), 403
    now = time.time()
    with _lock: out = [n for n, t in _presence.items() if now - t < PRESENCE_TTL]
    return jsonify(ok=True, online=out)

# NEW ROUTE: Serves your main.lua directly from Render
@app.route("/script", methods=["GET"])
def serve_script():
    try:
        # Looks for main.lua in the same folder as bridge.py
        with open("main.lua", "r") as f:
            return f.read(), 200, {'Content-Type': 'text/plain'}
    except Exception:
        return "Script not found.", 404

if __name__ == "__main__":
    from waitress import serve
    print(f"bridge on http://127.0.0.1:{PORT}")
    serve(app, host="0.0.0.0", port=PORT)