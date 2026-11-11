"""Live bridge into a Blender window that is open on screen.

  blender R6Football.blend --python tools/anim/blender_bridge.py

Every 0.3 s Blender looks in tools/anim/bridge/in for *.py files, runs each one inside the open
session (so its changes show up in the viewport at once), deletes it and writes what it printed,
or the traceback, to tools/anim/bridge/out/<name>.txt. Only files in that local folder are run.
send.ps1 drops a script in and waits for the answer.
"""
import bpy, os, io, glob, traceback, contextlib

ROOT = os.path.dirname(os.path.abspath(__file__))
INBOX = os.path.join(ROOT, "bridge", "in")
OUTBOX = os.path.join(ROOT, "bridge", "out")
os.makedirs(INBOX, exist_ok=True)
os.makedirs(OUTBOX, exist_ok=True)
SHARED = {"bpy": bpy, "__name__": "__bridge__", "ANIM_ROOT": ROOT}


def _poll():
    for path in sorted(glob.glob(os.path.join(INBOX, "*.py"))):
        name = os.path.splitext(os.path.basename(path))[0]
        try:
            code = open(path, encoding="utf-8").read()
        except OSError:
            continue  # still being written
        os.remove(path)
        buf = io.StringIO()
        status = "ok"
        try:
            with contextlib.redirect_stdout(buf):
                exec(compile(code, name + ".py", "exec"), SHARED)
        except Exception:
            status = "error"
            buf.write(traceback.format_exc())
        with open(os.path.join(OUTBOX, name + ".txt"), "w", encoding="utf-8") as f:
            f.write(status + "\n" + buf.getvalue())
    return 0.3


if not bpy.app.timers.is_registered(_poll):
    bpy.app.timers.register(_poll, persistent=True)
print("[bridge] listening on", INBOX)
