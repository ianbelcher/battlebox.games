#!/usr/bin/env python3
"""Download every build listed in kits/sources.txt into kits/downloads/.

The workflow is "paste a link, get a kit", so this takes the links and
does the fetching; game/tests/import_structures.gd then turns whatever
landed into stampable kits. Run tools/import_kits.sh to do both.

Sites differ in how much they want to be scraped:

  * A direct link to a .schem/.schematic/.nbt just downloads.
  * minecraft-schematics.com puts the file behind a /download/ URL that
    usually requires a free login, so an anonymous fetch gets an HTML
    page back instead of a build. We detect that and say so rather than
    saving a login page named like a schematic.
  * planetminecraft.com serves a zip; we take the schematic out of it.

Anything that can't be fetched is reported with a one-line instruction:
download it by hand into kits/downloads/. The importer does not care how
a file got there.

Usage: python3 tools/fetch_kits.py [--sources FILE] [--out DIR]
"""

import argparse
import io
import json
import os
import re
import sys
import urllib.error
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
WORLD = os.path.dirname(HERE)
DEFAULT_SOURCES = os.path.join(WORLD, "kits", "sources.txt")
DEFAULT_OUT = os.path.join(WORLD, "kits", "downloads")
MANIFEST = os.path.join(WORLD, "kits", "manifest.json")

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")
BUILD_EXT = (".schem", ".schematic", ".nbt")


def parse_sources(path):
    """-> [{'url':…, 'name':…, 'by':…}] from the pasted-links file."""
    out = []
    if not os.path.exists(path):
        return out
    with open(path) as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = [p.strip() for p in line.split("|")]
            url = parts[0]
            if not url.lower().startswith("http"):
                continue
            out.append({
                "url": url,
                "name": parts[1] if len(parts) > 1 and parts[1] else "",
                "by": parts[2] if len(parts) > 2 and parts[2] else "",
            })
    return out


def slug(text):
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_") or "build"


def get(url, referer=None):
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Accept": "*/*",
        **({"Referer": referer} if referer else {}),
    })
    with urllib.request.urlopen(req, timeout=45) as resp:
        return resp.read(), resp.headers.get("Content-Type", ""), resp.geturl()


def looks_like_build(data):
    """Real builds are gzipped NBT (1f 8b) or bare NBT (a compound, 0x0a).
    An HTML login page is neither, and that is exactly what these sites
    hand back when they want you signed in."""
    return len(data) > 200 and (data[:2] == b"\x1f\x8b" or data[:1] == b"\x0a")


def from_zip(data):
    """Planet Minecraft ships a project zip; take the build out of it."""
    try:
        zf = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile:
        return None, None
    for name in zf.namelist():
        if name.lower().endswith(BUILD_EXT):
            return zf.read(name), os.path.splitext(name)[1].lower()
    return None, None


def candidates(url):
    """URLs worth trying, in order, for a page link rather than a file."""
    if url.lower().endswith(BUILD_EXT):
        return [url]
    tries = [url]
    m = re.search(r"minecraft-schematics\.com/schematic/(\d+)", url)
    if m:
        # The site's own download endpoint for that schematic id.
        tries.insert(0, "https://www.minecraft-schematics.com/download/%s/" % m.group(1))
    return tries


def fetch_one(entry, out_dir):
    """-> (path, note). path is None when it needs doing by hand."""
    url = entry["url"]
    name = entry["name"] or slug(url.rstrip("/").split("/")[-1])
    for attempt in candidates(url):
        try:
            data, ctype, final = get(attempt, referer=url)
        except (urllib.error.URLError, urllib.error.HTTPError, OSError) as err:
            continue
        ext = None
        if "zip" in ctype or data[:2] == b"PK":
            data, ext = from_zip(data)
            if data is None:
                continue
        if not looks_like_build(data):
            continue
        if ext is None:
            ext = next((e for e in BUILD_EXT if final.lower().endswith(e)), ".schem")
        path = os.path.join(out_dir, slug(name) + ext)
        with open(path, "wb") as fh:
            fh.write(data)
        return path, "%d KB" % (len(data) // 1024)
    return None, "needs a manual download (the site wants a login)"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sources", default=DEFAULT_SOURCES)
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    entries = parse_sources(args.sources)
    if not entries:
        print("Nothing listed in %s — paste a build link in there first."
              % args.sources)
        return 0

    manifest = {}
    if os.path.exists(MANIFEST):
        try:
            manifest = json.load(open(MANIFEST))
        except ValueError:
            manifest = {}

    manual = []
    for entry in entries:
        path, note = fetch_one(entry, args.out)
        label = entry["name"] or entry["url"]
        if path:
            print("  ok      %-28s %s" % (label, note))
            manifest[os.path.basename(path)] = {
                "name": entry["name"], "by": entry["by"], "url": entry["url"]}
        else:
            print("  MANUAL  %-28s %s" % (label, note))
            manual.append(entry)

    # Anything already sitting under kits/ counts too, however it arrived —
    # a hand-download is a first-class way to add a build, not a fallback.
    # If the filename carries the site's id (30747.schem) we can match it
    # back to its sources.txt line and keep the name and builder.
    by_id = {}
    for entry in entries:
        m = re.search(r"/(\d+)/?$", entry["url"].rstrip("/") + "/")
        if m:
            by_id[m.group(1)] = entry
    kits_root = os.path.dirname(args.out)
    for root, _dirs, files in os.walk(kits_root):
        for fname in sorted(files):
            if not fname.lower().endswith(BUILD_EXT):
                continue
            known = manifest.get(fname, {})
            # Re-match every run: an earlier pass may have filed this as an
            # anonymous hand-drop before its link was in sources.txt.
            if known.get("name") and known.get("by"):
                continue
            stem = os.path.splitext(fname)[0]
            hit = by_id.get(stem)
            if hit:
                manifest[fname] = {"name": hit["name"], "by": hit["by"],
                                   "url": hit["url"]}
                print("  matched %-28s -> %s" % (fname, hit["name"] or hit["url"]))
            elif fname not in manifest:
                manifest[fname] = {"name": "", "by": "",
                                   "url": "(added by hand)"}

    with open(MANIFEST, "w") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True)
    print("\n%d build(s) in %s" % (
        len([f for f in os.listdir(args.out) if f.lower().endswith(BUILD_EXT)]),
        args.out))
    if manual:
        print("\nDownload these by hand and drop the file into %s:" % args.out)
        for entry in manual:
            print("   %s" % entry["url"])
        print("The importer picks up anything in that folder.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
