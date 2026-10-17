#!/usr/bin/env python3
"""Builds the client-facing notes document from ROUND2_REPORT.md.

Output: ~/Documents/projects/go_donation/Notes_with_fixes.html and .pdf
Same order as the client's notes (points 1..91). Each point: the client's own
wording, its status, how it was fixed, and the screenshots.

Usage: python3 tools/build_notes_pdf.py
Needs: Pillow, Google Chrome (headless print-to-pdf). No other dependencies.
"""
import base64, html, io, os, re, subprocess, sys
from PIL import Image

ROOT = os.path.expanduser('~/Documents/projects/go_donation')
SRC = os.path.join(ROOT, 'ROUND2_REPORT.md')
OUT_HTML = os.path.join(ROOT, 'Notes_with_fixes.html')
OUT_PDF = os.path.join(ROOT, 'Notes_with_fixes.pdf')
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'

STATUS = [  # (prefix, label, colour)
    ('🟡', 'تم جزئياً', '#c27c0e'),
    ('✅', 'تم الإصلاح', '#1f7a4d'),
    ('☑️', 'موجود مسبقاً', '#1f7a4d'),
    ('➕', 'إضافة — خارج النطاق الأصلي', '#6b4fa0'),
    ('⏳', 'قيد الانتظار', '#b7791f'),
    ('❌', 'لم يتم', '#b83232'),
    ('🚫', 'مرفوض', '#b83232'),
    ('ℹ️', 'معلومة', '#4a6a8a'),
    ('↪', 'ضمن بند آخر', '#4a6a8a'),
    ('⬜', 'لم يبدأ', '#777777'),
]

_img_cache = {}


def img_tag(path, alt=''):
    full = path if os.path.isabs(path) else os.path.join(ROOT, path)
    if not os.path.exists(full):
        return f'<div class="missing">[missing image: {html.escape(path)}]</div>'
    if full not in _img_cache:
        im = Image.open(full).convert('RGB')
        wide = im.width > im.height
        w = 1800 if wide else 1100
        if im.width > w:
            im = im.resize((w, int(im.height * w / im.width)), Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, 'JPEG', quality=90, optimize=True)
        _img_cache[full] = (base64.b64encode(buf.getvalue()).decode(), 'wide' if wide else 'tall')
    data, kind = _img_cache[full]
    return f'<img class="{kind}" src="data:image/jpeg;base64,{data}" alt="{html.escape(alt)}">'


def inline(t):
    t = html.escape(t, quote=False)
    t = re.sub(r'!\[[^\]]*\]\(([^)]+)\)', lambda m: img_tag(m.group(1)), t)
    t = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', t)
    t = re.sub(r'`([^`]+)`', r'<code>\1</code>', t)
    t = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'\1', t)
    t = t.replace('\\*', '*')
    return t


def body_to_html(lines):
    out, i = [], 0
    while i < len(lines):
        ln = lines[i]
        if not ln.strip():
            i += 1
            continue
        if ln.lstrip().startswith('|'):
            rows = []
            while i < len(lines) and lines[i].lstrip().startswith('|'):
                rows.append([c.strip() for c in lines[i].strip().strip('|').split('|')])
                i += 1
            rows = [r for r in rows if not all(re.fullmatch(r':?-{2,}:?', c) for c in r)]
            if any('![' in c for r in rows for c in r):
                labels = rows[0] if not any('![' in c for c in rows[0]) else []
                data_rows = rows[1:] if labels else rows
                out.append('<div class="gal">')
                for r in data_rows:
                    for ci, c in enumerate(r):
                        if not c.strip():
                            continue
                        cap = f'<figcaption>{inline(labels[ci])}</figcaption>' if ci < len(labels) and labels[ci].strip() else ''
                        out.append(f'<figure>{inline(c)}{cap}</figure>')
                out.append('</div>')
                continue
            out.append('<table class="shots">')
            for ri, r in enumerate(rows):
                tag = 'th' if ri == 0 and not any('![' in c for c in r) else 'td'
                out.append('<tr>' + ''.join(f'<{tag}>{inline(c)}</{tag}>' for c in r) + '</tr>')
            out.append('</table>')
            continue
        if re.match(r'\s*[-*] ', ln):
            out.append('<ul>')
            while i < len(lines) and re.match(r'\s*[-*] ', lines[i]):
                out.append('<li dir="auto">' + inline(re.sub(r'^\s*[-*] ', '', lines[i])) + '</li>')
                i += 1
            out.append('</ul>')
            continue
        if re.fullmatch(r'(\s*!\[[^\]]*\]\([^)]+\)\s*)+', ln):
            imgs = []
            while i < len(lines) and re.fullmatch(r'(\s*!\[[^\]]*\]\([^)]+\)\s*)+', lines[i]):
                imgs.append(lines[i])
                i += 1
            out.append('<div class="gal">' + ''.join(f'<figure>{inline(x)}</figure>' for x in imgs) + '</div>')
            continue
        para = [ln]
        i += 1
        while i < len(lines) and lines[i].strip() and not lines[i].lstrip().startswith('|') \
                and not re.match(r'\s*[-*] ', lines[i]):
            para.append(lines[i])
            i += 1
        out.append('<p dir="auto">' + inline(' '.join(para)) + '</p>')
    return '\n'.join(out)


def parse(src):
    text = open(src, encoding='utf-8').read()
    parts = re.split(r'^## (\d+)\. ', text, flags=re.M)
    points = []
    for k in range(1, len(parts), 2):
        num = int(parts[k])
        block = parts[k + 1].split('\n')
        title = re.sub(r'\*\*(.+?)\*\*', r'\1', block[0]).strip()
        rest = block[1:]
        status_line = next((l for l in rest if l.startswith('**Status:**')), '')
        status_txt = status_line.replace('**Status:**', '').strip()
        rest = [l for l in rest if not l.startswith('**Status:**')]
        points.append((num, title, status_txt, rest))
    return points


def chip(status_txt):
    for pre, label, col in STATUS:
        if status_txt.startswith(pre):
            return pre, label, col
    return '⬜', 'لم يبدأ', '#777777'


CSS = """
@page { size: A4; margin: 14mm 12mm; }
* { box-sizing: border-box; }
body { font-family: 'Noto Sans Arabic','Geeza Pro','Arial',sans-serif; direction: ltr; color:#1b1f1d;
       font-size: 11.5pt; line-height: 1.65; margin:0; }
h1 { font-size: 22pt; margin: 0 0 4px; color:#2f5d4a; }
.sub { color:#555; margin-bottom: 14px; }
.sumtable { width:100%; border-collapse: collapse; font-size: 9.5pt; margin: 10px 0 22px; }
.sumtable td { border:1px solid #ddd; padding:3px 6px; vertical-align: top; }
.sumtable td.n { width: 32px; text-align:center; font-weight:700; }
.sumtable td.s { width: 120px; font-weight:700; white-space:nowrap; }
.point { page-break-inside: auto; border-top: 2px solid #2f5d4a; padding-top: 8px; margin-top: 18px; }
.point h2 { font-size: 13pt; margin: 0 0 6px; }
.num { display:inline-block; background:#2f5d4a; color:#fff; border-radius: 6px; padding: 0 8px; margin-inline-start: 8px; }
.chip { display:inline-block; color:#fff; border-radius: 99px; padding: 1px 12px; font-size: 10pt; font-weight:700; }
.orig { background:#f5f2ea; border-inline-start: 4px solid #cfc8b9; padding: 6px 10px; margin: 8px 0; font-size: 10.5pt; }
.note { color:#444; font-size: 10pt; margin: 6px 0; }
table.shots { width:100%; border-collapse: collapse; margin: 8px 0; page-break-inside: avoid; }
table.shots td, table.shots th { border:1px solid #e3ded2; padding: 4px; text-align:center; vertical-align: top; }
table.shots th { background:#f0ece1; font-size: 10pt; }
img { max-width: 100%; height:auto; border-radius: 6px; border:1px solid #ddd; margin: 2px; }
table.shots img { width: 100%; max-width: 300px; }
p img { max-width: 48%; vertical-align: top; }
code { background:#eee; padding: 0 4px; border-radius: 4px; font-size: 9.5pt; direction:ltr; unicode-bidi: embed; }
ul { margin: 4px 0; padding-inline-start: 22px; }
table.shots td { text-align:center; }
.gal { display:flex; flex-wrap:wrap; gap:10px; margin:10px 0; justify-content:flex-start; }
.gal figure { margin:0; flex:0 0 auto; page-break-inside:avoid; break-inside:avoid; }
.gal figure:has(img.wide) { flex:1 1 100%; }
.gal img.wide { width:100%; max-width:100%; }
.gal img.tall { width:auto; max-width:100%; max-height:150mm; }
.gal figcaption { font-size:9.5pt; color:#555; text-align:center; margin-top:3px; }
"""


def main():
    pts = parse(SRC)
    orig = {}
    notes_md = open(os.path.join(ROOT, 'CLIENT_NOTES_ROUND2.md'), encoding='utf-8').read()
    for m in re.finditer(r'^\| (\d+) \| (.+?) \| .*? \|$', notes_md, flags=re.M):
        t = re.sub(r'^\[[FAQ]\]\s*', '', m.group(2))
        pass
    h = [f'<!doctype html><html lang="en" dir="ltr"><head><meta charset="utf-8"><title>الملاحظات والحلول</title><style>{CSS}</style></head><body>']
    h.append('<h1>تطبيق توازن — الملاحظات والحلول</h1>')
    h.append('<div class="sub">كل بند بترتيب ملف الملاحظات: نص الملاحظة، حالتها، كيف تم حلّها، ولقطات الشاشة.</div>')
    counts = {}
    h.append('<table class="sumtable">')
    for num, title, st, _ in pts:
        pre, label, col = chip(st)
        counts[label] = counts.get(label, 0) + 1
        short = (orig.get(num) or title)
        short = short if len(short) < 110 else short[:107] + '…'
        h.append(f'<tr><td class="n">{num}</td><td class="s" dir="rtl" style="color:{col}">{pre} {label}</td><td dir="auto">{html.escape(short)}</td></tr>')
    h.append('</table>')
    h.append('<p class="note">' + ' · '.join(f'{k}: {v}' for k, v in counts.items()) + '</p>')
    for num, title, st, rest in pts:
        pre, label, col = chip(st)
        h.append('<div class="point">')
        h.append(f'<h2 dir="auto"><span class="num">{num}</span>{html.escape(orig.get(num) or title)}</h2>')
        h.append(f'<span class="chip" style="background:{col}">{pre} {label}</span>')
        extra = re.sub(r'^[^—:]*[—:]\s*', '', st) if ('—' in st or ':' in st) else ''
        if extra and not st.startswith('✅ Fixed') and extra != st:
            h.append(f'<div class="note" dir="auto">{inline(extra)}</div>')
        h.append(body_to_html(rest))
        h.append('</div>')
    h.append('</body></html>')
    open(OUT_HTML, 'w', encoding='utf-8').write('\n'.join(h))
    subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--no-pdf-header-footer',
                    f'--print-to-pdf={OUT_PDF}', f'file://{OUT_HTML}'],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=300)
    print('points:', len(pts), 'pdf:', OUT_PDF, round(os.path.getsize(OUT_PDF) / 1e6, 1), 'MB')


if __name__ == '__main__':
    sys.exit(main())
