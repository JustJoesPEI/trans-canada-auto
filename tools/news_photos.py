#!/usr/bin/env python3
"""Saves the photos in CBC news articles, with their captions, for looking
up how a real place looks before building it (no photo from Joe yet).

    python3 -I tools/news_photos.py OUTDIR URL [URL...]

Each article's photos go to OUTDIR as <article>_<n>.jpg, 1280 wide, and
the caption and publication date are printed. Find the articles with a web
search (site cbc.ca); the environment allows www.cbc.ca and i.cbc.ca.
Article pages also carry other stories' thumbnails, so look before using
one. The pictures are CBC's: look at them, don't put them in the game.
"""
import sys, re, json, html, urllib.request, os
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36"
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
for url in sys.argv[2:]:
    page = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=25).read().decode("utf8", "replace")
    slug = re.sub(r'[^a-z0-9]+', '_', url.rsplit('/', 1)[-1].lower())[:50]
    title = re.search(r'<title>(.*?)</title>', page, re.S)
    print("==", html.unescape(title.group(1)).strip() if title else url)
    date = re.search(r'"datePublished":"([^"]+)"', page); print("   published", date.group(1) if date else "?")
    seen = set(); k = 0
    for m in re.finditer(r'<figure.*?</figure>', page, re.S):
        fig = m.group(0)
        src = re.search(r'(https://i\.cbc\.ca/[^"\s]+?/default\.jpg)', fig)
        if not src: continue
        base = src.group(1)
        if base in seen: continue
        seen.add(base)
        cap = re.sub(r'<[^>]+>', ' ', re.search(r'<figcaption.*?</figcaption>', fig, re.S).group(0)) if '<figcaption' in fig else ''
        cap = html.unescape(re.sub(r'\s+', ' ', cap)).strip()
        try:
            data = urllib.request.urlopen(urllib.request.Request(base + "?im=Resize%3D1280", headers={"User-Agent": UA}), timeout=25).read()
        except Exception as e:
            print("   fail", base, e); continue
        p = f"{out}/{slug}_{k}.jpg"; open(p, "wb").write(data); k += 1
        print("  ", p, "|", cap[:200])
