#!/usr/bin/env python3
"""Turn a coloured terminal capture (tmux capture-pane -e -p) into an SVG "screenshot".

    ansi2svg.py <capture.ansi >screen.svg [--title TEXT]

Handles the SGR codes tmux emits: bold, dim, italic, underline, reverse, 16/256/24-bit
colours. Every character sits on a fixed grid (textLength), so box drawing lines up
whatever monospace font the viewer has. No dependencies beyond Python 3.
"""
import re
import sys
from html import escape

FG, BG = "#cdd6f4", "#1e1e2e"          # default text and background (Catppuccin mocha)
# The 16 basic colours, Catppuccin mocha flavoured.
BASIC = ["#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
         "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8"]
CW, CH, FS, PAD, BAR = 8.4, 18, 14, 14, 30   # cell width/height, font size, padding, title bar


def c256(n):
    if n < 16:
        return BASIC[n]
    if n < 232:
        n -= 16
        lv = [0, 95, 135, 175, 215, 255]
        return "#%02x%02x%02x" % (lv[n // 36], lv[n // 6 % 6], lv[n % 6])
    g = 8 + (n - 232) * 10
    return "#%02x%02x%02x" % (g, g, g)


def parse(lines):
    """-> rows of cells: (char, fg, bg, bold, dim, italic, underline)"""
    rows = []
    st = dict(fg=None, bg=None, bold=False, dim=False, it=False, ul=False, rev=False)
    for line in lines:
        row = []
        for tok in re.split(r"(\x1b\[[0-9;:]*m)", line):
            if tok.startswith("\x1b["):
                p = [int(x) if x else 0 for x in tok[2:-1].replace(":", ";").split(";")] or [0]
                i = 0
                while i < len(p):
                    c = p[i]
                    if c == 0: st.update(fg=None, bg=None, bold=False, dim=False, it=False, ul=False, rev=False)
                    elif c == 1: st["bold"] = True
                    elif c == 2: st["dim"] = True
                    elif c == 3: st["it"] = True
                    elif c == 4: st["ul"] = True
                    elif c == 7: st["rev"] = True
                    elif c == 22: st["bold"] = st["dim"] = False
                    elif c == 23: st["it"] = False
                    elif c == 24: st["ul"] = False
                    elif c == 27: st["rev"] = False
                    elif 30 <= c <= 37: st["fg"] = BASIC[c - 30]
                    elif 90 <= c <= 97: st["fg"] = BASIC[c - 82]
                    elif 40 <= c <= 47: st["bg"] = BASIC[c - 40]
                    elif 100 <= c <= 107: st["bg"] = BASIC[c - 92]
                    elif c == 39: st["fg"] = None
                    elif c == 49: st["bg"] = None
                    elif c in (38, 48) and i + 1 < len(p):
                        key = "fg" if c == 38 else "bg"
                        if p[i + 1] == 2 and i + 4 < len(p):
                            st[key] = "#%02x%02x%02x" % tuple(p[i + 2:i + 5]); i += 4
                        elif p[i + 1] == 5 and i + 2 < len(p):
                            st[key] = c256(p[i + 2]); i += 2
                    i += 1
            elif tok:
                for ch in tok:
                    fg, bg = st["fg"] or FG, st["bg"] or BG
                    if st["rev"]:
                        fg, bg = bg, fg
                    row.append((ch, fg, bg, st["bold"], st["dim"], st["it"], st["ul"]))
        rows.append(row)
    return rows


def svg(rows, title):
    cols = max([len(r) for r in rows] + [20])
    w = PAD * 2 + cols * CW
    h = BAR + PAD * 2 + len(rows) * CH
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:.0f}" height="{h:.0f}" viewBox="0 0 {w:.0f} {h:.0f}">',
           '<style>text{font-family:"JetBrains Mono","DejaVu Sans Mono",Menlo,Consolas,monospace;'
           f'font-size:{FS}px;white-space:pre}}</style>',
           f'<rect width="100%" height="100%" rx="10" fill="{BG}" stroke="#45475a"/>',
           f'<circle cx="18" cy="15" r="6" fill="#f38ba8"/><circle cx="38" cy="15" r="6" fill="#f9e2af"/>'
           f'<circle cx="58" cy="15" r="6" fill="#a6e3a1"/>']
    if title:
        out.append(f'<text x="{w / 2:.0f}" y="20" fill="#7f849c" text-anchor="middle">{escape(title)}</text>')
    for y, row in enumerate(rows):
        top = BAR + PAD + y * CH
        # backgrounds, merged into runs
        x = 0
        while x < len(row):
            bg = row[x][2]
            e = x
            while e < len(row) and row[e][2] == bg:
                e += 1
            if bg != BG:
                out.append(f'<rect x="{PAD + x * CW:.1f}" y="{top:.1f}" width="{(e - x) * CW + 0.5:.1f}" height="{CH + 0.5}" fill="{bg}"/>')
            x = e
        # text, in runs of the same style
        x = 0
        while x < len(row):
            sty = row[x][1:2] + row[x][3:]
            e = x
            while e < len(row) and row[e][1:2] + row[e][3:] == sty:
                e += 1
            text = "".join(c[0] for c in row[x:e])
            if text.strip():
                fg, bold, dim, it, ul = sty
                attrs = f'fill="{fg}"' + (' font-weight="bold"' if bold else '') + (' opacity="0.6"' if dim else '') \
                    + (' font-style="italic"' if it else '') + (' text-decoration="underline"' if ul else '')
                out.append(f'<text x="{PAD + x * CW:.1f}" y="{top + CH * 0.75:.1f}" textLength="{(e - x) * CW:.1f}" '
                           f'lengthAdjust="spacingAndGlyphs" {attrs}>{escape(text)}</text>')
            x = e
    out.append("</svg>")
    return "\n".join(out)


if __name__ == "__main__":
    title = sys.argv[sys.argv.index("--title") + 1] if "--title" in sys.argv else ""
    lines = sys.stdin.read().split("\n")
    while lines and not lines[-1].strip():
        lines.pop()
    print(svg(parse(lines), title))
