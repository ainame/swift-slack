"""Minimal stdio Codex fixture: no network, credentials, or command execution."""
import json
import os
import signal
import sys
import threading
import time

state = sys.argv[1]
thread_id = "saved-conversation"
output_lock = threading.Lock()


def record(method, params=None):
    entry = {"method": method, "params": params or {}, "pid": os.getpid()}
    fd = os.open(os.path.join(state, "events.jsonl"), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(fd, (json.dumps(entry) + "\n").encode())
    finally:
        os.close(fd)


def send(message):
    with output_lock:
        print(json.dumps(message), flush=True)


def completed(turn_id):
    send({"method": "turn/completed", "params": {
        "threadId": thread_id,
        "turn": {"id": turn_id, "items": [], "status": "completed", "error": None},
    }})


def drain(turn_id):
    while not os.path.exists(os.path.join(state, "release-drain")):
        time.sleep(0.01)
    completed(turn_id)


def terminate(*_):
    record("closed")
    sys.exit(0)


signal.signal(signal.SIGTERM, terminate)
record("launched")
try:
    for line in sys.stdin:
        request = json.loads(line)
        method = request.get("method")
        params = request.get("params", {})
        record(method, params)
        if method == "initialized":
            continue
        if method == "initialize":
            result = {"serverInfo": {"name": "codex", "version": "test"}, "userAgent": "codex/test"}
        elif method in ("thread/start", "thread/resume"):
            result = {
                "approvalPolicy": "never", "approvalsReviewer": "user", "cwd": os.getcwd(),
                "model": "test", "modelProvider": "openai", "sandbox": {"type": "readOnly"},
                "thread": {
                    "id": thread_id, "cliVersion": "test", "createdAt": 1, "updatedAt": 2,
                    "cwd": os.getcwd(), "ephemeral": False, "modelProvider": "openai", "preview": "",
                    "sessionId": "session-test", "source": "appServer", "status": {"type": "idle"}, "turns": [],
                },
            }
        elif method == "turn/start":
            turn_id = "turn-" + str(request["id"])
            send({"id": request["id"], "result": {"turn": {
                "id": turn_id, "items": [], "status": "inProgress", "error": None,
            }}})
            text = "".join(item.get("text", "") for item in params.get("input", []))
            if text == "drain":
                threading.Thread(target=drain, args=(turn_id,), daemon=True).start()
            else:
                completed(turn_id)
            continue
        elif method == "turn/interrupt":
            result = {}  # Ack the interrupt while the test deliberately holds notification draining.
        else:
            send({"id": request["id"], "error": {"code": -32601, "message": "Unsupported fixture method"}})
            continue
        send({"id": request["id"], "result": result})
finally:
    record("exited")
