#!/usr/bin/env python3
"""Read the current wallpaper and work out what the wizard is standing in.

This is heuristic scene reading, not object recognition. It separates his
walking band into dark ground and brighter water, finds anomalously warm
points (lit windows, lamps, glowing crystals), and calls a tight cluster of
them a structure. It cannot tell a castle from a cathedral, so it reports
shape and lets the wizard hedge about what he is looking at.

Every threshold is relative to the wallpaper's own distribution, so nothing
here is tuned to one picture -- but a wallpaper with no clear shoreline, or
no lights, correctly yields no water and no structures rather than
inventing them.
"""

import json
import os
import sys

import numpy as np
from PIL import Image

STATE_LINK = os.path.expanduser("~/.local/state/omarchy/current/background")

COLS = 512  # analysis columns across the screen


def luminance(a):
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def cover_map(img_w, img_h, screen_w, screen_h):
    """Replicate Image.PreserveAspectCrop so analysis coords match the screen."""
    scale = max(screen_w / img_w, screen_h / img_h)
    return scale, (img_w * scale - screen_w) / 2.0, (img_h * scale - screen_h) / 2.0


def visible_part(path, screen_w, screen_h):
    """Just the part of the wallpaper the compositor actually shows."""
    img = Image.open(path).convert("RGB")
    scale, off_x, off_y = cover_map(img.width, img.height, screen_w, screen_h)
    left, top = off_x / scale, off_y / scale
    box = (int(left), int(top),
           int(round(left + screen_w / scale)), int(round(top + screen_h / scale)))
    return img.crop(box)


def otsu(values):
    """Threshold and separation quality for a 1-D set."""
    order = np.sort(values)
    best_t, best_v = float(np.median(values)), -1.0
    for q in np.linspace(0.08, 0.92, 80):
        t = float(np.quantile(order, q))
        lo, hi = values[values <= t], values[values > t]
        if len(lo) < 6 or len(hi) < 6:
            continue
        v = len(lo) * len(hi) * (lo.mean() - hi.mean()) ** 2
        if v > best_v:
            best_v, best_t = v, t
    spread = max(1e-6, float(values.max() - values.min()))
    lo, hi = values[values <= best_t], values[values > best_t]
    if len(lo) < 6 or len(hi) < 6:
        return best_t, 0.0
    # How far apart the two groups sit, as a fraction of the whole range.
    return best_t, float(hi.mean() - lo.mean()) / spread


def smooth_bool(mask, width):
    """Median-filter a mask so a single stray column can't flip the surface."""
    if width < 3:
        return mask
    pad = width // 2
    padded = np.pad(mask.astype(np.float32), pad, mode="edge")
    return np.array([padded[i:i + width].mean() > 0.5 for i in range(len(mask))])


def classify_surface(band):
    """Split the walking band into water and ground.

    Measured on real wallpapers, the split is strongly bimodal in plain
    luminance: foreground rock is near-black, open water is mid-tone. Adding
    texture terms only let bright reflection streaks stripe the lake, so this
    deliberately uses brightness alone and then insists the two groups are
    genuinely far apart before calling anything water.
    """
    lum = luminance(band)
    # Median down the column: a bright reflection streak shifts the mean far
    # more than it shifts the median.
    col = np.median(lum, axis=0)

    cut, separation = otsu(col)

    # Without a real valley between the two groups this is one continuous
    # surface, not a shoreline. Better to report dry land than a phantom lake.
    if separation < 0.28:
        return np.zeros(len(col), dtype=bool), separation, cut

    is_water = smooth_bool(col > cut, 9)

    # A body of water is a few broad spans. Alternating slivers mean the
    # threshold is slicing up textured ground -- a city skyline, mist, trees --
    # so drop the narrow ones and, if what is left is still confetti, conclude
    # there is no water here at all.
    min_span = max(6, int(len(col) * 0.06))
    is_water = drop_narrow(is_water, min_span)
    transitions = int(np.count_nonzero(np.diff(is_water.astype(np.int8))))
    if transitions > 6:
        return np.zeros(len(col), dtype=bool), separation, cut

    return is_water, separation, cut


def drop_narrow(mask, min_span):
    """Erase runs shorter than min_span, in both directions."""
    out = mask.copy()
    for value in (True, False):
        start = None
        for i in range(len(out) + 1):
            on = i < len(out) and out[i] == value
            if on and start is None:
                start = i
            elif not on and start is not None:
                if i - start < min_span:
                    out[start:i] = not value
                start = None
    return out


def runs_of(mask, step, screen_w):
    out, start = [], 0
    for i in range(1, len(mask) + 1):
        if i == len(mask) or mask[i] != mask[start]:
            out.append({
                "x0": int(start * step),
                "x1": int(min(screen_w, i * step)),
                "kind": "water" if bool(mask[start]) else "land",
            })
            start = i
    return out


def find_waterline(whole, is_water, screen_h):
    """Top edge of the water, and how convincingly sharp that edge is.

    Averaging the luminance profile across every water column first is the
    whole trick: per-column scans are dominated by reflection streaks running
    far up the image, whereas a real shoreline is one sharp step that all the
    columns share, and averaging makes it the only thing left standing.

    Everything below the line is surface reflection, which is what makes a
    sunset glow and its mirrored pillar merge into one building-shaped blob.
    """
    water_cols = np.nonzero(is_water)[0]
    rows = whole.shape[0]
    if len(water_cols) < 8:
        return screen_h, 0.0

    profile = luminance(whole[:, water_cols]).mean(axis=1)
    kernel = np.ones(3) / 3.0
    smoothed = np.convolve(profile, kernel, mode="same")
    gradient = np.abs(np.diff(smoothed))

    lo, hi = int(rows * 0.30), int(rows * 0.97)
    if hi - lo < 4:
        return screen_h, 0.0
    idx = lo + int(np.argmax(gradient[lo:hi]))
    # Sharpness relative to the image's usual row-to-row change. A lake edge
    # towers over it; mist and pavement have no such step.
    baseline = max(1e-6, float(np.percentile(gradient, 65)))
    return (idx + 1) / rows * screen_h, float(gradient[idx] / baseline)


def find_lights(a):
    """Points whose colour is anomalously warm for this wallpaper.

    Lit windows and lamps are warm against almost any scene; keying off the
    image's own R-B distribution means a warm-toned wallpaper raises the bar
    instead of lighting up everywhere.
    """
    warm = a[..., 0] - a[..., 2]
    lum = luminance(a)
    floor = max(8.0, float(np.percentile(warm, 99.2)))
    hot = (warm > floor) & (lum > float(np.percentile(lum, 55)))
    ys, xs = np.nonzero(hot)
    if len(xs) == 0:
        return [], hot
    strength = warm[ys, xs] + lum[ys, xs] * 0.25
    return list(zip(xs.tolist(), ys.tolist(), strength.tolist())), hot


def find_crystals(visible, screen_w, screen_h):
    """Bright, strongly coloured, *cool* glows down near the shore.

    Lit windows are warm against almost any scene; the crystals on the bank
    are the opposite -- magenta and violet, measurably brighter than anything
    around them but with red no higher than blue.

    Run at much finer resolution than the rest of the pass: a crystal is a
    thin bright spike, and the 10x10 blocks the global downsample uses average
    it straight back into the dark rock behind it.
    """
    band_top = int(visible.height * 0.70)
    crop = visible.crop((0, band_top, visible.width, visible.height))
    cw = 1024
    ch = max(48, int(cw * crop.height / crop.width))
    a = np.asarray(crop.resize((cw, ch), Image.BOX), dtype=np.float32)

    lum = luminance(a)
    mx = a.max(axis=2)
    mn = a.min(axis=2)
    sat = (mx - mn) / np.maximum(1.0, mx)
    warm = a[..., 0] - a[..., 2]

    floor = max(90.0, float(np.percentile(lum, 99.2)))
    hot = (lum > floor) & (sat > 0.3) & (warm < 20)

    ys, xs = np.nonzero(hot)
    if len(xs) == 0:
        return []

    order = np.argsort(-lum[ys, xs])
    out, taken = [], []
    for i in order:
        x = float(xs[i]) / cw * screen_w
        y = (band_top + float(ys[i]) / ch * crop.height) / visible.height * screen_h
        if any(abs(x - tx) < screen_w * 0.025 for tx in taken):
            continue
        taken.append(x)
        out.append({
            "kind": "crystal",
            "x": int(x),
            "y": int(y),
            "score": round(float(lum[ys[i], xs[i]] / 255.0), 2),
        })
        if len(out) >= 6:
            break
    return out


def cluster_lights(points, screen_w, screen_h):
    """Grid-cluster warm points; a dense cluster is a lit structure."""
    if not points:
        return [], []
    cell = max(24, int(screen_w / 90))
    buckets = {}
    for x, y, s in points:
        buckets.setdefault((x // cell, y // cell), []).append((x, y, s))

    seen, clusters = set(), []
    for key in buckets:
        if key in seen:
            continue
        stack, members = [key], []
        seen.add(key)
        while stack:
            cx, cy = stack.pop()
            members.extend(buckets[(cx, cy)])
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    nb = (cx + dx, cy + dy)
                    if nb in buckets and nb not in seen:
                        seen.add(nb)
                        stack.append(nb)
        clusters.append(members)

    structures, lamps = [], []
    for members in clusters:
        xs = [m[0] for m in members]
        ys = [m[1] for m in members]
        weight = sum(m[2] for m in members)
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        w, h = x1 - x0, y1 - y0
        # A handful of lights spread over some width reads as a building; one
        # or two tight points read as a lamp or a glowing crystal.
        aspect = h / max(1.0, w)
        # A wide, flat glow is a horizon or a light shaft, not a building.
        # Real structures are either compact or taller than they are wide.
        looks_built = aspect > 0.22 or w < screen_w * 0.05
        if len(members) >= 3 and weight > 260 and max(w, h) > screen_w / 160 and looks_built:
            shape = "tower" if aspect > 1.3 else ("keep" if aspect > 0.45 else "hall")
            # Keep a spread of the actual lit points so something can shimmer
            # in the real windows rather than at made-up spots in a box.
            bright = sorted(members, key=lambda m: -m[2])
            windows, taken = [], []
            for wx, wy, _ in bright:
                if any(abs(wx - tx) < 14 and abs(wy - ty) < 14 for tx, ty in taken):
                    continue
                taken.append((wx, wy))
                windows.append([int(wx), int(wy)])
                if len(windows) >= 14:
                    break

            structures.append({
                "kind": "structure",
                "windows": windows,
                "shape": shape,
                "x": int((x0 + x1) / 2),
                "x0": int(x0), "x1": int(x1),
                "y": int(y0), "y1": int(y1),
                "lights": len(members),
                "score": round(min(1.0, weight / 3000.0), 2),
            })
        else:
            lamps.append({
                "kind": "light",
                "x": int(sum(xs) / len(xs)),
                "y": int(sum(ys) / len(ys)),
                "score": round(min(1.0, weight / 400.0), 2),
            })

    structures = drop_reflections(structures, screen_h)
    lamps = drop_reflections(lamps + structures, screen_h)
    lamps = [l for l in lamps if l["kind"] == "light"]
    structures.sort(key=lambda s: -s["score"])
    lamps.sort(key=lambda s: -s["score"])
    return structures[:6], lamps[:10]


def drop_reflections(items, screen_h):
    """Discard anything that looks like its own mirror image in the water.

    A lit castle on a lake produces a second, dimmer castle directly beneath
    it. Without this the wizard cheerfully sets off to visit a reflection.
    """
    keep = []
    for item in items:
        x0 = item.get("x0", item["x"] - 12)
        x1 = item.get("x1", item["x"] + 12)
        mirrored = False
        for other in items:
            if other is item:
                continue
            ox0 = other.get("x0", other["x"] - 12)
            ox1 = other.get("x1", other["x"] + 12)
            if min(x1, ox1) - max(x0, ox0) <= 0:
                continue
            if item["y"] > other["y"] + 24 and item["y"] > screen_h * 0.55:
                mirrored = True
                break
        if not mirrored:
            keep.append(item)
    return keep


def ground_profile(whole, is_water, screen_h, samples=256):
    """Height of the walkable ground for each column, in screen pixels.

    The near-field foreground is the dark band that reaches the bottom of the
    picture, so scanning up from the bottom while the column stays dark traces
    the top of the rocks and banks he can actually stand on. Water columns take
    the waterline instead -- a lake surface is the ground, as far as a boat is
    concerned.
    """
    rows, cols = whole.shape[0], whole.shape[1]
    lum = luminance(whole)
    dark_cut = float(np.percentile(lum, 28))

    ground = np.empty(cols, dtype=np.float32)
    for x in range(cols):
        y = rows - 1
        while y > 0 and lum[y, x] < dark_cut:
            y -= 1
        ground[x] = y + 1
    # Water takes the near edge of the picture, not the waterline. The lake is
    # a surface seen in perspective: its far edge is the waterline, but a boat
    # drawn full-size up there would be a giant on the horizon. He sails the
    # near shore, where his scale is honest.
    # Held a little off the very bottom edge, so there is lake below the hull
    # for his reflection to fall on. Sitting flush with the screen edge would
    # push the whole reflection off-screen.
    if is_water.any():
        ground[is_water] = rows - 1 - max(2, int(rows * 0.055))

    # Drape the profile: walkable ground cannot have cliffs in it. Taking the
    # top of the dark silhouette literally means the line rides up and over
    # every crystal, bush and rock spire in the foreground, and anyone
    # standing there is perched on a spike rather than on the bank.
    #
    # Two passes clip any rise steeper than a person could walk, from each
    # direction, which pulls thin tall features down into the slope around
    # them while leaving broad hills intact.
    max_rise = 1.3  # rows of climb per analysis column
    for i in range(1, cols):
        ground[i] = max(ground[i], ground[i - 1] - max_rise)
    for i in range(cols - 2, -1, -1):
        ground[i] = max(ground[i], ground[i + 1] - max_rise)

    pad = 3
    padded = np.pad(ground, pad, mode="edge")
    ground = np.array([padded[i:i + 2 * pad + 1].mean() for i in range(cols)])

    # Plant them a little into the surface rather than balanced exactly on the
    # boundary pixel, which reads as hovering.
    ground = np.minimum(ground + rows * 0.008, rows - 1)

    idx = np.linspace(0, cols - 1, samples)
    return [int(round(float(np.interp(i, np.arange(cols), ground)) / rows * screen_h))
            for i in idx]


def analyse(path, screen_w, screen_h, walk_h):
    visible = visible_part(path, screen_w, screen_h)

    # Full-height pass for lights, at analysis width.
    rows = max(120, int(COLS * screen_h / screen_w))
    whole = np.asarray(visible.resize((COLS, rows), Image.BOX), dtype=np.float32)
    sx, sy = screen_w / COLS, screen_h / rows

    # The walking band keeps its native vertical detail: it is only ~120px
    # tall, and downsampling it to a few rows throws away the shoreline.
    band_img = visible.crop((0, visible.height - max(8, int(walk_h * visible.height / screen_h)),
                             visible.width, visible.height))
    band = np.asarray(band_img.resize((COLS, 48), Image.BOX), dtype=np.float32)
    is_water, separation, cut = classify_surface(band)

    waterline, edge = (find_waterline(whole, is_water, screen_h)
                       if is_water.any() else (screen_h, 0.0))
    # No sharp shoreline means the bright band is not a water surface.
    if edge < 3.0:
        is_water = np.zeros_like(is_water)
        waterline = screen_h

    points, _ = find_lights(whole)
    points = [(int(x * sx), int(y * sy), s) for x, y, s in points]
    # Reflections live below the waterline; dropping them here stops a glow
    # and its mirror image from clustering into one building-shaped mass.
    points = [p for p in points if p[1] < waterline - 4]
    structures, lamps = cluster_lights(points, screen_w, screen_h)
    crystals = find_crystals(visible, screen_w, screen_h)

    ground = ground_profile(whole, is_water, screen_h)
    step_px = screen_w / COLS

    # Crystals grow out of the bank, not out of the lake. Moonlight on open
    # water is bright, cool and saturated too, and is otherwise indistinguishable.
    runs = runs_of(is_water, step_px, screen_w)

    def on_land(x):
        for run in runs:
            if run["x0"] <= x < run["x1"]:
                return run["kind"] == "land"
        return True

    crystals = [c for c in crystals if on_land(c["x"])]

    return {
        "ground": ground,
        "groundStep": round(screen_w / (len(ground) - 1), 3),
        "step": round(step_px, 3),
        "source": path,
        "screen": {"w": screen_w, "h": screen_h},
        "walkHeight": walk_h,
        "surface": runs,
        "waterFraction": round(float(is_water.mean()), 3),
        "waterline": int(waterline),
        "shoreEdge": round(edge, 2),
        "separation": round(separation, 3),
        "pois": structures + lamps + crystals,
    }


def main():
    screen_w = int(sys.argv[1]) if len(sys.argv) > 1 else 1920
    screen_h = int(sys.argv[2]) if len(sys.argv) > 2 else 1080
    walk_h = int(sys.argv[3]) if len(sys.argv) > 3 else 120
    path = sys.argv[4] if len(sys.argv) > 4 else os.path.realpath(STATE_LINK)
    if not os.path.exists(path):
        print(json.dumps({"error": "no background", "surface": [], "pois": []}))
        return
    print(json.dumps(analyse(path, screen_w, screen_h, walk_h)))


if __name__ == "__main__":
    main()
