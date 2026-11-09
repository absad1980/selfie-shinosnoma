"""Repairs three problems in the men's suit layers (app/assets/suits/m*.png):

  m03, m04, m09  open shirt V reaching into the chest (the customer's neck would be stretched into it) ->
                 rebuilt from good closed-collar suits by recolouring jacket, shirt and tie:
                 m03 = m01 with a charcoal jacket and burgundy tie
                 m04 = m05 with a light blue shirt and navy tie
                 m09 = m02 with a grey tie
  m06            the gold tie knot lost its middle (its warm colour was taken for skin) ->
                 rebuilt from m07 with a brown jacket and gold tie
  m10            the AI generator's watermark on the jacket -> painted over with the jacket fabric beside it

Run after regenerating the suits:  python tools/fix_men_suits.py   (needs: pip install pillow numpy)
"""
import json
import os

import numpy as np
from PIL import Image

SUITS = os.path.join(os.path.dirname(__file__), '..', 'app', 'assets', 'suits')


def load(name):
    return np.array(Image.open(os.path.join(SUITS, name + '.png')).convert('RGBA')).astype(float)


def save(name, a):
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(os.path.join(SUITS, name + '.png'), optimize=True)
    print('fixed', name)


def close_v(name, c):
    """Keeps the collar's own V opening down to just under the collar points, then closes the shirt below a
    gently curved line with shirt fabric. Colours are sampled well inside the shirt and smoothed, so no streaks."""
    a = load(name)
    h, w = a.shape[:2]
    fw, nx, chin = c['faceW'], c['neckX'], c['chinY']
    y_close = chin + fw * .3  # bottom of the remaining collar opening (about where a buttoned collar meets)
    lift = fw * .06
    runs = {}
    for y in range(int(chin + 10), h):
        # the transparent run around the neck centre (search a few px either side, the V tip may be off-centre)
        x0 = None
        for dx in range(0, 8):
            for xx in (int(nx) + dx, int(nx) - dx):
                if 0 <= xx < w and a[y, xx, 3] == 0:
                    x0 = xx
                    break
            if x0 is not None:
                break
        if x0 is None:
            continue
        l = x0
        while l > 0 and a[y, l - 1, 3] == 0:
            l -= 1
        r = x0
        while r < w - 1 and a[y, r + 1, 3] == 0:
            r += 1
        if l == 0 or r == w - 1 or r - l > fw * .9:
            continue
        runs[y] = (l, r)
    if not runs:
        return
    # one shirt colour per side, from a patch well inside the shirt, then smoothed down the rows
    ys = sorted(runs)
    left = {y: a[max(0, y - 4):y + 5, max(0, runs[y][0] - 12):max(1, runs[y][0] - 6), :3].reshape(-1, 3).mean(0) for y in ys}
    right = {y: a[max(0, y - 4):y + 5, runs[y][1] + 7:runs[y][1] + 13, :3].reshape(-1, 3).mean(0) for y in ys}
    for y in ys:
        l, r = runs[y]
        hw = max(1.0, (r - l) / 2)
        for x in range(l - 2, r + 3):  # 2 px wider: covers the thin skin fringe on the V edges
            if not 0 <= x < w:
                continue
            edge_y = y_close - lift * ((x - nx) / hw) ** 2
            if y < edge_y:
                continue
            t = min(1.0, max(0.0, (x - l) / max(1, r - l)))
            col = left[y] * (1 - t) + right[y] * t
            d = y - edge_y
            if d < 3:
                col = col * (.8 + .06 * d)  # soft shadow under the collar edge
            elif abs(x - nx) < 1.2 and y > y_close + fw * .08:
                col = col * .95  # faint button placket
            a[y, x, :3] = col
            a[y, x, 3] = 255
    save(name, a)


def fix_knot(name, c):
    """Refills the tie knot from its top down to the solid tie, between the outer tie edges (smoothed over rows),
    with a rounded light-to-dark shading like real silk."""
    a = load(name)
    h, w = a.shape[:2]
    fw, nx = c['faceW'], c['neckX']
    rgb = a[..., :3]
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0)
    gold = (a[..., 3] > 0) & (sat > .35) & (rgb[..., 0] > rgb[..., 2] + 30) & (np.abs(np.arange(w)[None, :] - nx) < fw * .3)
    ys, xs = np.where(gold)
    top = ys.min()
    solid_rows = [y for y in range(top, h) if gold[y, int(nx) - 2:int(nx) + 3].all()]
    solid_top = next((y for y in solid_rows if y > top + 5), top + int(fw * .25))
    solid = a[solid_top + 2:solid_top + 12, int(nx) - 4:int(nx) + 5, :3].reshape(-1, 3).mean(0)
    bounds = {}
    for y in range(top, solid_top + 1):
        row = xs[ys == y]
        if len(row) >= 1:
            bounds[y] = (row.min(), row.max())
    yy = sorted(bounds)
    for y in range(top, solid_top + 1):
        near = [bounds[k] for k in yy if abs(k - y) <= 3]
        if not near:
            continue
        l = int(np.mean([b[0] for b in near]))
        r = int(np.mean([b[1] for b in near]))
        for x in range(l, r + 1):
            u = (x - (l + r) / 2) / max(1, (r - l) / 2)  # -1 … 1 across the knot
            v = (y - top) / max(1, solid_top - top)  # 0 top … 1 bottom
            shade = 1.08 - .28 * u * u - .1 * v
            a[y, x, :3] = solid * shade
            a[y, x, 3] = 255
    save(name, a)


def remove_mark(name, cx, cy, r):
    """Replaces a small round area with the average of the fabric left, right, above and below it, feathered."""
    a = load(name)
    src = a.copy()
    o = 2 * r + 4
    for y in range(cy - r - 3, cy + r + 4):
        for x in range(cx - r - 3, cx + r + 4):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** .5
            if d > r + 3:
                continue
            fill = (src[y, x - o] + src[y, x + o if x + o < a.shape[1] else x - o - 4] + src[y - o, x] + src[y + o if y + o < a.shape[0] else y - o - 4, x]) / 4
            k = 1.0 if d <= r else 1 - (d - r) / 3
            a[y, x] = src[y, x] * (1 - k) + fill * k
    save(name, a)


def tie_mask(a, c, tol):
    """The tie: grown by colour similarity from seeds every few pixels straight down the centre (knot to bottom),
    each seed matched to its own local colour, so creases and shading don't stop it; kept inside a central strip."""
    from collections import deque
    h, w = a.shape[:2]
    fw, nx, chin = c['faceW'], c['neckX'], c['chinY']
    rgb = a[..., :3]
    sx = int(round(nx))
    knot = next(y for y in range(int(chin + 10), h) if a[y, sx, 3] > 0 and rgb[y, sx].min() < 200)
    m = np.zeros((h, w), bool)
    refs = []
    for sy in range(int(knot + 3), h - 2, 6):
        if a[sy, sx, 3] == 0 or rgb[sy, sx].min() >= 200 or m[sy, sx]:
            continue
        ref = rgb[sy - 1:sy + 2, sx - 1:sx + 2].reshape(-1, 3).mean(0)
        refs.append(ref)
        q = deque([(sy, sx)])
        m[sy, sx] = True
        while q:
            y, x = q.popleft()
            for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= yy < h and 0 <= xx < w and not m[yy, xx] and a[yy, xx, 3] > 0                         and abs(xx - nx) < fw * .2 and yy > chin + fw * .1                         and np.abs(rgb[yy, xx] - ref).sum() < tol and rgb[yy, xx].min() < 215:
                    m[yy, xx] = True
                    q.append((yy, xx))
    # second pass: shaded sides of the tie — any non-white pixel joined to it inside the strip
    q = deque(zip(*np.nonzero(m)))
    while q:
        y, x = q.popleft()
        for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= yy < h and 0 <= xx < w and not m[yy, xx] and a[yy, xx, 3] > 0                     and abs(xx - nx) < fw * .17 and yy > knot - 2 and rgb[yy, xx].min() < 195:
                m[yy, xx] = True
                q.append((yy, xx))
    ref = np.mean(refs, axis=0) if refs else np.array([128., 128, 128])
    return m, ref


def derive(base, new, c, tie_tol, jacket_mul=None, tie_rgb=None, shirt_tint=None, jacket_rgb=None):
    a = load(base)
    rgb = a[..., :3].copy()
    al = a[..., 3] > 0
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0)
    lum = .299 * rgb[..., 0] + .587 * rgb[..., 1] + .114 * rgb[..., 2]
    tie, ref = tie_mask(a, c, tie_tol)
    shirt = al & (lum > 170) & (sat < .14) & ~tie
    ref_lum = .299 * ref[0] + .587 * ref[1] + .114 * ref[2]
    # tie edge band (1–2 px around the tie): blend by how close each pixel is to the tie colour vs the shirt
    from PIL import ImageFilter
    grow = np.array(Image.fromarray((tie * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))) > 0
    band = grow & ~tie & al
    shirt_ref = rgb[shirt].mean(0) if shirt.any() else np.array([240., 240, 240])
    jacket = al & ~shirt & ~grow
    if jacket_mul is not None:
        a[jacket, :3] *= jacket_mul
    if jacket_rgb is not None:
        # new jacket colour, keeping the fabric's light and shade
        jl = lum[jacket]
        a[jacket, :3] = np.array(jacket_rgb, float)[None, :] * np.clip(jl / max(1, jl.mean()), .4, 1.8)[:, None]
    if tie_rgb is not None:
        target = np.array(tie_rgb, float)
        k = np.clip(lum / max(1, ref_lum), .4, 1.15)[..., None]  # capped: light edge pixels are half shirt
        recol = target[None, None, :] * k
        a[tie, :3] = recol[tie]
        dt = np.abs(rgb - ref).sum(-1)
        ds = np.abs(rgb - shirt_ref).sum(-1)
        t = np.clip(ds / np.maximum(1, ds + dt), 0, 1)
        # edge pixels are half shirt: give them the tie colour at its normal brightness, not the shirt's
        edge_col = target[None, :] * np.clip(k[band], .4, 1.0)
        a[band, :3] = (rgb[band] * (1 - t[band, None]) + edge_col * t[band, None])
    if shirt_tint is not None:
        a[shirt, :3] *= np.array(shirt_tint, float)[None, :]
    save(new, a)


def shallow_collar(name, c):
    """Turns the deep see-through V (where the AI model's neck was) into a shallow collar opening:
    the V stays open only a little below the collar tips; below that it is closed with the shirt's own colour,
    shaded like a collar band. Records 'throat' = the bottom of the remaining opening, where the suit meets the neck."""
    a = load(name)
    h, w = a.shape[:2]
    fw, nx = c['faceW'], c['neckX']
    xs = [x for x in range(int(nx - fw * .45), int(nx + fw * .45)) if 0 <= x < w]
    tops = {}
    for x in xs:
        col = np.nonzero(a[:, x, 3] > 128)[0]
        if len(col):
            tops[x] = col[0]
    left = [tops[x] for x in tops if x < nx]
    right = [tops[x] for x in tops if x > nx]
    wing = max(min(left), min(right))  # the lower of the two collar tips
    # the opening stays open about halfway from the collar tips down to the tie knot
    x0 = int(round(nx))
    knot = next((y for y in range(int(wing), h) if a[y, x0, 3] > 0), int(wing + fw * .35))
    throat = int(wing + (knot - wing) * .5)
    # shirt colour: from the collar wings just beside the opening, below the tips
    samples = []
    for y in range(int(wing + 4), int(wing + fw * .25)):
        row = a[y]
        x0 = int(round(nx))
        if row[x0, 3] > 0:
            continue
        l = x0
        while l > 0 and row[l - 1, 3] == 0:
            l -= 1
        r = x0
        while r < w - 1 and row[r + 1, 3] == 0:
            r += 1
        for xx in (l - 5, l - 4, r + 4, r + 5):
            if 0 <= xx < w and row[xx, 3] > 0 and row[xx, :3].min() > 150:
                samples.append(row[xx, :3])
    # the shirt's lit white (not its shadows)
    shirt = np.percentile(np.array(samples), 90, axis=0) if samples else np.array([240., 240, 240])
    # the opening's bottom edge is a V: lowest (the throat point) in the middle, rising toward the collar
    lift = fw * .08
    opening_w = None
    for y in range(int(throat - lift), h):
        x0 = int(round(nx))
        if a[y, x0, 3] > 0:
            continue
        l = x0
        while l > 0 and a[y, l - 1, 3] == 0:
            l -= 1
        r = x0
        while r < w - 1 and a[y, r + 1, 3] == 0:
            r += 1
        if l == 0 or r == w - 1:
            continue
        for x in range(l - 1, r + 2):
            u = (x - nx) / max(1, (r - l) / 2)
            edge_y = throat - lift * min(1.0, abs(u))
            if y < edge_y - 1:
                continue
            cover = min(1.0, max(0.0, y - edge_y + 1) / 2)  # smooth, anti-aliased top edge
            shade = .96 + .04 * (1 - min(1.0, u * u))  # a touch lighter in the middle
            if a[y, x, 3] > 0 and cover < 1:
                continue  # never paint over the collar itself
            a[y, x, :3] = shirt * shade
            a[y, x, 3] = max(a[y, x, 3], 255 * cover)
    save(name, a)
    # width of the collar opening near its top (the collar tips), for sizing the suit to the neck
    yy = int(wing + fw * .03)
    l = r = int(round(nx))
    while l > 0 and a[yy, l - 1, 3] == 0:
        l -= 1
    while r < w - 1 and a[yy, r + 1, 3] == 0:
        r += 1
    return throat, r - l


if __name__ == '__main__':
    anchors = json.load(open(os.path.join(SUITS, 'anchors.json')))
    # rebuilt suits take their base suit's anchors (same body and framing)
    for new, base in (('m03', 'm01'), ('m04', 'm05'), ('m09', 'm02')):
        anchors[new] = dict(anchors[base])
    json.dump(anchors, open(os.path.join(SUITS, 'anchors.json'), 'w'), indent=1)
    derive('m01', 'm03', anchors['m01'], 90, jacket_mul=.62, tie_rgb=(118, 28, 44))
    derive('m05', 'm04', anchors['m05'], 60, tie_rgb=(28, 40, 78), shirt_tint=(.84, .91, 1.0))
    derive('m02', 'm09', anchors['m02'], 70, tie_rgb=(105, 108, 116))
    anchors['m06'] = dict(anchors['m07'])
    json.dump(anchors, open(os.path.join(SUITS, 'anchors.json'), 'w'), indent=1)
    derive('m07', 'm06', anchors['m07'], 80, jacket_rgb=(62, 46, 36), tie_rgb=(176, 128, 46))
    remove_mark('m10', 305, 404, 13)
    # every men's suit: shallow collar opening, and where it meets the neck
    for n in [f'm{i:02d}' for i in range(1, 11)]:
        anchors[n]['throat'], anchors[n]['openW'] = shallow_collar(n, anchors[n])
    json.dump(anchors, open(os.path.join(SUITS, 'anchors.json'), 'w'), indent=1)
