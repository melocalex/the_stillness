#!/usr/bin/env python3
"""Search the public Roblox Creator Store and print vetting details.

Usage: python3 -I tools/assets/search_store.py <category> "<keyword>" [count]
  category: models | audio | meshes | decals
Prints one line per result: id, name, creator, verified/endorsed flags,
free/price, hasScripts, duration (audio). Read-only public API; no auth.
"""
import json
import sys
import urllib.parse
import urllib.request

CATEGORY = {"models": 10, "audio": 3, "meshes": 40, "decals": 13}
BASE = "https://apis.roblox.com/toolbox-service/v1"


def get(url):
    req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "asset-vetting-script"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def main():
    cat, keyword = sys.argv[1], sys.argv[2]
    count = int(sys.argv[3]) if len(sys.argv) > 3 else 15
    q = urllib.parse.urlencode({"keyword": keyword, "num": max(count, 10)})
    ids = [str(x["id"]) for x in get(f"{BASE}/marketplace/{CATEGORY[cat]}?{q}").get("data", [])][:count]
    if not ids:
        print("no results")
        return
    details = get(f"{BASE}/items/details?assetIds={','.join(ids)}").get("data", [])
    for it in details:
        a, c = it.get("asset", {}), it.get("creator", {})
        prod = it.get("fiatProduct") or it.get("product") or {}
        price = prod.get("purchasePrice") or prod.get("price")
        free = "FREE" if not price or (isinstance(price, dict) and str(price.get("quantity", {}).get("significand", 0)) == "0") else f"PRICE {price}"
        flags = []
        if c.get("isVerifiedCreator"):
            flags.append("verified")
        if a.get("isEndorsed"):
            flags.append("endorsed")
        if a.get("hasScripts"):
            flags.append("HAS-SCRIPTS")
        dur = f"{a.get('duration')}s" if a.get("duration") else ""
        print(f"{a.get('id')}\t{a.get('name')!r}\t{c.get('name')}\t{','.join(flags)}\t{free}\t{dur}")


if __name__ == "__main__":
    main()
