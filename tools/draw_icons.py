"""Icon family for Full Mana Forever, Last Breath Forever and Full Health Forever.
Style C: bold and clear. Drawn at 2048 px (32x the 64 px grid), scaled down with LANCZOS.
usage: python3 tools/draw_icons.py <outdir>  (needs Pillow)"""
import math, os, struct, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

K = 32
S = 64 * K
CX, CY = 32.0, 38.5          # bulb / face centre on the 64 grid


def P(v):
    return v * K


# ---------- themes ----------
THEMES = {
    'fmf': dict(kind='flask',
                corner=(9, 16, 44), mid=(20, 44, 112), glow=(50, 140, 255),
                outline=(5, 10, 30),
                glass=(208, 230, 255), glass_sh=(150, 185, 235), inside=(24, 38, 82),
                liq=(38, 140, 255), liq_hi=(110, 196, 255), liq_sh=(18, 92, 222),
                rim=(16, 64, 170), spark=(226, 240, 255)),
    'fhf': dict(kind='flask',
                corner=(40, 8, 12), mid=(108, 24, 30), glow=(255, 60, 60),
                outline=(30, 4, 8),
                glass=(255, 222, 222), glass_sh=(232, 166, 170), inside=(78, 22, 30),
                liq=(232, 40, 50), liq_hi=(255, 112, 106), liq_sh=(170, 18, 36),
                rim=(126, 10, 26), spark=(255, 232, 230)),
    'lbf': dict(kind='watch',
                corner=(26, 9, 44), mid=(64, 22, 108), glow=(176, 70, 255),
                outline=(18, 5, 34),
                glass=(240, 224, 255), glass_sh=(196, 166, 232), inside=(48, 18, 80),
                liq=(150, 44, 228), liq_hi=(196, 112, 255), liq_sh=(106, 26, 180),
                wedge=(228, 186, 255),
                rim=(78, 18, 140), spark=(242, 228, 255)),
}

SPARKS = [(13.5, 16.5, 2.7), (50.5, 14.5, 2.4), (11.5, 47.5, 2.1), (52.5, 47.5, 2.2)]   # on pixel centres


# ---------- helpers ----------
def mask():
    return Image.new('L', (S, S), 0)


def fill(im, m, col):
    layer = Image.new('RGBA', (S, S), tuple(col[:3]) + (255,))
    im.paste(layer, (0, 0), m)


def circle(m, cx, cy, r, v=255):
    ImageDraw.Draw(m).ellipse([P(cx - r), P(cy - r), P(cx + r), P(cy + r)], fill=v)
    return m


def rrect(m, x0, y0, x1, y1, r, v=255):
    ImageDraw.Draw(m).rounded_rectangle([P(x0), P(y0), P(x1), P(y1)], radius=P(r), fill=v)
    return m


def poly(m, pts, v=255):
    ImageDraw.Draw(m).polygon([(P(x), P(y)) for x, y in pts], fill=v)
    return m


def mul(a, b):
    return ImageChops.multiply(a, b)


def sub(a, b):
    return ImageChops.subtract(a, b)


def add(a, b):
    return ImageChops.add(a, b)


def rot_rect(cx, cy, ang, x0, y0, x1, y1, r=0.0, n=10):
    """rounded rect in a frame rotated by ang degrees around (cx, cy); returns 64-grid points"""
    pts = []
    if r <= 0:
        base = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    else:
        base = []
        for ox, oy, a0 in [(x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)]:
            for k in range(n + 1):
                a = math.radians(a0 + 90 * k / n)
                base.append((ox + r * math.cos(a), oy + r * math.sin(a)))
    ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    for x, y in base:
        pts.append((cx + x * ca - y * sa, cy + x * sa + y * ca))
    return pts


# ---------- background ----------
def background(t):
    # radial gradient from mid (behind the object) to corner colour; computed small, scaled up
    n = 256
    g = Image.new('RGB', (n, n))
    px = g.load()
    c0, c1 = t['corner'], t['mid']
    for y in range(n):
        for x in range(n):
            d = math.hypot(x / n * 64 - 32, y / n * 64 - 36) / 40.0
            k = max(0.0, 1 - d) ** 1.6
            px[x, y] = tuple(int(c0[i] + (c1[i] - c0[i]) * k) for i in range(3))
    im = g.resize((S, S), Image.BICUBIC).convert('RGBA')
    # soft glow behind the object
    gm = circle(mask(), CX, CY, 20.5, 200)
    gm = gm.filter(ImageFilter.GaussianBlur(P(4.2)))
    fill(im, gm, t['glow'])
    gm2 = circle(mask(), CX, CY, 19.5, 120).filter(ImageFilter.GaussianBlur(P(1.6)))
    fill(im, gm2, t['glow'])
    return im


def sparkle_mask(x, y, r):
    m = mask()
    pts = []
    n = 64
    for i in range(4 * n):
        a = 2 * math.pi * i / (4 * n)
        # astroid-like four-point star with concave sides
        c, s = math.cos(a), math.sin(a)
        rr = r * (abs(c) ** 0.7 + abs(s) ** 0.7) ** (-1 / 0.7)
        pts.append((x + rr * c, y + rr * s))
    poly(m, pts)
    return m


def sparkles(im, t):
    for x, y, r in SPARKS:
        g = circle(mask(), x, y, r * 0.9, 110).filter(ImageFilter.GaussianBlur(P(r * 0.55)))
        fill(im, g, t['glow'])
        fill(im, sparkle_mask(x, y, r), t['spark'])


# ---------- infinity sign ----------
def infinity(im, t):
    icx, icy, w = 31.9, 39.4, 9.4
    pts = []
    for i in range(1800):
        a = 2 * math.pi * i / 1800
        den = 1 + math.sin(a) ** 2
        pts.append((icx + w * math.cos(a) / den, icy + 1.42 * w * math.sin(a) * math.cos(a) / den))

    def stroke(th):
        m = mask()
        d = ImageDraw.Draw(m)
        for x, y in pts:
            d.ellipse([P(x - th / 2), P(y - th / 2), P(x + th / 2), P(y + th / 2)], fill=255)
        return m
    rim = stroke(4.6).filter(ImageFilter.GaussianBlur(P(0.35)))
    fill(im, rim.point(lambda v: v * 0.92), t['rim'])
    fill(im, stroke(2.75), (255, 255, 255))


# ---------- flask ----------
def flask(im, t):
    R = 17.5            # glass outer radius
    o = 1.35            # dark outline width
    nw = 4.6            # neck half width (glass outer)
    ny0 = 12.6
    # silhouette outline: bulb + neck + cork, dilated
    om = mask()
    circle(om, CX, CY, R + o)
    rrect(om, CX - nw - o, ny0 - 1, CX + nw + o, CY - R + 4, 0.8)
    rrect(om, CX - 6.0 - o, 5.6 - o + 0.6, CX + 6.0 + o, ny0 + 1.2 + o * 0.5, 1.6)
    fill(im, om, t['outline'])
    # glass body
    gm = mask()
    circle(gm, CX, CY, R)
    rrect(gm, CX - nw, ny0, CX + nw, CY - R + 4, 0.0)
    fill(im, gm, t['glass'])
    # glass shade on the lower right (two-tone)
    sh = sub(circle(mask(), CX, CY, R), circle(mask(), CX - 1.2, CY - 1.4, R - 0.2))
    fill(im, sh, t['glass_sh'])
    # inside
    gw = 1.45
    ri = R - gw
    im_ = mask()
    circle(im_, CX, CY, ri)
    rrect(im_, CX - nw + gw, ny0 - 0.5, CX + nw - gw, CY - R + 4.5, 0)
    fill(im, im_, t['inside'])
    # liquid below the level line
    lvl = 25.6
    bulb_in = circle(mask(), CX, CY, ri)
    below = rrect(mask(), 0, lvl, 64, 64, 0)
    lm = mul(bulb_in, below)
    fill(im, lm, t['liq'])
    # lighter top band of the liquid
    band = mul(lm, rrect(mask(), 0, lvl, 64, lvl + 2.2, 0))
    fill(im, band, t['liq_hi'])
    # darker crescent bottom right (two-tone shading)
    cres = mul(lm, sub(circle(mask(), CX, CY, ri), circle(mask(), CX - 2.6, CY - 3.0, ri - 0.4)))
    fill(im, cres, t['liq_sh'])
    # surface line
    hw = math.sqrt(ri * ri - (CY - lvl) ** 2) - 0.2
    d = ImageDraw.Draw(im)
    d.rectangle([P(CX - hw), P(lvl - 0.1), P(CX + hw), P(lvl + 0.6)], fill=t['liq_hi'] + (255,))
    # glass highlight: clean white arc upper right + short neck line
    d.arc([P(CX - R + 2.4), P(CY - R + 2.4), P(CX + R - 2.4), P(CY + R - 2.4)], -64, -26,
          fill=(255, 255, 255, 240), width=int(P(1.25)))
    hl = circle(mask(), CX + (R - 3.0) * math.cos(math.radians(-16)), CY + (R - 3.0) * math.sin(math.radians(-16)), 0.65)
    fill(im, hl, (255, 255, 255))
    d.rectangle([P(CX + nw - gw - 1.2), P(ny0 + 1.2), P(CX + nw - gw - 0.3), P(CY - R + 2.0)], fill=(255, 255, 255, 120))
    # cork: two tone with a lighter top
    cm = rrect(mask(), CX - 6.0, 5.6 + 0.6, CX + 6.0, ny0 + 1.0, 1.0)
    fill(im, cm, (146, 92, 50))
    fill(im, mul(cm, rrect(mask(), 0, 0, 64, 8.4, 0)), (196, 138, 84))
    fill(im, mul(cm, rrect(mask(), CX + 2.8, 0, 64, 64, 0)), (118, 72, 38))


# ---------- stopwatch ----------
def watch(im, t):
    R = 18.3            # case outer radius
    o = 1.35
    W = t
    # buttons and crown: (angle, stem len, stem w, head w, head h, radius)
    parts = [(-50, 2.8, 2.8, 6.4, 3.5, 0.9), (50, 2.8, 2.8, 6.4, 3.5, 0.9), (0, 3.0, 3.4, 10.0, 3.9, 1.1)]

    def part_masks(e):
        m = mask()
        for ang, sl, sw, hw, hh, rad in parts:
            base = -R + 1.0
            poly(m, rot_rect(CX, CY, ang, -sw / 2 - e, base - sl - e, sw / 2 + e, base + e))
            poly(m, rot_rect(CX, CY, ang, -hw / 2 - e, base - sl - hh - e, hw / 2 + e, base - sl + e, rad + e * 0.6))
        return m
    om = part_masks(o)
    circle(om, CX, CY, R + o)
    fill(im, om, W['outline'])
    pm = part_masks(0)
    fill(im, pm, W['glass'])
    # shade on the right side of each head/stem (two-tone)
    shm = mask()
    for ang, sl, sw, hw, hh, rad in parts:
        base = -R + 1.0
        poly(shm, rot_rect(CX, CY, ang, sw * 0.1, base - sl, sw / 2, base))
        poly(shm, rot_rect(CX, CY, ang, hw * 0.18, base - sl - hh, hw / 2, base - sl, rad))
    fill(im, mul(shm, pm), W['glass_sh'])
    # dark line between head and stem so heads read as buttons
    lm = mask()
    for ang, sl, sw, hw, hh, rad in parts:
        base = -R + 1.0
        poly(lm, rot_rect(CX, CY, ang, -sw / 2 - 0.2, base - sl - 0.15, sw / 2 + 0.2, base - sl + 0.55))
    fill(im, lm, W['outline'])
    # case ring (outline separates it from the parts)
    fill(im, circle(mask(), CX, CY, R + 0.55), W['outline'])
    fill(im, circle(mask(), CX, CY, R - 0.1), W['glass'])
    sh = sub(circle(mask(), CX, CY, R - 0.1), circle(mask(), CX - 1.2, CY - 1.4, R - 0.3))
    fill(im, sh, W['glass_sh'])
    # dark inner rim and face
    r = R - 2.3
    fill(im, circle(mask(), CX, CY, r + 0.6), W['outline'])
    face = circle(mask(), CX, CY, r)
    fill(im, face, W['liq'])
    cres = mul(face, sub(circle(mask(), CX, CY, r), circle(mask(), CX - 2.4, CY - 2.8, r - 0.3)))
    fill(im, cres, W['liq_sh'])
    # wedge on the outer ring of the face, 12 to 2 o'clock
    ri = r * 0.64
    wm = mask()
    ImageDraw.Draw(wm).pieslice([P(CX - r), P(CY - r), P(CX + r), P(CY + r)], -90, -30, fill=255)
    wm = sub(wm, circle(mask(), CX, CY, ri))
    fill(im, wm, W['wedge'])
    # white hand at 2 o'clock across the ring, slightly past both edges
    ha = math.radians(60)
    a0 = (CX + (ri - 1.2) * math.sin(ha), CY - (ri - 1.2) * math.cos(ha))
    a1 = (CX + (r - 0.3) * math.sin(ha), CY - (r - 0.3) * math.cos(ha))
    hm = mask()
    d = ImageDraw.Draw(hm)
    w = 2.0
    d.line([P(a0[0]), P(a0[1]), P(a1[0]), P(a1[1])], fill=255, width=int(P(w)))
    for p in (a0, a1):
        d.ellipse([P(p[0] - w / 2), P(p[1] - w / 2), P(p[0] + w / 2), P(p[1] + w / 2)], fill=255)
    hm = mul(hm, circle(mask(), CX, CY, r - 0.05))
    # thin dark edge around the hand so it separates from the light wedge
    edge = hm.filter(ImageFilter.MaxFilter(int(P(0.9)) | 1))
    fill(im, mul(sub(edge, hm), face), W['outline'])
    fill(im, hm, (255, 255, 255))
    # glass highlight: white arc on the case ring, upper left
    d = ImageDraw.Draw(im)
    d.arc([P(CX - R + 0.55), P(CY - R + 0.55), P(CX + R - 0.55), P(CY + R - 0.55)], 196, 238,
          fill=(255, 255, 255, 245), width=int(P(1.0)))


# ---------- tile ----------
def tile_mask():
    m = mask()
    ImageDraw.Draw(m).rounded_rectangle([0, 0, S - 1, S - 1], radius=P(8.5), fill=255)
    return m


def draw(name):
    t = THEMES[name]
    im = background(t)
    sparkles(im, t)
    (flask if t['kind'] == 'flask' else watch)(im, t)
    infinity(im, t)
    # faint darker rim line inside the tile edge
    tm = tile_mask()
    rim = Image.new('L', (S, S), 0)
    ImageDraw.Draw(rim).rounded_rectangle([P(0.35), P(0.35), S - 1 - P(0.35), S - 1 - P(0.35)], radius=P(8.2),
                                          outline=255, width=int(P(0.7)))
    fill(im, rim.point(lambda v: v * 0.6), tuple(int(c * 0.55) for c in t['corner']))
    flat = Image.new('RGBA', (S, S), t['corner'] + (255,))
    flat.paste(im, (0, 0), tm)
    return flat, tm


def write_tga(img, path):
    img = img.convert('RGBA')
    w, h = img.size
    hdr = bytes([0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, w & 255, w >> 8, h & 255, h >> 8, 32, 8])
    px = img.load()
    data = bytearray()
    for y in range(h - 1, -1, -1):
        for x in range(w):
            r, g, b, a = px[x, y]
            data += bytes((b, g, r, a))
    with open(path, 'wb') as f:
        f.write(hdr + bytes(data) + b'\0' * 8 + b'TRUEVISION-XFILE.\0')


def main(out):
    os.makedirs(out, exist_ok=True)
    smalls = {}
    for name in ('fmf', 'lbf', 'fhf'):
        flat, tm = draw(name)
        flat.resize((1024, 1024), Image.LANCZOS).save(os.path.join(out, name + '_1024.png'))
        cf = flat.copy()
        cf.putalpha(tm)
        cf = cf.resize((512, 512), Image.LANCZOS)
        a = cf.split()[3]
        cf.putalpha(a.point(lambda v: 0 if v < 3 else v))
        cf.save(os.path.join(out, name + '_512_curseforge.png'))
        sm = flat.resize((64, 64), Image.LANCZOS).convert('RGB').convert('RGBA')
        write_tga(sm, os.path.join(out, name + '_icon.tga'))
        smalls[name] = (flat.resize((512, 512), Image.LANCZOS), cf)
    # preview
    bgc = (30, 30, 30, 255)
    pw = 3 * 200 + 40
    pv = Image.new('RGBA', (pw, 340), bgc)
    for i, name in enumerate(('fmf', 'lbf', 'fhf')):
        big, cf = smalls[name]
        x0 = 40 + i * 200
        pv.alpha_composite(cf.resize((160, 160), Image.LANCZOS), (x0, 20))
        x = x0
        for s in (64, 48, 32, 24):
            pv.alpha_composite(cf.resize((s, s), Image.LANCZOS), (x, 200 + (64 - s)))
            x += s + 6
    pv.save(os.path.join(out, 'preview_family.png'))


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
