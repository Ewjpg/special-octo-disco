"""Authors every R6 clip of the game as r6_clip.py JSON specs in clips/.

  python gen_clips.py

Angles are r6_joint.py semantics (degrees, parent axes, +X right, -Z forward):
  root/neck: pitch + = bow forward, lean + = tip to the LEFT, turn + = face LEFT, pos = [dx, dy, dz]
  limbs:     swing + = forward, spread + = outward, twist + = front face turns left
Pitching the torso back swings the hanging legs forward by the same angle; compensate in the hips.
Keys with ground=True put the lowest foot on the turf (solves the RootJoint height).
"""
import json, os

NAMES = {"root": "RootJoint", "neck": "Neck", "rs": "Right Shoulder", "ls": "Left Shoulder",
         "rh": "Right Hip", "lh": "Left Hip"}
ALL = list(NAMES)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "clips")
os.makedirs(OUT, exist_ok=True)

# Timing in game (seconds, fades, ProcAnimator priority); matches Animations.luau.
META = {}


def pose(**joints):
    """Full pose: every joint present, so interpolation never jumps to rest."""
    out = {}
    for short in ALL:
        out[short] = dict(joints.get(short, {}))
    return out


def key(t, p, ease="smooth", ground=True):
    return {"t": t, "ease": ease, "ground": ground, "p": p}


def clip(name, duration, keys, loop=False, fade_in=0.06, fade_out=0.18, priority=3):
    spec = {"name": name, "fps": 30, "duration": duration, "loop": loop, "priority": "Action", "keyframes": []}
    for k in keys:
        joints = {NAMES[s]: v for s, v in k["p"].items()}
        spec["keyframes"].append({"t": k["t"], "ease": k["ease"], "ground": k["ground"], "joints": joints})
    with open(os.path.join(OUT, name + ".json"), "w") as f:
        json.dump(spec, f, indent=1)
    META[name] = {"length": duration, "loop": loop, "fadeIn": fade_in, "fadeOut": fade_out, "priority": priority}


def mirror(p):
    """Left <-> right: swap limbs, flip lean/turn/twist and the x offset."""
    swap = {"rs": "ls", "ls": "rs", "rh": "lh", "lh": "rh"}
    out = {}
    for s, v in p.items():
        v = dict(v)
        for k in ("lean", "turn", "twist"):
            if k in v:
                v[k] = -v[k]
        if "pos" in v:
            v["pos"] = [-v["pos"][0], v["pos"][1], v["pos"][2]]
        out[swap.get(s, s)] = v
    return out


REST = pose()

# ---------------------------------------------------------------- kicks
WINDUP = pose(
    root={"pitch": -6, "turn": -22}, neck={"turn": 18, "pitch": 6},
    rh={"swing": -58}, lh={"swing": 12, "spread": 6},
    rs={"swing": -40, "spread": 28}, ls={"swing": 38, "spread": 48},
)
WINDUP_DEEP = pose(
    root={"pitch": -9, "turn": -27}, neck={"turn": 22, "pitch": 8},
    rh={"swing": -66}, lh={"swing": 14, "spread": 7},
    rs={"swing": -48, "spread": 32}, ls={"swing": 44, "spread": 54},
)
clip("ChargeHold", 0.7, [key(0, WINDUP), key(0.35, WINDUP_DEEP), key(0.7, WINDUP)],
     loop=True, fade_in=0.14, fade_out=0.12, priority=2)

clip("Shoot", 0.52, [
    key(0, WINDUP),
    key(0.08, pose(root={"pitch": -10, "turn": 8}, neck={"turn": -6, "pitch": 12},
                   rh={"swing": 72}, lh={"swing": -8, "spread": 6},
                   rs={"swing": 30, "spread": 34}, ls={"swing": -26, "spread": 60}), "in"),
    key(0.2, pose(root={"pitch": -16, "turn": 16}, neck={"turn": -12, "pitch": 14},
                  rh={"swing": 108}, lh={"swing": -14, "spread": 4},
                  rs={"swing": 42, "spread": 40}, ls={"swing": -38, "spread": 64}), "out"),
    key(0.52, REST),
], fade_in=0.04, fade_out=0.2)

# Power shot: deeper wind-up, a hop into the strike, leg finishes high, lands.
clip("PowerShot", 0.7, [
    key(0, WINDUP_DEEP),
    key(0.1, pose(root={"pitch": -4, "turn": -34}, neck={"turn": 26, "pitch": 6},
                  rh={"swing": -80}, lh={"swing": 18, "spread": 8},
                  rs={"swing": -60, "spread": 40}, ls={"swing": 60, "spread": 60}), "out"),
    key(0.18, pose(root={"pitch": -18, "turn": 14, "pos": [0, 0.5, 0]}, neck={"turn": -10, "pitch": 16},
                   rh={"swing": 96}, lh={"swing": -18, "spread": 6},
                   rs={"swing": 40, "spread": 50}, ls={"swing": -40, "spread": 75}), "in", ground=False),
    key(0.32, pose(root={"pitch": -24, "turn": 24, "pos": [0, 0.35, 0]}, neck={"turn": -16, "pitch": 18},
                   rh={"swing": 135}, lh={"swing": -22, "spread": 4},
                   rs={"swing": 55, "spread": 55}, ls={"swing": -50, "spread": 80}), "out", ground=False),
    key(0.48, pose(root={"pitch": 8, "turn": 10}, neck={"pitch": -4},
                   rh={"swing": 20}, lh={"swing": -10},
                   rs={"swing": 10, "spread": 30}, ls={"swing": -10, "spread": 35})),
    key(0.7, REST),
], fade_in=0.06, fade_out=0.22, priority=4)

# Pass: short back-lift, inside of the foot sweeps across the body.
clip("Pass", 0.36, [
    key(0, REST),
    key(0.08, pose(root={"pitch": 4, "turn": -10}, neck={"turn": 8},
                   rh={"swing": -32, "spread": 12, "twist": -30}, lh={"swing": 6},
                   rs={"swing": -18, "spread": 22}, ls={"swing": 20, "spread": 30}), "out"),
    key(0.16, pose(root={"pitch": 6, "turn": 10}, neck={"turn": -4, "pitch": 8},
                   rh={"swing": 40, "spread": -14, "twist": -36}, lh={"swing": -6},
                   rs={"swing": 16, "spread": 28}, ls={"swing": -14, "spread": 34}), "in"),
    key(0.36, REST),
], fade_in=0.04, fade_out=0.16)

# Lob: lean back, scoop under the ball, arms open up.
clip("Lob", 0.46, [
    key(0, REST),
    key(0.1, pose(root={"pitch": -4, "turn": -12}, neck={"turn": 8},
                  rh={"swing": -45}, lh={"swing": 8},
                  rs={"swing": -30, "spread": 25}, ls={"swing": 30, "spread": 35}), "out"),
    key(0.2, pose(root={"pitch": -22, "turn": 6}, neck={"pitch": -10},
                  rh={"swing": 70}, lh={"swing": -20},
                  rs={"swing": 30, "spread": 60}, ls={"swing": 10, "spread": 70}), "in"),
    key(0.32, pose(root={"pitch": -24, "turn": 8}, neck={"pitch": -12},
                   rh={"swing": 92}, lh={"swing": -22},
                   rs={"swing": 40, "spread": 65}, ls={"swing": 15, "spread": 75}), "out"),
    key(0.46, REST),
], fade_in=0.04, fade_out=0.18)

# Slide tackle: drop onto the left hip, right leg leading low, left hand trailing on the turf.
SLIDE = pose(root={"pitch": -58, "lean": -12, "pos": [0, 0, 0]}, neck={"pitch": 32},
             rh={"swing": 30}, lh={"swing": -4, "spread": 8},
             rs={"swing": 50, "spread": 30}, ls={"swing": -30, "spread": 55})
clip("Slide", 0.8, [
    key(0, REST),
    key(0.08, pose(root={"pitch": -30, "lean": -6}, neck={"pitch": 18},
                   rh={"swing": 40}, lh={"swing": -10, "spread": 6},
                   rs={"swing": 40, "spread": 30}, ls={"swing": -20, "spread": 45}), "out"),
    key(0.16, SLIDE, "out"),
    key(0.5, pose(root={"pitch": -54, "lean": -10}, neck={"pitch": 28},
                  rh={"swing": 26}, lh={"swing": -2, "spread": 8},
                  rs={"swing": 45, "spread": 30}, ls={"swing": -28, "spread": 55}), "linear"),
    key(0.8, REST),
], fade_in=0.07, fade_out=0.22, priority=4)

# Dribble: a quick step-over and cut, body dips to sell the fake.
clip("Dribble", 0.4, [
    key(0, REST),
    key(0.08, pose(root={"pitch": 10, "lean": -14, "turn": -10}, neck={"turn": 10},
                   rh={"swing": 30, "spread": 30}, lh={"swing": -8, "spread": 6},
                   rs={"swing": -10, "spread": 55}, ls={"swing": 15, "spread": 40}), "out"),
    key(0.18, pose(root={"pitch": 14, "lean": 16, "turn": 14}, neck={"turn": -10},
                   rh={"swing": -12, "spread": 4}, lh={"swing": 24, "spread": 26},
                   rs={"swing": 18, "spread": 40}, ls={"swing": -14, "spread": 58}), "smooth"),
    key(0.4, REST),
], fade_in=0.04, fade_out=0.16)

# Dash: explosive lean into a long stride.
clip("Dash", 0.38, [
    key(0, REST),
    key(0.06, pose(root={"pitch": 28}, neck={"pitch": -22},
                   rh={"swing": -40}, lh={"swing": 55},
                   rs={"swing": 60, "spread": 10}, ls={"swing": -55, "spread": 10}), "out"),
    key(0.22, pose(root={"pitch": 22}, neck={"pitch": -18},
                   rh={"swing": -30}, lh={"swing": 40},
                   rs={"swing": 45, "spread": 10}, ls={"swing": -45, "spread": 10}), "linear"),
    key(0.38, REST),
], fade_in=0.05, fade_out=0.16)

# Stun: knocked back, arms flung, a wobble before recovering.
clip("Stun", 0.8, [
    key(0, REST),
    key(0.08, pose(root={"pitch": -18, "lean": 8}, neck={"pitch": -24, "turn": 10},
                   rh={"swing": 22}, lh={"swing": -6, "spread": 10},
                   rs={"swing": 30, "spread": 60}, ls={"swing": 20, "spread": 70}), "out"),
    key(0.3, pose(root={"pitch": 12, "lean": -10}, neck={"pitch": 20, "turn": -8},
                  rh={"swing": -8, "spread": 8}, lh={"swing": 14},
                  rs={"swing": -15, "spread": 35}, ls={"swing": 10, "spread": 30}), "smooth"),
    key(0.5, pose(root={"pitch": 4, "lean": 6}, neck={"pitch": 8},
                  rh={"swing": 4}, lh={"swing": 0},
                  rs={"swing": 0, "spread": 18}, ls={"swing": 0, "spread": 15}), "smooth"),
    key(0.8, REST),
], fade_in=0.05, fade_out=0.25, priority=5)

# Celebrate: knee-slide-free fist pumps with both arms, looking up.
UP = pose(root={"pitch": -10}, neck={"pitch": -18},
          rh={"swing": 8}, lh={"swing": -4, "spread": 6},
          rs={"swing": 168, "spread": 18}, ls={"swing": 168, "spread": 18})
PUMP = pose(root={"pitch": -4}, neck={"pitch": -10},
            rh={"swing": 4}, lh={"swing": 0, "spread": 6},
            rs={"swing": 110, "spread": 40}, ls={"swing": 120, "spread": 40})
clip("Celebrate", 1.9, [
    key(0, REST),
    key(0.22, UP, "out"),
    key(0.45, PUMP, "smooth"),
    key(0.68, UP, "out"),
    key(0.91, PUMP, "smooth"),
    key(1.14, UP, "out"),
    key(1.6, UP, "linear"),
    key(1.9, REST),
], fade_in=0.1, fade_out=0.3, priority=4)

# Keeper dive to the right: the whole body tips over sideways, arms stretched past the head.
DIVE_R = pose(root={"lean": -74, "pos": [0.8, -1.0, 0]}, neck={"lean": 8},
              rh={"swing": 6, "spread": -6}, lh={"swing": -6, "spread": 26},
              rs={"swing": 8, "spread": 172}, ls={"swing": 14, "spread": 176})
DIVE_R_SET = pose(root={"lean": -14, "pitch": 8, "pos": [0, -0.3, 0]}, neck={},
                  rh={"spread": 12}, lh={"spread": 18},
                  rs={"swing": 20, "spread": 60}, ls={"swing": 20, "spread": 60})
dive_r = [
    key(0, REST),
    key(0.08, DIVE_R_SET, "out"),
    key(0.22, DIVE_R, "out", ground=False),
    key(0.55, DIVE_R, "linear", ground=False),
    key(0.75, REST),
]
clip("DiveRight", 0.75, dive_r, fade_in=0.06, fade_out=0.25, priority=4)
clip("DiveLeft", 0.75, [dict(k, p=mirror(k["p"])) for k in dive_r], fade_in=0.06, fade_out=0.25, priority=4)

with open(os.path.join(OUT, "_meta.json"), "w") as f:
    json.dump(META, f, indent=1)
print("clips:", ", ".join(META))

