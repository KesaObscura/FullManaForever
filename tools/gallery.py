# CurseForge gallery images (1280x720). Usage: python3 tools/gallery.py <work dir>/ [01 02 ...]
# The work dir holds images/<n>.webp (in-game screenshots) and gets gallery/out/*.png.
# Needs Pillow. Not part of the addon zip.
# Gallery images for CurseForge: 1280x720, dark background, title, game crops in framed panels.
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont
BASE = (sys.argv[1].rstrip("/") + "/") if len(sys.argv) > 1 and sys.argv[1].endswith("/") else "./"
W, H = 1280, 720
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
GOLD, BLUE, WHITE, SUB = (242, 201, 76), (90, 140, 230), (240, 244, 252), (160, 178, 214)

def background():
    bg = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(bg)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=(int(12 + 10 * t), int(18 + 16 * t), int(34 + 28 * t)))
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse((W * 0.15, H * 0.25, W * 0.85, H * 1.25), fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    bg = Image.composite(Image.new("RGB", (W, H), (40, 70, 130)), bg, glow)
    return bg

def crop(src, box, scale):
    im = Image.open(BASE + src).convert("RGB").crop(box)
    return im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS)

def rounded(im, r=14):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), r, fill=255)
    return mask

def make(out, title, subtitle, panels, top=158, stack=False):
    bg = background()
    d = ImageDraw.Draw(bg)
    d.text((60, 44), title, font=ImageFont.truetype(BOLD, 40), fill=WHITE)
    if subtitle:
        d.text((62, 100), subtitle, font=ImageFont.truetype(REG, 22), fill=SUB)
    cap = ImageFont.truetype(BOLD, 22)
    if stack:
        y = top
        for im, caption in panels:
            x = (W - im.width) // 2 - 120
            bg.paste(im, (x, y), rounded(im))
            d.rounded_rectangle((x - 2, y - 2, x + im.width + 1, y + im.height + 1), 15, outline=BLUE, width=2)
            d.text((x + im.width + 30, y + im.height / 2 - 14), caption, font=cap, fill=GOLD)
            y += im.height + 40
        foot = ImageFont.truetype(REG, 16)
        t = "Full Mana Forever  ·  WoW: Forever"
        d.text((W - 40 - d.textlength(t, font=foot), H - 36), t, font=foot, fill=(120, 136, 170))
        bg.save(BASE + "gallery/out/" + out, optimize=True)
        return
    gap = 70
    slots = [max(p[0].width, d.textlength(p[1] or "", font=cap)) for p in panels]
    total = sum(slots) + gap * (len(panels) - 1)
    x0 = (W - total) / 2
    for (im, caption), slot in zip(panels, slots):
        x = int(x0 + (slot - im.width) / 2)
        y = top
        sh = Image.new("RGBA", (im.width + 40, im.height + 40), (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle((20, 24, im.width + 20, im.height + 24), 16, fill=(0, 0, 0, 150))
        sh = sh.filter(ImageFilter.GaussianBlur(10))
        bg.paste(sh, (x - 20, y - 20), sh)
        bg.paste(im, (x, y), rounded(im))
        d.rounded_rectangle((x - 2, y - 2, x + im.width + 1, y + im.height + 1), 15, outline=BLUE, width=2)
        if caption:
            tw = d.textlength(caption, font=cap)
            d.text((x + (im.width - tw) / 2, y + im.height + 18), caption, font=cap, fill=GOLD)
        x0 += slot + gap
    foot = ImageFont.truetype(REG, 16)
    t = "Full Mana Forever  ·  WoW: Forever"
    d.text((W - 40 - d.textlength(t, font=foot), H - 36), t, font=foot, fill=(120, 136, 170))
    bg.save(BASE + "gallery/out/" + out, optimize=True)

def only(name):
    args = [a for a in sys.argv[1:] if not a.endswith("/")]
    return not args or name in args

if __name__ == "__main__":
    ROW = (1150, 135, 1480, 255)  # row layout frame (bar under the icons)
    if only("01"):
        make("01_hero.png", "Drink at the right moment",
             "The icon lights up when the potion is ready and fits into your missing mana: nothing wasted.",
             [(crop("images/113.webp", ROW, 3.2), "")], top=190)
    if only("03r"):
        make("03_five_second_rule_row.png", "Five-second rule and live mana regen",
             "After a spell: gold strip and seconds. The regen running right now, also in combat.",
             [(crop("images/114.webp", ROW, 1.85), "Casting:\n4.0 s left, regen 0.0/s"),
              (crop("images/113.webp", ROW, 1.85), "Rule over:\nregen 15.3/s")], top=160, stack=True)
    if only("07"):
        LIB = (1003, 2, 1557, 600)
        make("07_item_list.png", "Item list",
             "Every supported item with its restore value. Switch single items off or add your own.",
             [(crop("images/111.webp", LIB, 0.78), "Potions and runes"),
              (crop("images/112.webp", LIB, 0.78), "Other consumables and gear")], top=145)
    COL = (1300, 62, 1440, 372)  # column layout frame in the 1920x1080 shots
    s = 1.4
    make("02_right_potion.png", "The right potion for your missing mana",
         "Several potions in your bags: the strongest one that will not overflow lights up.",
         [(crop("images/108.webp", COL, s), "72 % mana: small potion"),
          (crop("images/107.webp", COL, s), "35 % mana: stronger potion")])
    make("03_five_second_rule.png", "Five-second rule and live mana regen",
         "After a spell: gold strip and seconds. The regen running right now, also in combat.",
         [(crop("images/107.webp", COL, s), "Casting: 4.4 s, regen 0.0/s"),
          (crop("images/106.webp", COL, s), "Rule over: regen 15.3/s")])
    if only("08"):
        make("08_unlocked.png", "Easy to place",
             "Unlock the frame: everything that is switched on shows up, grey where you carry nothing.",
             [(crop("images/117.webp", (1165, 128, 1485, 250), 3.0), "")], top=190)
    if only("05"):
        BAR = (1178, 216, 1474, 241)
        make("05_mana_text.png", "Mana text like the game's Status Text",
             "Number, percentage, both or nothing on the bar, plus the regen next to it.",
             [(crop("images/121.webp", BAR, 2.5), "Number"),
              (crop("images/120.webp", BAR, 2.5), "Percentage"),
              (crop("images/119.webp", BAR, 2.5), "Both"),
              (crop("images/118.webp", BAR, 2.5), "None")], top=170, stack=True)
    if only("06"):
        make("06_settings.png", "Settings that explain themselves",
             "Hover any option for a short explanation. Reset position and Reset size undo your experiments.",
             [(crop("images/111.webp", (80, 2, 960, 626), 0.83), "")], top=150)
    if only("09"):
        make("09_own_spells.png", "Your own mana spells too",
             "Eureka!, Evocation, Innervate, Mana Tide, Inner Focus, Life Tap: lit when ready and your mana is low.",
             [(crop("images/144.webp", (1150, 150, 1475, 240), 3.0), "")], top=200)
    if only("07n"):
        make("08_unlocked.png", "Easy to place",
             "Unlock the frame: everything that is switched on shows up, grey where you carry nothing.",
             [(crop("images/141.webp", (1150, 132, 1480, 240), 2.9), "")], top=190)
    if only("06n"):
        S = (196, 168, 1076, 772)
        make("06_settings.png", "Settings that explain themselves",
             "Hover any option for a short explanation. Reset position and Reset size undo your experiments.",
             [(crop("images/141.webp", (196, 168, 636, 772), 0.8), "Display and look"),
              (crop("images/141.webp", (636, 168, 1076, 772), 0.8), "Visibility, drinking, own spells")], top=145)
