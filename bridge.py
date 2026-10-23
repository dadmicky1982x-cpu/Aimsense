import os, time, threading
from flask import Flask, request, jsonify

# The exact password we are using everywhere
API_TOKEN    = "AIMSENSE-SECRET-123"
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
    if request.headers.get("X-Token") != API_TOKEN: return jsonify(ok=False, err="bad token"), 403
    data = request.get_json(silent=True) or {}
    cmd, target = (data.get("cmd") or "").strip(), (data.get("target") or "").strip().lower()
    if not cmd or len(cmd) > 200 or not target: return jsonify(ok=False, err="bad payload"), 400
    cid = data.get("id") or str(int(time.time() * 1000))
    with _lock: _queue.append({"cmd": cmd, "target": target, "ts": time.time(), "id": cid})
    return jsonify(ok=True, id=cid)

@app.route("/poll", methods=["GET"])
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

# This serves your main.lua directly from Render
@app.route("/script", methods=["GET"])
def serve_script():
    try:
        with open("main.lua", "r") as f:
            return f.read(), 200, {'Content-Type': 'text/plain'}
    except Exception:
        return "Script not found. Upload main.lua next to bridge.py", 404

if __name__ == "__main__":
    from waitress import serve
    serve(app, host="0.0.0.0", port=PORT)