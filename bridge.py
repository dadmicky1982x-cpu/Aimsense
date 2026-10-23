import os, time, threading
from flask import Flask, request, jsonify

# ==========================================
# ===== CONFIG =====
# ==========================================
API_TOKEN    = "AIMSENSE-SECRET-123"
COMMAND_TTL  = 30.0
PRESENCE_TTL = 20.0
PORT         = int(os.environ.get("PORT", 8080))

app = Flask(__name__)
_lock = threading.Lock()

_queue = []       # Stores commands: {"cmd": str, "target": str, "ts": float, "id": str}
_presence = {}    # Stores online executors: {roblox_name: last_seen_ts}
_keys = {}        # Stores generated keys: {key: discord_id}
_links = {}       # Stores discord links: {discord_id: roblox_id}

def _prune():
    now = time.time()
    with _lock:
        _queue[:] = [c for c in _queue if now - c["ts"] < COMMAND_TTL]

# ==========================================
# ===== COMMAND RELAY =====
# ==========================================
@app.route("/push", methods=["POST"])
def push():
    if request.headers.get("X-Token") != API_TOKEN: 
        return jsonify(ok=False, err="bad token"), 403
    
    data = request.get_json(silent=True) or {}
    cmd = (data.get("cmd") or "").strip()
    target = (data.get("target") or "").strip().lower()
    
    if not cmd or len(cmd) > 200 or not target: 
        return jsonify(ok=False, err="bad payload"), 400
        
    cid = data.get("id") or str(int(time.time() * 1000))
    with _lock: 
        _queue.append({"cmd": cmd, "target": target, "ts": time.time(), "id": cid})
    return jsonify(ok=True, id=cid)

@app.route("/poll", methods=["GET"])
def poll():
    if request.headers.get("X-Token") != API_TOKEN: 
        return jsonify(ok=False, err="bad token"), 403
        
    name = (request.args.get("name") or "").strip().lower()
    if not name: 
        return jsonify(ok=False, err="no name"), 400
        
    _prune()
    with _lock:
        mine = [c["cmd"] for c in _queue if c["target"] == name]
        _queue[:] = [c for c in _queue if c["target"] != name]
        
    return jsonify(ok=True, cmds=mine)

@app.route("/presence", methods=["POST"])
def presence():
    if request.headers.get("X-Token") != API_TOKEN: 
        return jsonify(ok=False, err="bad token"), 403
        
    data = request.get_json(silent=True) or {}
    name = (data.get("name") or "").strip().lower()
    
    if not name: 
        return jsonify(ok=False, err="no name"), 400
        
    with _lock: 
        _presence[name] = time.time()
    return jsonify(ok=True)

@app.route("/online", methods=["GET"])
def online():
    if request.headers.get("X-Token") != API_TOKEN: 
        return jsonify(ok=False, err="bad token"), 403
        
    now = time.time()
    with _lock: 
        out = [n for n, t in _presence.items() if now - t < PRESENCE_TTL]
    return jsonify(ok=True, online=out)

# ==========================================
# ===== AUTHENTICATION & SCRIPT SERVING =====
# ==========================================
@app.route("/link", methods=["POST"])
def link_account():
    if request.headers.get("X-Token") != API_TOKEN: 
        return jsonify(ok=False), 403
        
    data = request.get_json(silent=True) or {}
    discord_id = str(data.get("discord_id", ""))
    roblox_id = str(data.get("roblox_id", ""))
    
    if not discord_id or not roblox_id: 
        return jsonify(ok=False, err="missing data"), 400
        
    with _lock: 
        _links[discord_id] = roblox_id.lower()
        
    return jsonify(ok=True)

@app.route("/register_key", methods=["POST"])
def register_key():
    if request.headers.get("X-Token") != API_TOKEN: 
        return jsonify(ok=False), 403
        
    data = request.get_json(silent=True) or {}
    key = data.get("key")
    discord_id = str(data.get("discord_id", ""))
    
    if not key or not discord_id: 
        return jsonify(ok=False, err="missing data"), 400
        
    with _lock: 
        _keys[key] = discord_id
        
    return jsonify(ok=True)

@app.route("/reset_hwid", methods=["POST"])
def reset_hwid():
    if request.headers.get("X-Token") != API_TOKEN: 
        return jsonify(ok=False), 403
        
    data = request.get_json(silent=True) or {}
    key = data.get("key")
    
    with _lock:
        if key in _keys:
            # We don't delete the key, we just leave it registered to the discord ID.
            # The HWID check will fail if their Roblox ID changes.
            # If you want to fully reset, we can just delete it from _keys.
            del _keys[key]
            return jsonify(ok=True)
            
    return jsonify(ok=False, err="Key not found"), 404

@app.route("/script", methods=["GET"])
def serve_script():
    key = request.args.get("key")
    hwid = request.args.get("hwid") # Roblox UserId
    
    if not key or not hwid: 
        return "Missing key or hwid", 400
        
    with _lock:
        if key not in _keys:
            return "Invalid Key", 403
            
        discord_id = _keys[key]
        
        # Check if they ran /link in Discord
        if discord_id not in _links:
            return "Discord account not linked to a Roblox account. Run /link in Discord.", 403
            
        # Check if the Roblox UserId matches the linked account
        if _links[discord_id] != hwid.lower():
            return "HWID Mismatch: This key is linked to a different Roblox account.", 403

    try:
        with open("main.lua", "r") as f:
            return f.read(), 200, {'Content-Type': 'text/plain'}
    except Exception:
        return "Script not found.", 404

if __name__ == "__main__":
    from waitress import serve
    print(f"Bridge running on port {PORT}")
    serve(app, host="0.0.0.0", port=PORT)