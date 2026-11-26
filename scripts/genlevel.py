import sys

W, H = 128, 48
GREEN, BROWN, ORANGE, YELLOW, PURPLE, PINK, SPIKE = 0xC, 0x8, 0x9, 0xD, 0x3, 0xB, 0x1
MAGENTA = PINK  # was magenta, now reserved for spikes

pix = [[0] * W for _ in range(H)]

def rect(x0, x1, y0, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            pix[y][x] = c

def ground(x0, x1, top=44):
    rect(x0, x1, top, top, GREEN)
    rect(x0, x1, top + 1, H - 1, BROWN)

# --- Columns 0..39: from the image (rows +8) ---
ground(0, 9)            # gap 10-12 (3)
ground(13, 20)          # gap 21-24 (4)
ground(25, 31)          # gap 32-36 (5)
ground(37, 47)
rect(5, 7, 40, 40, ORANGE)
rect(9, 12, 35, 35, ORANGE)
rect(15, 18, 31, 31, ORANGE)
rect(15, 17, 39, 39, ORANGE)
rect(22, 25, 27, 27, ORANGE)
rect(29, 32, 23, 23, YELLOW)
rect(26, 28, 40, 40, PURPLE)
rect(30, 31, 38, 38, MAGENTA)

# --- Columns 40..79: obstacles ---
rect(42, 43, 43, 43, ORANGE)        # 1 high step
rect(46, 47, 42, 43, ORANGE)        # 2 high step
                                    # gap 48-49 (2)
ground(50, 63)
rect(55, 56, 40, 43, ORANGE)        # 4 high wall
rect(59, 63, 40, 40, PURPLE)        # low ceiling (head bump)
                                    # gap 64-73 (10): ferry platform only
ground(74, 79)

# --- Columns 80..127: ledges and a second staircase ---
ground(80, 87, top=40)              # raised ledge (4 up)
                                    # gap 88-91 (4) down to ground
ground(92, 117)
rect(101, 104, 39, 39, ORANGE)
rect(107, 110, 34, 34, ORANGE)
rect(113, 116, 29, 29, YELLOW)
                                    # gap 118-120 (3)
ground(121, 127)                    # lines up with column 0

# --- Spikes ---
rect(52, 53, 43, 43, SPIKE)         # on the ground before the 4 high wall
rect(96, 98, 43, 43, SPIKE)         # under the second staircase

if "--map" in sys.argv:
    chars = {0: '.', GREEN: 'G', BROWN: 'b', ORANGE: 'o', YELLOW: 'Y', PURPLE: 'p', PINK: 'k', SPIKE: 'X'}
    for y in range(H):
        print(f"{y:2} " + ''.join(chars[c] for c in pix[y]))
    sys.exit()

print("; Example level: 128 x 48 pixels, 24 text rows of $80 bytes")
print("; Each byte = top pixel (low nibble) + bottom pixel (high nibble)")
print("; Columns 127 and 0 line up so the level wraps")
print("background:")
for r in range(24):
    print(f"    ; text row {r} (pixel rows {2*r}, {2*r+1})")
    row = [pix[2*r][x] | (pix[2*r+1][x] << 4) for x in range(W)]
    for i in range(0, W, 16):
        print("    .byte   " + ','.join(f"${b:02X}" for b in row[i:i+16]))
