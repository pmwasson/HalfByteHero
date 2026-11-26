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
#   MARK_SPIKE  one pixel; the pixel to its left is the spike color
#   MARK_HPATH  horizontal platform path: on the platform's row, fill the
#               columns the platform sweeps that it doesn't start on
#   MARK_VPATH  vertical platform path: fill the rows the platform sweeps
#               (full platform width) that it doesn't start on
#
# A platform is a strip of one color, 1 pixel high, touching its path.
# It must either have path pixels on both sides, or be the only
# non-background thing touching its path (so it can be told apart from
# solid ground at the end of a path).
#
# All markers and platforms become the background color in the data
# (platforms are drawn by initObjects).
# Platforms start moving away from the end they're at: right/down
# (objDir = 1), unless they start at the right/bottom end ($FF).
#-----------------------------------------------------------------------------

MARK_BG    = (128, 255, 0  )    # chartreuse
MARK_SPIKE = (0,   128, 128)    # teal
MARK_HPATH = (0,   255, 255)    # cyan
MARK_VPATH = (255, 0,   128)    # rose

MARKERS = {MARK_BG: 'bg', MARK_SPIKE: 'spike', MARK_HPATH: 'hpath', MARK_VPATH: 'vpath'}

LEVEL_W, LEVEL_H = 128, 48


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


def find_color_marker(pix, marker):
    """Color of the pixel left of the single `marker` pixel; clears the marker"""
    found = [(x, y) for y in range(LEVEL_H) for x in range(LEVEL_W) if pix[y][x] == marker]
    if len(found) != 1:
        raise LevelError(f"need exactly one {marker} marker pixel, found {len(found)}: {found}")
    x, y = found[0]
    if x == 0 or not isinstance(pix[y][x - 1], int):
        raise LevelError(f"{marker} marker at ({x},{y}) needs an Apple II color to its left")
    return found[0], pix[y][x - 1]


def runs_of(line):
    """Split a line into runs of equal values: [value, start, end] (end inclusive)"""
    runs = []
    for i, v in enumerate(line):
        if runs and runs[-1][0] == v:
            runs[-1][2] = i
        else:
            runs.append([v, i, i])
    return runs


def find_paths(line, marker, bg, where):
    """
    Find platforms on one line (a row for hpath, a column for vpath).
    Returns (platStart, platEnd, color, pathStart, pathEnd) tuples.
    """
    runs = runs_of(line)
    n = len(runs)

    def is_marker(i):
        return 0 <= i < n and runs[i][0] == marker

    def is_candidate(i):
        return 0 <= i < n and isinstance(runs[i][0], int) and runs[i][0] != bg

    found = []
    used = set()

    # Platforms with path on both sides
    for i in range(n):
        if is_candidate(i) and is_marker(i - 1) and is_marker(i + 1):
            if i - 1 in used:
                raise LevelError(f"{where}: two platforms share a {marker} path at {runs[i - 1][1]}")
            used.update((i - 1, i + 1))
            found.append((runs[i][1], runs[i][2], runs[i][0], runs[i - 1][1], runs[i + 1][2]))

    # Platforms at one end of their path
    for i in range(n):
        if not is_marker(i) or i in used:
            continue
        cands = [j for j in (i - 1, i + 1) if is_candidate(j)]
        if not cands:
            raise LevelError(f"{where}: {marker} path at {runs[i][1]}..{runs[i][2]} has no platform")
        if len(cands) > 1:
            raise LevelError(f"{where}: {marker} path at {runs[i][1]}..{runs[i][2]} touches two "
                             f"colors, can't tell which is the platform (start the platform "
                             f"inside the path, or leave a background gap at the far end)")
        j = cands[0]
        if is_marker(j + (j - i)):
            raise LevelError(f"{where}: platform at {runs[j][1]} has a path on both sides already")
        used.add(i)
        found.append((runs[j][1], runs[j][2], runs[j][0],
                      min(runs[i][1], runs[j][1]), max(runs[i][2], runs[j][2])))
    return found


def convert_level(infile, outfile):
    pix = read_level(infile)

    (bgx, bgy), bg = find_color_marker(pix, 'bg')
    (spx, spy), spike = find_color_marker(pix, 'spike')
    if spike == bg:
        raise LevelError("spike color is the same as the background color")
    pix[bgy][bgx] = bg
    pix[spy][spx] = bg

    objects = []    # dicts with the obj* fields

    # Horizontal platforms, row by row
    for y in range(LEVEL_H):
        for x0, x1, color, p0, p1 in find_paths(pix[y], 'hpath', bg, f"row {y}"):
            width = x1 - x0 + 1
            objMax = p1 - width + 1
            objects.append(dict(type='OBJ_HPLAT', x=x0, y=y, width=width, color=color,
                                min=p0, max=objMax, dir=0xFF if x0 == objMax else 1))

    # Vertical platforms, column by column, then merge matching neighbors
    cols = []
    for x in range(LEVEL_W):
        column = [pix[y][x] for y in range(LEVEL_H)]
        for y0, y1, color, p0, p1 in find_paths(column, 'vpath', bg, f"column {x}"):
            if y0 != y1:
                raise LevelError(f"column {x}: vertical platform at rows {y0}..{y1} is more than 1 pixel high")
            cols.append((x, y0, color, p0, p1))
    cols.sort(key=lambda c: (c[1:], c[0]))
    for x, y, color, p0, p1 in cols:
        last = objects[-1] if objects else None
        if (last and last['type'] == 'OBJ_VPLAT' and last['x'] + last['width'] == x
                and (last['y'], last['color'], last['min'], last['max']) == (y, color, p0, p1)):
            last['width'] += 1
        else:
            objects.append(dict(type='OBJ_VPLAT', x=x, y=y, width=1, color=color,
                                min=p0, max=p1, dir=0xFF if y == p1 else 1))

    objects.sort(key=lambda o: (o['x'], o['y']))

    # Platforms and paths become background in the data
    for y in range(LEVEL_H):
        for x in range(LEVEL_W):
            if pix[y][x] in ('hpath', 'vpath'):
                pix[y][x] = bg
    for o in objects:
        for x in range(o['x'], o['x'] + o['width']):
            pix[o['y']][x] = bg

    # Converted image for checking
    out = Image.new('P', (LEVEL_W, LEVEL_H))
    out.putpalette(palette_image().getpalette())
    out.putdata([pix[y][x] for y in range(LEVEL_H) for x in range(LEVEL_W)])
    out.save(outfile)

    write_level_asm(infile, bg, spike, objects, pix)


def write_level_asm(infile, bg, spike, objects, pix):
    count = len(objects)
    print("; " + "-" * 76)
    print(f"; Level data generated by imageConvert.py --level from {os.path.basename(infile)}")
    print("; Don't edit, edit the PNG")
    print("; " + "-" * 76)
    print()
    print(f"levelBgColor:   .byte   ${bg:X}")
    print(f"levelSpikeColor:.byte   ${spike:X}")
    print()
    print(f"objCount:       .byte   {count}")
    print(f".assert {count} <= OBJ_MAX, error, \"too many objects for OBJ_MAX\"")
    print()

    def table(label, values):
        if values:
            cols = "".join(f"{v + ',':<12}" for v in values[:-1]) + values[-1]
            print(f"{label + ':':<16}.byte   {cols}")
        else:
            print(f"{label + ':'}")
        print(f"{'':<16}.res    OBJ_MAX-{count}")

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
