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
        for p in panels:
            im, caption = p[0], p[1]
            color = p[2] if len(p) > 2 else GOLD  # optional caption colour
            x = (W - im.width) // 2 - 120
            bg.paste(im, (x, y), rounded(im))
            d.rounded_rectangle((x - 2, y - 2, x + im.width + 1, y + im.height + 1), 15, outline=BLUE, width=2)
            d.text((x + im.width + 30, y + im.height / 2 - 14), caption, font=cap, fill=color)
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

def hide_name(im):
    # the player frame's name (a real character) is blurred out
    box = (500, 290, 760, 320)
    im.paste(im.crop(box).filter(ImageFilter.GaussianBlur(8)), box[:2])
    return im

def social(avatar, shot, box):
    # GitHub social preview (1280x640): avatar, name, what it does, the hero shot
    bg = background().crop((0, 40, W, 680))
    d = ImageDraw.Draw(bg)
    av = Image.open(BASE + avatar).convert("RGBA").resize((230, 230), Image.LANCZOS)
    bg.paste(av, (70, 60), av)
    d.text((340, 92), "Full Mana Forever", font=ImageFont.truetype(BOLD, 64), fill=WHITE)
    d.text((344, 178), "Mana potion timing, five-second rule", font=ImageFont.truetype(REG, 30), fill=SUB)
    d.text((344, 218), "and live mana regen for WoW Forever", font=ImageFont.truetype(REG, 30), fill=SUB)
    im = crop(shot, box, 1.25)
    x, y = (W - im.width) // 2, 330
    bg.paste(im, (x, y), rounded(im))
    d.rounded_rectangle((x - 2, y - 2, x + im.width + 1, y + im.height + 1), 15, outline=BLUE, width=2)
    bg.save(BASE + "gallery/out/social_preview.png", optimize=True)

def only(name):
    args = [a for a in sys.argv[1:] if not a.endswith("/")]
    return not args or name in args

if __name__ == "__main__":
    # 0.8.2 shots: English client, icon size 96, bar 30, text sizes 200 %, over water
    BIG = (845, 95, 1420, 275)
    if only("01"):
        make("01_hero.png", "Drink at the right moment",
             "Potions light up when they fit into your missing mana, your own mana spells when they are ready.",
             [(crop("images/192.webp", BIG, 1.6), "")], top=180)
    if only("social"):
        social("images/234.png", "images/192.webp", BIG)
    if only("02"):
        make("02_right_potion.png", "The right potion for your missing mana",
             "Several potions in your bags: the strongest one that will not overflow lights up.",
             [(crop("images/195.webp", BIG, 0.95), "82 % mana:\nsmall potion"),
              (crop("images/193.webp", BIG, 0.95), "69 % mana:\nstronger potion")], top=160, stack=True)
    if only("03r"):
        make("03_five_second_rule_row.png", "Five-second rule and live mana regen",
             "After a spell: gold strip and seconds. The regen running right now, also in combat.",
             [(crop("images/194.webp", BIG, 0.95), "Casting:\n3.1 s left, regen 0.0/s"),
              (crop("images/193.webp", BIG, 0.95), "Rule over:\nregen 15.5/s")], top=160, stack=True)
    if only("10"):
        BAR = (1140, 180, 1430, 222)  # row layout, mana full: bar, numbers, seconds and regen
        make("10_regen_colors.png", "Your regen at a glance",
             "Light blue: normal. Green: above normal (drinking, Spirit Tap, ...). Gold: five-second rule.",
             [(crop("images/182.webp", BAR, 1.9), "Normal:\n15.5/s", (153, 217, 255)),
              (crop("images/181.webp", BAR, 1.9), "Drinking:\n23.9/s", (115, 255, 115)),
              (crop("images/180.webp", BAR, 1.9), "Drinking right after a spell:\n8.4/s, rule 2.2 s", GOLD)],
             top=170, stack=True)
    if only("07"):
        LIB = (1003, 2, 1557, 600)
        make("07_item_list.png", "Item list",
             "Every supported item with its restore value. Switch single items off or add your own.",
             [(crop("images/111.webp", LIB, 0.78), "Potions and runes"),
              (crop("images/112.webp", LIB, 0.78), "Other consumables and gear")], top=145)
    if only("03c"):
        COL = (1060, 52, 1290, 595)  # 0.8.2 big shots, icons in a column
        make("03_five_second_rule.png", "Icons in a column",
             "The same in a column: seconds above the bar, mana and regen below it.",
             [(crop("images/210.webp", COL, 0.85), "Casting: 3.2 s, regen 0.0/s"),
              (crop("images/209.webp", COL, 0.85), "Rule over: regen 15.5/s")], top=140)
    if only("08"):
        make("08_unlocked.png", "Easy to place",
             "Unlock the frame: everything that is switched on shows up, grey where you carry nothing.",
             [(crop("images/215.webp", (770, 195, 1460, 385), 1.5), "")], top=180)
    if only("11"):
        make("11_move_texts.png", "Move texts anywhere",
             "Move texts freely: drag the mana numbers, the seconds and the regen, each on its own.",
             [(crop("images/214.webp", (820, 105, 1390, 355), 1.6), "")], top=170)
    if only("12"):
        make("12_just_regen.png", "Just the regen, if you like",
             "Switch off the bar, mana text and five-second rule; drag the regen wherever you want it.",
             [(hide_name(crop("images/213.webp", (380, 340, 780, 575), 2.0)), "")], top=160)
    if only("05"):
        BAR = (935, 326, 1510, 392)  # 0.8.2 big shots: bar, seconds, regen, mana text below
        make("05_mana_text.png", "Mana text like the game's Status Text",
             "Its own switch and text size: number, percentage or both, or switched off.",
             [(crop("images/205.webp", BAR, 0.95), "Number"),
              (crop("images/204.webp", BAR, 0.95), "Percentage"),
              (crop("images/197.webp", BAR, 0.95), "Both"),
              (crop("images/199.webp", BAR, 0.95), "Switched off")], top=150, stack=True)
    if only("05old"):
        # the same frames for 0.8.1, where "None" is still a choice in the list
        BAR = (935, 326, 1510, 392)
        make("05_mana_text_0.8.1.png", "Mana text like the game's Status Text",
             "Number, percentage, both or none, plus the regen next to the bar.",
             [(crop("images/205.webp", BAR, 0.95), "Number"),
              (crop("images/204.webp", BAR, 0.95), "Percentage"),
              (crop("images/197.webp", BAR, 0.95), "Both"),
              (crop("images/199.webp", BAR, 0.95), "None")], top=150, stack=True)
    if only("06"):
        make("06_settings.png", "Settings that explain themselves",
             "Every part has its own switch and text size. Hover any option for a short explanation.",
             [(crop("images/211.webp", (347, 72, 1227, 665), 0.88), "")], top=140)
    if only("09"):
        make("09_own_spells.png", "Your own mana spells too",
             "Eureka!, Evocation, Innervate, Mana Tide, Inner Focus, Life Tap: lit when ready and your mana is low.",
             [(crop("images/144.webp", (1150, 150, 1475, 240), 3.0), "")], top=200)
    if only("07n"):
        make("08_unlocked.png", "Easy to place",
             "Unlock the frame: everything that is switched on shows up, grey where you carry nothing.",
             [(crop("images/141.webp", (1150, 132, 1480, 240), 2.9), "")], top=190)
    if only("06n"):
        # 0.8.2 window: every part has its own switch, switched-off settings stay greyed out
        make("06_settings.png", "Settings that explain themselves",
             "Every part has its own switch and text size. Hover any option for a short explanation.",
             [(crop("images/187.webp", (520, 242, 960, 838), 0.8), "Display and look"),
              (crop("images/187.webp", (960, 242, 1400, 838), 0.8), "Visibility, drinking, own spells")], top=145)
