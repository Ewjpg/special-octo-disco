"""Writes src/_manifest.json: every script in src with its place in the Studio tree (Rojo layout).

  python tools/studio_sync.py

Serve src over localhost and run tools/studio_sync.luau in Studio's edit DataModel (MCP execute_luau):
it creates or updates every script so an open place matches the files, without restarting Studio.
"""
import json, os

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src")
ROOTS = {"shared": ["ReplicatedStorage", "Shared"], "server": ["ServerScriptService", "Server"],
         "client": ["StarterPlayer", "StarterPlayerScripts", "Client"]}
entries = []
for top, base in ROOTS.items():
    for dirpath, _, files in os.walk(os.path.join(SRC, top)):
        rel_dir = os.path.relpath(dirpath, os.path.join(SRC, top))
        parts = [] if rel_dir == "." else rel_dir.replace("\\", "/").split("/")
        for f in sorted(files):
            if not f.endswith(".luau"):
                continue
            stem = f[:-5]
            cls = "ModuleScript"
            if stem.endswith(".server"):
                cls, stem = "Script", stem[:-7]
            elif stem.endswith(".client"):
                cls, stem = "LocalScript", stem[:-7]
            path = base + parts + ([] if stem == "init" else [stem])
            entries.append({"file": "/".join([top] + parts + [f]), "path": path, "class": cls,
                            "init": stem == "init"})
# parents before children
entries.sort(key=lambda e: len(e["path"]))
json.dump(entries, open(os.path.join(SRC, "_manifest.json"), "w"), indent=0)
print(len(entries), "scripts")
