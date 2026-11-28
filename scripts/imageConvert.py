import sys
import os.path
import argparse
from PIL import Image

#-----------------------------------------------------------------------------
# Convert a PNG to Apple II low-res data (asm source on stdout)
#
#   imageConvert.py input.png output.png
#       Picture (e.g. title screen): quantized to the 16 colors. The label
#       is the output file's base name.
#
#   imageConvert.py --level input.png output.png
#       Level: 128 x 48, every pixel must be an exact Apple II color or one
#       of the marker colors below. Writes the level data that game.asm
#       includes (levelBgColor, levelSpikeColor, the obj* tables and
#       background).
#
# output.png is the converted image (markers replaced) for checking.
#-----------------------------------------------------------------------------

APPLE2_PALETTE = [
    (0,   0,   0  ),    # 0 black
    (153, 3,   95 ),    # 1 red(ish)
    (66,  4,   225),    # 2 dark blue
    (202, 19,  254),    # 3 purple
    (0,   115, 16 ),    # 4 dark green
    (127, 127, 127),    # 5 gray 1
    (36,  151, 244),    # 6 medium blue
    (170, 162, 255),    # 7 light blue
    (79,  81,  1  ),    # 8 brown
    (240, 92,  0  ),    # 9 orange
    (128, 128, 128),    # A gray 2 (1 off gray 1 so levels can tell them apart)
    (255, 133, 225),    # B pink
    (18,  202, 7  ),    # C light green
    (206, 212, 19 ),    # D yellow
    (81,  245, 149),    # E aqua
    (255, 255, 255),    # F white
]

#-----------------------------------------------------------------------------
# Level marker colors (chosen to look distinct from the 16 Apple II colors)
#
#   MARK_BG     one pixel; the pixel to its left is the background color
#   MARK_SPIKE  one pixel; the pixel to its left is the spike color. The
#               marker itself becomes a spike (the spike color), so put it
#               at the end of a row of spikes
#   MARK_CHECK  checkpoint: draw a 1 pixel wide column in its color standing
#               on solid ground, and replace its bottom pixel with this
#               marker. The bottom pixel is where the player respawns.
#               (At least 2 pixels high, so the color can be seen above it)
#   MARK_LEDGE  crumbling ledge: draw a 1 pixel high row in its color and
#               replace the pixel at one end with this marker. The color is
#               taken from the pixel next to the marker, and the marker
#               becomes part of the ledge. At least 2 pixels wide. If both
#               sides of the marker are colored (e.g. a ledge from wall to
#               wall), the side that is 1 pixel high is the ledge.
#   MARK_PATH   moving platform path: fill the pixels the platform sweeps
#               that it doesn't start on. The shape sets the direction:
#                 horizontal: a single row on the platform's row, beside it
#                 vertical:   a rectangle exactly as wide as the platform,
#                             directly above and/or below it
#
# Player start: the level must have exactly one lone white (COLOR_WHITE)
# pixel, i.e. with no white among its 8 neighbors. It becomes background.
# White pixels touching other white pixels are ordinary level pixels
# (e.g. highlights). With nothing solid under the start the player starts
# falling (e.g. dropping in at the top of a level); it just can't be
# standing on a spike.
#
# A platform is a strip of one color, 1 pixel high, touching its path.
# Each connected blob of path pixels belongs to one platform (a platform
# in the middle of its path has a blob on each side), so different
# platforms' paths must not touch. If a blob could belong to more than one
# strip (e.g. a path that ends against a wall), the platform is the strip
# with path on both sides, or else the only strip that is 1 pixel high.
#
# All other markers and platforms become the background color in the data
# (platforms are drawn by initObjects).
# Platforms start moving away from the end they're at: right/down
# (objDir = 1), unless they start at the right/bottom end ($FF).
#-----------------------------------------------------------------------------

MARK_BG    = (128, 255, 0  )    # chartreuse
MARK_SPIKE = (0,   128, 128)    # teal
MARK_CHECK = (192, 0,   0  )    # red
MARK_PATH  = (0,   255, 255)    # cyan
MARK_LEDGE = (255, 0,   128)    # rose

MARKERS = {MARK_BG: 'bg', MARK_SPIKE: 'spike', MARK_CHECK: 'check', MARK_PATH: 'path',
           MARK_LEDGE: 'ledge'}

COLOR_WHITE = 0xF                # a lone white pixel marks the player start

LEVEL_W, LEVEL_H = 128, 48
OBJ_TABLE_SIZE = 16                     # entries in each obj* table (fixed)
LEVEL_DATA_SIZE = 0x100 + LEVEL_W * LEVEL_H // 2    # header page + background


class LevelError(Exception):
    pass


def palette_image(picture=False):
    pal = list(APPLE2_PALETTE)
    if picture:
        pal[0xA] = pal[0x5]     # pictures: grays quantize to gray 1 as before
    p_img = Image.new('P', (1, 1))
    flat = [c for rgb in pal for c in rgb]
    p_img.putpalette(flat * 16)
    return p_img


def convert_picture(infile, outfile):
    print(";", "--------------------------------------------------------------------")
    im = Image.open(infile)
    print(";", infile, im.format, im.size, im.mode)
    im = im.convert('RGB').quantize(palette=palette_image(picture=True), dither=0)
    im.save(outfile)
    print(";", outfile, im.format, im.size, im.mode)

    allData = []
    for y in range(0, im.size[1], 2):
        line = []
        for x in range(im.size[0]):
            # combine 2 pixel row into 1 byte row
            evenPixel = hex(im.getpixel((x, y)))
            oddPixel = hex(im.getpixel((x, y + 1)))
            byte = "$" + oddPixel[2:] + evenPixel[2:]
            line.append(byte)
        allData.append(line)

    name = os.path.basename(os.path.splitext(outfile)[0])
    print("{}:".format(name))
    for line in allData:
        print(".byte ", end="")
        print(*line, sep=",")


#-----------------------------------------------------------------------------
# Level conversion
#-----------------------------------------------------------------------------

def read_level(infile):
    """Return pix[y][x]: 0..15 for Apple colors, or a marker name"""
    im = Image.open(infile).convert('RGB')
    if im.size != (LEVEL_W, LEVEL_H):
        raise LevelError(f"level must be {LEVEL_W}x{LEVEL_H}, got {im.size[0]}x{im.size[1]}")
    lookup = {rgb: i for i, rgb in enumerate(APPLE2_PALETTE)}
    lookup.update(MARKERS)
    pix = []
    for y in range(LEVEL_H):
        row = []
        for x in range(LEVEL_W):
            rgb = im.getpixel((x, y))
            if rgb not in lookup:
                raise LevelError(f"pixel ({x},{y}) color {rgb} is not an Apple II or marker color")
            row.append(lookup[rgb])
        pix.append(row)
    return pix


def find_marker(pix, marker, name=None):
    """Position of the single `marker` pixel"""
    found = [(x, y) for y in range(LEVEL_H) for x in range(LEVEL_W) if pix[y][x] == marker]
    if len(found) != 1:
        raise LevelError(f"need exactly one {name or marker} marker pixel, found {len(found)}: {found}")
    return found[0]


def find_start(pix):
    """Position of the single lone white pixel (no white among its 8 neighbors)"""
    def white(x, y):
        return 0 <= x < LEVEL_W and 0 <= y < LEVEL_H and pix[y][x] == COLOR_WHITE
    lone = [(x, y) for y in range(LEVEL_H) for x in range(LEVEL_W)
            if white(x, y) and not any(white(x + dx, y + dy)
                                       for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy)]
    if len(lone) != 1:
        raise LevelError(f"need exactly one lone white pixel (player start), found "
                         f"{len(lone)}: {lone}")
    return lone[0]


def find_color_marker(pix, marker):
    """Position of the single `marker` pixel and the color of the pixel left of it"""
    x, y = find_marker(pix, marker)
    if x == 0 or not isinstance(pix[y][x - 1], int):
        raise LevelError(f"{marker} marker at ({x},{y}) needs an Apple II color to its left")
    return (x, y), pix[y][x - 1]


def path_blobs(pix):
    """4-connected groups of path pixels, each a set of (x, y)"""
    seen = set()
    blobs = []
    for y in range(LEVEL_H):
        for x in range(LEVEL_W):
            if pix[y][x] != 'path' or (x, y) in seen:
                continue
            blob = set()
            todo = [(x, y)]
            seen.add((x, y))
            while todo:
                cx, cy = todo.pop()
                blob.add((cx, cy))
                for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
                    if (0 <= nx < LEVEL_W and 0 <= ny < LEVEL_H and (nx, ny) not in seen
                            and pix[ny][nx] == 'path'):
                        seen.add((nx, ny))
                        todo.append((nx, ny))
            blobs.append(blob)
    return blobs


def find_platforms(pix, bg):
    """
    Match each path blob to the platform strip it belongs to.
    Returns a list of object dicts (OBJ_HPLAT / OBJ_VPLAT).
    """

    def is_color(x, y):
        return 0 <= x < LEVEL_W and 0 <= y < LEVEL_H and isinstance(pix[y][x], int) and pix[y][x] != bg

    def is_path(x, y):
        return 0 <= x < LEVEL_W and 0 <= y < LEVEL_H and pix[y][x] == 'path'

    def strip_at(x, y):
        """The run of one color along row y through (x, y): (y, x0, x1, color)"""
        color = pix[y][x]
        x0, x1 = x, x
        while x0 > 0 and pix[y][x0 - 1] == color:
            x0 -= 1
        while x1 < LEVEL_W - 1 and pix[y][x1 + 1] == color:
            x1 += 1
        return (y, x0, x1, color)

    def thick_strip(strip):
        """True if any pixel of the strip has its color directly above or below"""
        y, x0, x1, color = strip
        return any(0 <= cy < LEVEL_H and pix[cy][cx] == color
                   for cx in range(x0, x1 + 1) for cy in (y - 1, y + 1))

    platforms = {}  # (orient, strip) -> [pathMin, pathMax]

    for blob in path_blobs(pix):
        xs = [p[0] for p in blob]
        ys = [p[1] for p in blob]
        bx0, bx1, by0, by1 = min(xs), max(xs), min(ys), max(ys)
        where = f"path at ({bx0},{by0})..({bx1},{by1})"
        if len(blob) != (bx1 - bx0 + 1) * (by1 - by0 + 1):
            raise LevelError(f"{where} must be a single row or a rectangle")

        # (orient, strip, enclosed): strips this blob could belong to
        cands = []
        if by0 == by1:
            # Horizontal: a strip at either end of the row
            for x, step in ((bx0 - 1, -1), (bx1 + 1, 1)):
                if is_color(x, by0):
                    strip = strip_at(x, by0)
                    far = strip[1] - 1 if step < 0 else strip[2] + 1
                    cands.append(('H', strip, is_path(far, by0)))
        # Vertical: a strip exactly as wide as the blob, above or below
        for y, step in ((by0 - 1, -1), (by1 + 1, 1)):
            if is_color(bx0, y):
                strip = strip_at(bx0, y)
                if strip[1] == bx0 and strip[2] == bx1:
                    enclosed = all(is_path(x, y + step) for x in range(bx0, bx1 + 1))
                    cands.append(('V', strip, enclosed))

        if not cands:
            raise LevelError(f"{where} has no platform touching it (horizontal paths go beside "
                             f"the platform, vertical paths above/below it at the same width)")
        if len(cands) > 1:
            # Prefer a strip with path on both sides, else the only strip
            # that is 1 pixel high (the others are walls, ground, ...)
            enclosed = [c for c in cands if c[2]]
            thin = [c for c in cands if not thick_strip(c[1])]
            if len(enclosed) == 1:
                cands = enclosed
            elif len(thin) == 1:
                cands = thin
            else:
                strips = ", ".join(f"({s[1]}..{s[2]},{s[0]})={s[3]}" for _, s, _ in cands)
                raise LevelError(f"{where} touches more than one strip that could be its "
                                 f"platform: {strips} (put path on both sides of the "
                                 f"platform, or leave a background gap)")
        orient, strip, _ = cands[0]

        lo, hi = (bx0, bx1) if orient == 'H' else (by0, by1)
        lo = min(lo, strip[1] if orient == 'H' else strip[0])
        hi = max(hi, strip[2] if orient == 'H' else strip[0])
        other = ('V' if orient == 'H' else 'H', strip)
        if other in platforms:
            raise LevelError(f"platform at ({strip[1]},{strip[0]}) has both horizontal and "
                             f"vertical path touching it")
        span = platforms.setdefault((orient, strip), [lo, hi])
        span[0] = min(span[0], lo)
        span[1] = max(span[1], hi)

    objects = []
    for (orient, (y, x0, x1, color)), (lo, hi) in platforms.items():
        width = x1 - x0 + 1
        if orient == 'H':
            objMax = hi - width + 1
            objects.append(dict(type='OBJ_HPLAT', x=x0, y=y, width=width, color=color,
                                min=lo, max=objMax, dir=0xFF if x0 == objMax else 1))
        else:
            objects.append(dict(type='OBJ_VPLAT', x=x0, y=y, width=width, color=color,
                                min=lo, max=hi, dir=0xFF if y == hi else 1))
    return objects


def convert_level(infile, outfile):
    pix = read_level(infile)

    (bgx, bgy), bg = find_color_marker(pix, 'bg')
    (spx, spy), spike = find_color_marker(pix, 'spike')
    if spike == bg:
        raise LevelError("spike color is the same as the background color")
    startX, startY = find_start(pix)
    pix[bgy][bgx] = bg
    pix[spy][spx] = spike       # the marker is a spike too
    pix[startY][startX] = bg
    if startY + 1 < LEVEL_H and pix[startY + 1][startX] == spike:
        raise LevelError(f"player start ({startX},{startY}) is standing on a spike "
                         f"(the player would die on every respawn)")

    objects = []    # dicts with the obj* fields

    # Checkpoints (cleared to background before looking for paths)
    for x, y in [(x, y) for y in range(LEVEL_H) for x in range(LEVEL_W) if pix[y][x] == 'check']:
        color = pix[y - 1][x] if y > 0 else None
        if not isinstance(color, int) or color == bg:
            raise LevelError(f"checkpoint at ({x},{y}) needs its column color above the marker")
        below = pix[y + 1][x] if y + 1 < LEVEL_H else bg
        if below in (bg, spike) or not isinstance(below, int):
            raise LevelError(f"checkpoint at ({x},{y}) must stand on solid ground "
                             f"(not background, a spike or a marker)")
        top = y - 1
        while top > 0 and pix[top - 1][x] == color:
            top -= 1
        for row in range(top, y + 1):
            pix[row][x] = bg
        objects.append(dict(type='OBJ_CHECKPOINT', x=x, y=y, width=1, color=color,
                            min=top, max=y, dir=0))

    # Crumbling ledges (cleared to background before looking for paths)
    for x, y in [(x, y) for y in range(LEVEL_H) for x in range(LEVEL_W) if pix[y][x] == 'ledge']:
        def color_at(cx):
            if 0 <= cx < LEVEL_W and isinstance(pix[y][cx], int) and pix[y][cx] != bg:
                return pix[y][cx]
            return None
        sides = [step for step in (-1, 1) if color_at(x + step) is not None]
        if len(sides) == 2:
            # Touching something on both ends (e.g. wall to wall): a ledge is
            # 1 pixel high, so rule out a side whose pixel has the same
            # color directly above or below it
            def thick(cx):
                c = pix[y][cx]
                return any(0 <= cy < LEVEL_H and pix[cy][cx] == c for cy in (y - 1, y + 1))
            sides = [step for step in sides if not thick(x + step)]
        if len(sides) != 1:
            neighbors = ", ".join(f"({x + s},{y})={pix[y][x + s]}" for s in (-1, 1)
                                  if 0 <= x + s < LEVEL_W)
            raise LevelError(f"ledge marker at ({x},{y}): can't tell which side is the ledge "
                             f"(neighbors {neighbors}). The ledge color must be on one side, "
                             f"and if both sides are colored the other side must be thicker "
                             f"than 1 pixel")
        step = sides[0]
        color = color_at(x + step)
        end = x + step
        while color_at(end + step) == color:
            end += step
        x0, x1 = min(x, end), max(x, end)
        for cx in range(x0, x1 + 1):
            pix[y][cx] = bg
        objects.append(dict(type='OBJ_LEDGE', x=x0, y=y, width=x1 - x0 + 1, color=color,
                            min=0, max=0, dir=0))

    # Moving platforms
    objects += find_platforms(pix, bg)

    objects.sort(key=lambda o: (o['x'], o['y']))

    # Platforms and paths become background in the data
    for y in range(LEVEL_H):
        for x in range(LEVEL_W):
            if pix[y][x] == 'path':
                pix[y][x] = bg
    for o in objects:
        for x in range(o['x'], o['x'] + o['width']):
            pix[o['y']][x] = bg

    # Converted image for checking
    out = Image.new('P', (LEVEL_W, LEVEL_H))
    out.putpalette(palette_image().getpalette())
    out.putdata([pix[y][x] for y in range(LEVEL_H) for x in range(LEVEL_W)])
    out.save(outfile)

    write_level_asm(infile, bg, spike, startX, startY, objects, pix)


def write_level_asm(infile, bg, spike, startX, startY, objects, pix):
    count = len(objects)
    if count > OBJ_TABLE_SIZE:
        raise LevelError(f"{count} objects, the obj* tables only hold {OBJ_TABLE_SIZE}")
    print("; " + "-" * 76)
    print(f"; Level data generated by imageConvert.py --level from {os.path.basename(infile)}")
    print("; Don't edit, edit the PNG")
    print(";")
    print(f"; Every level has the same layout and size (${LEVEL_DATA_SIZE:X} bytes, page")
    print("; aligned), so a stored level can be copied over the active one.")
    print("; " + "-" * 76)
    print()
    print(".align  256")
    print("levelData:")
    print()
    print(f"levelBgColor:   .byte   ${bg:X}")
    print(f"levelSpikeColor:.byte   ${spike:X}")
    print(f"levelStartX:    .byte   {startX}")
    print(f"levelStartY:    .byte   {startY}")
    print()
    print(f"objCount:       .byte   {count}")
    print()
    print(f"; Each obj* table is padded to {OBJ_TABLE_SIZE} entries")

    def table(label, values):
        if values:
            cols = "".join(f"{v + ',':<16}" for v in values[:-1]) + values[-1]
            print(f"{label + ':':<16}.byte   {cols}")
        else:
            print(f"{label + ':'}")
        if count < OBJ_TABLE_SIZE:
            print(f"{'':<16}.res    {OBJ_TABLE_SIZE - count}")

    table("objType", [o['type'] for o in objects])
    table("objX", [str(o['x']) for o in objects])
    table("objY", [str(o['y']) for o in objects])
    table("objWidth", [str(o['width']) for o in objects])
    table("objColor", [f"${o['color']:X}" for o in objects])
    table("objMin", [str(o['min']) for o in objects])
    table("objMax", [str(o['max']) for o in objects])
    table("objDir", [f"${o['dir']:02X}" if o['dir'] == 0xFF else str(o['dir']) for o in objects])
    print()

    print(".align  256                     ; setMapPtr needs background page aligned")
    print("; 128 x 48 pixels, 24 text rows of $80 bytes")
    print("; Each byte = top pixel (low nibble) + bottom pixel (high nibble)")
    print("; Columns 127 and 0 line up so the level wraps")
    print("background:")
    for r in range(LEVEL_H // 2):
        print(f"    ; text row {r} (pixel rows {2 * r}, {2 * r + 1})")
        row = [pix[2 * r][x] | (pix[2 * r + 1][x] << 4) for x in range(LEVEL_W)]
        for i in range(0, LEVEL_W, 16):
            print("    .byte   " + ','.join(f"${b:02X}" for b in row[i:i + 16]))
    print()
    print("levelDataEnd:")
    print(f".assert levelDataEnd - levelData = ${LEVEL_DATA_SIZE:X}, error, \"level data size changed\"")


def main():
    parser = argparse.ArgumentParser(description="Convert a PNG to Apple II low-res asm data")
    parser.add_argument("--level", action="store_true", help="convert a 128x48 level with markers")
    parser.add_argument("infile")
    parser.add_argument("outfile", help="converted PNG (for checking)")
    args = parser.parse_args()

    if args.level:
        try:
            convert_level(args.infile, args.outfile)
        except LevelError as e:
            sys.exit(f"{args.infile}: {e}")
    else:
        convert_picture(args.infile, args.outfile)


main()
