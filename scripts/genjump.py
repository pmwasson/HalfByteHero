# Generate jump table: VY per tick (signed 8.8), and check the arc.
# Per tick: VY += g (rise g while VY < 0, fall g otherwise), clamp, Y += VY.
import math

def table(v0, g_rise, g_fall, vmax, scale):
    """Simulate in exact floats, quantize each VY entry to 8.8."""
    v, out = v0, []
    while True:
        v += g_rise if v < 0 else g_fall
        v = min(v, vmax)
        out.append(round(v * 256))
        if out[-1] >= round(vmax * 256) and len(out) > 1 and out[-2] >= round(vmax * 256):
            break
    return out

def arc(entries, term, extra=4):
    """Integer 8.8 playback like playerStepY, Y starts at 0 (subpixel 0)."""
    y, rows = 0, []
    for e in entries + [term] * extra:
        y += e
        rows.append(math.floor(y / 256))
    return rows

def report(name, t, term, cut_v):
    rows = arc(t, term)
    land = next(i for i, r in enumerate(rows) if i > 0 and r >= 0 and rows[i - 1] < 0)
    cut = next(i for i, e in enumerate(t) if e >= cut_v)
    fall = next(i for i, e in enumerate(t) if e >= 0)
    print(f"{name}: len={len(t)} peak={min(rows)} back_at_row0_tick={land} CUT_IDX={cut} FALL_IDX={fall}")
    return rows

t30 = table(-1.0, 0x1A / 256, 0x26 / 256, 1.0, 1)
print("30Hz matches spec:", [f"{e & 0xFFFF:04X}" for e in t30])
r30 = report("30Hz", t30, 0x100, round(-0.4 * 256))

t60 = table(-0.5, 0x1A / 256 / 4, 0x26 / 256 / 4, 0.5, 2)
r60 = report("60Hz", t60, 0x80, round(-0.2 * 256))

print("rows 30Hz        :", r30[:20])
print("rows 60Hz (every2):", r60[1::2][:20])
print("lo:", ",".join(f"${e & 0xFF:02X}" for e in t60))
print("hi:", ",".join(f"${(e >> 8) & 0xFF:02X}" for e in t60))
