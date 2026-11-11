"""Keys every game clip on the R6IK rig in the open Blender session (60 fps, Bezier, auto-clamped).

Run through the bridge after rbx_bake.py and rig_pose.py are loaded. Each clip is one Blender action
on __PrimaryArmature, so it can be scrubbed, tweaked by hand in the Graph Editor, and re-baked.
Controls (world = character axes: +X right, +Y forward, +Z up, studs):
  M  MasterControl      whole body (dives only: it also carries the feet)
  P  LowerTorso-FK      pelvis/torso: loc moves the hips (z < 0 crouches), rot tilts the torso
  RF/LF RightLeg-IK / LeftLeg-IK   foot targets (rest at the ground under each hip)
  RA/LA RightUpperArm / LeftUpperArm   FK arms (rx > 0 forward, RIGHT arm out = ry < 0, LEFT arm out = ry > 0)
  H  Head (FK: rx < 0 nods down, rz > 0 turns left)
Principles used on purpose: anticipation before every kick, a fast contact, overshoot and settle,
arms keyed 1-3 frames after the legs (overlap), pelvis weight shifts, never a key on every joint at
the same frame in the middle of a move.
"""
import bpy, math

N = {"M": "MasterControl", "P": "LowerTorso-FK", "RF": "RightLeg-IK", "LF": "LeftLeg-IK",
     "RA": "RightUpperArm", "LA": "LeftUpperArm", "H": "Head"}
CLIPS = {}


def pose(**kw):
    out = {}
    for short, v in kw.items():
        if isinstance(v, dict):
            out[N[short]] = v
        else:  # (loc, rot) tuple or rot only for FK
            loc, rot = v if len(v) == 2 and isinstance(v[0], tuple) else ((0, 0, 0), v)
            out[N[short]] = {"loc": loc, "rot": rot}
    return out


def L(x, y, z):
    return (x, y, z)


REST_BONES = ["P", "RF", "LF", "RA", "LA", "H"]


def rest(*extra):
    # extra (MasterControl) first: the other controls are placed relative to it
    return pose(**{s: ((0, 0, 0), (0, 0, 0)) for s in list(extra) + REST_BONES})


def clip(name, frames, keys, loop=False, fade_in=0.06, fade_out=0.18, priority=3, uses_master=False):
    CLIPS[name] = {"frames": frames, "keys": keys, "loop": loop, "fadeIn": fade_in, "fadeOut": fade_out,
                   "priority": priority, "master": uses_master}


def full(p, *extra):
    """Fill every standard bone so the first/last keys pin the whole body."""
    base = rest(*extra)
    base.update(p)
    return base


# ------------------------------------------------------------------ locomotion
STRIDE_F, STRIDE_B = 1.15, -1.2
run_a = pose(P=(L(0, 0.15, -0.12), (-14, 0, -7)),
             RF=(L(0, STRIDE_F, 0.05), (0, 0, 0)), LF=(L(0, STRIDE_B, 0.7), (0, 0, 0)),
             RA=(-52, 0, 0), LA=(58, 0, 0), H=(8, 0, 6))
run_pass = pose(P=(L(0, 0.15, 0.08), (-14, 0, 0)),
                RF=(L(0, -0.1, 0.0), (0, 0, 0)), LF=(L(0, 0.3, 0.75), (0, 0, 0)),
                RA=(-5, 0, 0), LA=(10, 0, 0), H=(8, 0, 0))
clip("Run", 32, [
    (0, full(run_a)),
    (5, pose(P=(L(0, 0.15, -0.22), (-15, 0, -5)))),           # weight drops onto the front foot
    (8, full(run_pass)),
    (16, full(mirror_pose(run_a))),
    (21, pose(P=(L(0, 0.15, -0.22), (-15, 0, 5)))),
    (24, full(mirror_pose(run_pass))),
    (32, full(run_a)),
], loop=True, fade_in=0.15, fade_out=0.15, priority=0)

idle_a = pose(P=(L(0, 0, -0.06), (-3, 0, 0)), RF=(L(0.12, 0.05, 0), (0, 0, -8)), LF=(L(-0.12, -0.1, 0), (0, 0, 8)),
              RA=(4, -6, 0), LA=(-2, 7, 0), H=(-4, 0, 0))
idle_b = pose(P=(L(0, 0, -0.12), (-5, 0, 0)), RF=(L(0.12, 0.05, 0), (0, 0, -8)), LF=(L(-0.12, -0.1, 0), (0, 0, 8)),
              RA=(6, -9, 0), LA=(0, 10, 0), H=(-6, 0, 4))
clip("Idle", 150, [(0, full(idle_a)), (75, full(idle_b)), (150, full(idle_a))],
     loop=True, fade_in=0.25, fade_out=0.25, priority=0)

# ------------------------------------------------------------------ kicks
WINDUP = pose(P=(L(0, -0.05, -0.18), (-6, 0, -22)),
              RF=(L(0.05, -1.45, 0.85), (0, 0, 0)), LF=(L(-0.1, 0.35, 0), (0, 0, 10)),
              RA=(-38, -32, 0), LA=(34, 48, 0), H=(-16, 0, 12))
WINDUP_DEEP = pose(P=(L(0, -0.08, -0.24), (-8, 0, -27)),
                   RF=(L(0.08, -1.7, 1.05), (0, 0, 0)), LF=(L(-0.1, 0.4, 0), (0, 0, 12)),
                   RA=(-46, -38, 0), LA=(40, 56, 0), H=(-18, 0, 16))
clip("ChargeHold", 42, [(0, full(WINDUP)), (21, full(WINDUP_DEEP)), (42, full(WINDUP))],
     loop=True, fade_in=0.14, fade_out=0.12, priority=2)

clip("Shoot", 31, [
    (0, full(WINDUP)),
    (3, pose(RF=(L(0.05, -0.6, 0.35), (0, 0, 0)), P=(L(0, 0, -0.2), (-4, 0, -8)))),
    (6, pose(RF=(L(0, 1.25, 0.45), (0, 0, 0)), P=(L(0, 0.05, -0.16), (4, 0, 10)), H=(-14, 0, -4))),   # contact
    (8, pose(RA=(26, -36, 0), LA=(-24, 62, 0))),
    (12, pose(RF=(L(0.08, 1.9, 1.95), (0, 0, 0)), P=(L(0, 0.05, -0.08), (12, 0, 16)), H=(-6, 0, -10))),
    (15, pose(RA=(42, -42, 0), LA=(-34, 66, 0))),
    (19, pose(RF=(L(0.05, 1.3, 0.9), (0, 0, 0)), P=(L(0, 0.1, -0.16), (2, 0, 8)))),
    (24, pose(RF=(L(0.02, 0.45, 0.05), (0, 0, 0)), RA=(8, -14, 0), LA=(-6, 18, 0), H=(-4, 0, 0))),
    (31, full(rest())),
], fade_in=0.04, fade_out=0.2)

clip("PowerShot", 42, [
    (0, full(WINDUP_DEEP)),
    (6, pose(RF=(L(0.1, -1.95, 1.25), (0, 0, 0)), P=(L(0, -0.1, -0.3), (-10, 0, -34)),
             RA=(-60, -48, 0), LA=(52, 64, 0), H=(-18, 0, 22))),
    (10, pose(P=(L(0, 0.1, 0.35), (0, 0, -12)), LF=(L(-0.1, 0.45, 0.45), (0, 0, 10)),
              RF=(L(0.05, -0.4, 0.9), (0, 0, 0)))),                                   # hop
    (13, pose(RF=(L(0, 1.45, 1.0), (0, 0, 0)), P=(L(0, 0.15, 0.3), (10, 0, 14)), H=(-14, 0, -6))),  # contact
    (15, pose(RA=(40, -52, 0), LA=(-36, 74, 0))),
    (19, pose(RF=(L(0.1, 1.6, 2.7), (0, 0, 0)), P=(L(0, 0.15, 0.2), (20, 0, 22)), LF=(L(-0.1, 0.4, 0.3), (0, 0, 10)))),
    (21, pose(RA=(56, -58, 0), LA=(-48, 80, 0), H=(-2, 0, -12))),
    (26, pose(P=(L(0, 0.25, -0.38), (-10, 0, 8)), RF=(L(0.1, 0.9, 0.0), (0, 0, 0)), LF=(L(-0.1, 0.2, 0), (0, 0, 10)),
              RA=(14, -34, 0), LA=(-8, 40, 0), H=(-10, 0, -4))),                      # land
    (32, pose(P=(L(0, 0.15, -0.16), (-4, 0, 3)), RF=(L(0.05, 0.4, 0), (0, 0, 0)))),
    (42, full(rest())),
], fade_in=0.06, fade_out=0.22, priority=4)

clip("Pass", 22, [
    (0, full(pose(P=(L(0, 0, -0.08), (-4, 0, 0))))),
    (5, pose(RF=(L(0.2, -0.75, 0.3), (0, 0, -35)), P=(L(0, -0.03, -0.14), (-4, 0, -9)), H=(-16, 0, 6))),
    (7, pose(RA=(-18, -22, 0), LA=(18, 32, 0))),
    (10, pose(RF=(L(-0.25, 0.75, 0.18), (0, 0, -40)), P=(L(0, 0.05, -0.14), (-6, 0, 9)))),   # contact
    (13, pose(RF=(L(-0.35, 1.05, 0.35), (0, 0, -40)), RA=(14, -28, 0), LA=(-12, 36, 0), H=(-10, 0, -2))),
    (22, full(rest())),
], fade_in=0.04, fade_out=0.16)

clip("Lob", 28, [
    (0, full(pose(P=(L(0, 0, -0.08), (-4, 0, 0))))),
    (6, pose(RF=(L(0, -1.15, 0.55), (0, 0, 0)), P=(L(0, -0.05, -0.2), (-6, 0, -12)), H=(-14, 0, 8))),
    (8, pose(RA=(-30, -26, 0), LA=(30, 36, 0))),
    (11, pose(RF=(L(0, 1.0, 0.22), (0, 0, 0)), P=(L(0, 0, -0.2), (10, 0, 6)))),              # scoop under the ball
    (16, pose(RF=(L(0, 1.65, 1.35), (0, 0, 0)), P=(L(0, 0, -0.06), (18, 0, 8)), H=(10, 0, 0))),
    (18, pose(RA=(30, -64, 0), LA=(18, 72, 0))),
    (22, pose(RF=(L(0, 0.8, 0.4), (0, 0, 0)), P=(L(0, 0.05, -0.12), (6, 0, 4)))),
    (28, full(rest())),
], fade_in=0.04, fade_out=0.18)

# ------------------------------------------------------------------ defence / movement
SLIDE = pose(P=(L(0.15, 0.2, -1.5), (52, -14, 6)),
             RF=(L(0.25, 2.15, 0.0), (0, 0, 0)), LF=(L(-0.4, 0.95, 0.0), (0, 0, 25)),
             RA=(74, -30, 0), LA=(-50, 58, 0), H=(-38, 0, 0))
clip("Slide", 48, [
    (0, full(rest())),
    (4, pose(P=(L(0.05, 0.25, -0.75), (16, -6, 4)), RF=(L(0.15, 1.3, 0.25), (0, 0, 0)),
             LF=(L(-0.25, 0.3, 0.0), (0, 0, 15)))),
    (6, pose(RA=(44, -30, 0), LA=(-30, 44, 0), H=(-18, 0, 0))),
    (9, full(SLIDE)),
    (30, pose(P=(L(0.15, 0.2, -1.45), (48, -12, 5)), RF=(L(0.25, 2.05, 0.0), (0, 0, 0)))),
    (38, pose(P=(L(0.05, 0.2, -0.6), (2, -2, 2)), RF=(L(0.1, 0.8, 0.0), (0, 0, 0)), LF=(L(-0.15, 0.2, 0), (0, 0, 8)),
              RA=(20, -16, 0), LA=(-10, 20, 0), H=(-8, 0, 0))),
    (48, full(rest())),
], fade_in=0.07, fade_out=0.22, priority=4)

clip("Dribble", 24, [
    (0, full(pose(P=(L(0, 0, -0.1), (-6, 0, 0))))),
    (4, pose(RF=(L(0.15, 0.55, 0.55), (0, 0, 0)), P=(L(0.05, 0, -0.18), (-8, -6, -6)), H=(-18, 0, 4))),
    (6, pose(RA=(-10, -48, 0), LA=(14, 40, 0))),
    (8, pose(RF=(L(-0.35, 0.7, 0.45), (0, 0, 0)))),                                     # step-over
    (11, pose(RF=(L(0.6, 0.3, 0.0), (0, 0, -15)), P=(L(0.35, 0.05, -0.32), (-10, 12, -10)))),
    (13, pose(RA=(16, -40, 0), LA=(-12, 58, 0), H=(-12, 0, -8))),
    (16, pose(LF=(L(-0.55, -0.35, 0.3), (0, 0, 0)), P=(L(0.1, 0.1, -0.2), (-12, -8, 6)))),     # push off
    (24, full(rest())),
], fade_in=0.04, fade_out=0.16)

clip("Dash", 23, [
    (0, full(rest())),
    (3, pose(P=(L(0, 0.35, -0.25), (-26, 0, 0)), RF=(L(0, -1.35, 0.6), (0, 0, 0)), LF=(L(0, 1.0, 0.25), (0, 0, 0)),
             H=(14, 0, 0))),
    (5, pose(RA=(64, 0, 0), LA=(-52, 8, 0))),
    (14, pose(P=(L(0, 0.3, -0.18), (-22, 0, 0)), RF=(L(0, -1.1, 0.5), (0, 0, 0)), LF=(L(0, 0.8, 0.2), (0, 0, 0)))),
    (16, pose(RA=(52, 0, 0), LA=(-44, 8, 0))),
    (23, full(rest())),
], fade_in=0.05, fade_out=0.16)

clip("Stun", 48, [
    (0, full(rest())),
    (4, pose(P=(L(0, -0.25, -0.2), (22, 6, 12)), H=(26, 0, -10), LF=(L(-0.1, -0.6, 0.0), (0, 0, 0)))),
    (6, pose(RA=(-12, -64, 0), LA=(-8, 70, 0))),
    (14, pose(P=(L(0, 0, -0.32), (-12, -4, -6)), H=(-12, 0, 8))),
    (17, pose(RA=(6, -22, 0), LA=(4, 26, 0))),
    (24, pose(P=(L(0.05, 0, -0.22), (4, 6, 4)), H=(4, 3, -4))),
    (34, pose(P=(L(0, 0, -0.1), (-4, -2, 0)), H=(-4, 0, 0), RA=(2, -10, 0), LA=(0, 10, 0),
              LF=(L(-0.05, -0.2, 0), (0, 0, 0)))),
    (48, full(rest())),
], fade_in=0.05, fade_out=0.25, priority=5)

UP = pose(RA=(168, -16, 0), LA=(154, 26, 0), H=(22, 0, 0))
clip("Celebrate", 114, [
    (0, full(rest())),
    (9, pose(P=(L(0, -0.05, -0.45), (-14, 0, 0)), RA=(-30, -14, 0), LA=(-28, 14, 0), H=(-12, 0, 0))),
    (17, pose(P=(L(0, 0, 0.75), (-2, 0, 0)), RF=(L(0, 0, 0.65), (0, 0, 0)), LF=(L(0, -0.1, 0.55), (0, 0, 0)))),
    (19, UP),
    (28, pose(P=(L(0, 0, -0.32), (-6, 0, 0)), RF=(L(0, 0, 0), (0, 0, 0)), LF=(L(0, 0, 0), (0, 0, 0)))),
    (36, pose(P=(L(0, 0, -0.06), (-2, 0, 0)), RA=(172, -10, 0), LA=(-12, 34, 0), H=(16, 0, 10))),
    (46, pose(RA=(96, -26, 0), P=(L(0, 0, -0.14), (-6, 0, -6)))),
    (56, pose(RA=(172, -10, 0), P=(L(0, 0, -0.04), (-1, 0, 4)))),
    (66, pose(RA=(96, -26, 0), P=(L(0, 0, -0.14), (-6, 0, -6)))),
    (76, pose(RA=(176, -8, 0), P=(L(0, 0, -0.02), (0, 0, 6)), H=(24, 0, 10))),
    (98, pose(RA=(150, -14, 0), LA=(-6, 26, 0), P=(L(0, 0, -0.06), (-2, 0, 2)))),
    (114, full(rest())),
], fade_in=0.1, fade_out=0.3, priority=4)

# ------------------------------------------------------------------ goalkeeper
dive_set = pose(M=(L(0, 0, 0), (0, 0, 0)), P=(L(0, 0.1, -0.38), (-12, 10, 0)),
                RF=(L(0.25, 0, 0), (0, 0, 0)), LF=(L(-0.25, 0, 0), (0, 0, 0)),
                RA=(22, -44, 0), LA=(22, 44, 0), H=(-6, 0, -10))
dive_push = pose(M=(L(0.55, 0, 0.25), (0, 32, 0)), LF=(L(-0.25, 0, -0.35), (0, 0, 0)), P=(L(0, 0.1, -0.1), (-6, 6, 0)))
dive_full = pose(M=(L(1.25, 0, -1.55), (0, 84, 0)), P=(L(0, 0, 0), (-4, 0, 0)),
                 RF=(L(0.1, 0, 0.1), (0, 0, 0)), LF=(L(-0.1, 0, -0.1), (0, 0, 0)),
                 RA=(20, -166, 0), LA=(26, 150, 0), H=(0, 0, -14))
dive_r = [
    (0, full(rest("M"))),
    (5, dive_set),
    (10, dive_push),
    (12, pose(RA=(22, -120, 0), LA=(24, 110, 0))),
    (16, dive_full),
    (30, pose(M=(L(1.3, 0, -1.62), (0, 86, 0)))),
    (38, pose(M=(L(0.7, 0, -0.85), (0, 44, 0)), RA=(12, -60, 0), LA=(12, 56, 0), P=(L(0, 0, -0.2), (-6, 4, 0)))),
    (45, full(rest("M"))),
]
clip("DiveRight", 45, dive_r, fade_in=0.06, fade_out=0.25, priority=4, uses_master=True)
clip("DiveLeft", 45, [(f, mirror_pose(p)) for f, p in dive_r], fade_in=0.06, fade_out=0.25, priority=4,
     uses_master=True)


def build(name):
    c = CLIPS[name]
    act = new_action(name, c["frames"])
    clear_action_keys(act)
    _last_q.clear()
    reset_pose()
    for frame, p in c["keys"]:
        key(frame, p)
    set_interp(act)
    if c["loop"]:
        for fc in _fcurves(act):
            # make loops seamless: the curve's ends meet with matching slopes
            if not any(m.type == "CYCLES" for m in fc.modifiers):
                fc.modifiers.new("CYCLES")
            fc.update()
    act["rbx"] = {k: c[k] for k in ("loop", "fadeIn", "fadeOut", "priority")}
    return act


def build_all():
    for name in CLIPS:
        build(name)
    return list(CLIPS)
