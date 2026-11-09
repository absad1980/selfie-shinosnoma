"""Removes the AI model's leftover hair and backdrop bits from the women's suit layers (app/assets/suits/w*.png).

Run after regenerating the suits (MAKE_SUITS=1 flutter test test/make_suits_test.dart):
    python tools/clean_women_suits.py            (needs: pip install pillow numpy)

Steps, all limited to the band above the shoulders:
  1. small separate blobs of hair colour (dark, grey) or backdrop colour (light grey/white) are removed;
     big connected pieces (a black jacket, a cream blouse collar) stay
  2. very thin slivers sticking up (under 7 px wide) are removed
  3. only the main garment piece is kept
  4. a light or dark fringe along the garment's top edge is stripped (3 passes)
"""
import json
import os
from collections import deque

import numpy as np
from PIL import Image

SUITS = os.path.join(os.path.dirname(__file__), '..', 'app', 'assets', 'suits')


def components(m):
    h, w = m.shape
    lab = np.zeros((h, w), int)
    sizes = [0]
    cur = 0
    for y in range(h):
        for x in range(w):
            if m[y, x] and not lab[y, x]:
                cur += 1
                q = deque([(y, x)])
                lab[y, x] = cur
                n = 0
                while q:
                    a, b = q.popleft()
                    n += 1
                    for c, d in ((a + 1, b), (a - 1, b), (a, b + 1), (a, b - 1)):
                        if 0 <= c < h and 0 <= d < w and m[c, d] and not lab[c, d]:
                            lab[c, d] = cur
                            q.append((c, d))
                sizes.append(n)
    return lab, np.array(sizes)


def horizontal_open(m, r):
    """Keeps only runs of opaque pixels at least 2r+1 wide (or touching the image edge)."""
    h, w = m.shape
    out = np.zeros_like(m)
    for y in range(h):
        row = m[y]
        x = 0
        while x < w:
            if row[x]:
                s = x
                while x < w and row[x]:
                    x += 1
                if x - s >= 2 * r + 1 or s == 0 or x == w:
                    out[y, s:x] = True
            else:
                x += 1
    return out


def clean(name, anchors):
    path = os.path.join(SUITS, name + '.png')
    a = np.array(Image.open(path).convert('RGBA'))
    h, w = a.shape[:2]
    rgb = a[..., :3].astype(int)
    fw, nx, sh = anchors['faceW'], anchors['neckX'], anchors['shoulder']
    yy, xx = np.mgrid[0:h, 0:w]
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0)
    lum = .299 * rgb[..., 0] + .587 * rgb[..., 1] + .114 * rgb[..., 2]

    band = (yy < sh + fw * .1) & (np.abs(xx - nx) < fw * .9)
    m = a[..., 3] > 0
    for colour in ((lum < 75) & (sat < .35), (lum > 150) & (sat < .05)):
        lab, sz = components(m & band & colour)
        small = np.isin(lab, np.nonzero(sz < 900)[0]) & (lab > 0)
        m &= ~small
    m = np.where(band, horizontal_open(m, 3), m)
    lab, sz = components(m)
    sz[0] = 0
    m = lab == sz.argmax()
    a[..., 3] = np.where(m, a[..., 3], 0)

    top = yy < sh + fw * .15
    for _ in range(3):
        al = a[..., 3] > 0
        nb = np.zeros_like(al)
        nb[1:, :] |= ~al[:-1, :]
        nb[:-1, :] |= ~al[1:, :]
        nb[:, 1:] |= ~al[:, :-1]
        nb[:, :-1] |= ~al[:, 1:]
        edge = al & nb & top
        fringe = edge & (((lum > 165) & (sat < .07)) | ((lum < 60) & (sat < .3) & (np.abs(xx - nx) < fw * .75) & (yy < sh)))
        a[..., 3] = np.where(fringe, 0, a[..., 3])
    Image.fromarray(a).save(path, optimize=True)
    print('cleaned', name)


if __name__ == '__main__':
    anchors = json.load(open(os.path.join(SUITS, 'anchors.json')))
    for n in sorted(anchors):
        if n.startswith('w'):
            clean(n, anchors[n])
