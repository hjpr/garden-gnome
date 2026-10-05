"""Generate round-2 ground texture candidates at the 5 ft house scale.

Usage: python3 gen_ground.py OUTDIR material[,material...] [count]
The style anchor is crimson clover 05 (docs/concepts/whimsy/textures/raw).
Half the candidates get it as a style reference, half get the prompt only,
so neither path's habits dominate a bank. Generated images are never fed
back in as references (that compounded artefacts in round 1).
"""
import base64, json, os, sys, urllib.request, concurrent.futures as cf

KEY = os.environ["OPENROUTER_API_KEY"]
MODEL = os.environ.get("MODEL", "google/gemini-3.1-flash-image")
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ANCHOR = os.path.join(ROOT, "docs/concepts/whimsy/textures/raw/crimson_clover-05.png")
MAX_SPEND = float(os.environ.get("MAX_SPEND", "3.0"))  # this run only

COMMON = ("Seen vertically overhead, like a flat map, no perspective, no horizon. "
          "Matte hand-painted gouache illustration with soft pencil detail, clear "
          "readable shapes, gentle two-tone shading, diffuse even light, no cast "
          "shadows. Uniform density across the whole 1024 square, filling every edge, "
          "no empty space, no border, no vignette, no frame, no text, no rows, no "
          "stripes, no single direction.")

MATERIALS = {
    "crimson_clover": ("A lush dense patch of crimson clover. About fifteen clover leaves "
                       "span the image width; each leaf has three oval leaflets with pale V "
                       "marks, medium greens #2F6B3F #4F9A3A #7FB255. About twelve small "
                       "crimson flower heads scattered evenly, a little soil and dry stems "
                       "in the gaps."),
    "wild_grass": ("Rough wild meadow grass. Loose clumps of short grass blades pointing "
                   "every way, about fourteen clumps across the image width, with a few "
                   "small clover leaves, a few tiny white and yellow flowers and dry tan "
                   "blades mixed in. Muted greens #3F6E33 #5E8C3E #8AA65A."),
    "lawn": ("A tidy mown lawn. Short soft grass blades in small tufts pointing every "
             "way, about twenty tufts across the image width, even fresh medium green "
             "#4E8F3A #6FA24A #3A7030, no flowers, no clover, no mowing stripes."),
    "dirt": ("Soft bare garden earth, dry and light: fine crumbly sandy-tan loam "
             "#C99A68 #B8875A #D6AC7C, a smooth matte surface of tiny soft crumbs and "
             "fine grain with gentle low-contrast mottling, only a few slightly darker "
             "crumbs. NO pebbles, NO stones, NO round clods, NO cobbles, no outlines, "
             "no leaves, no plants. Calm and quiet so plants drawn on top stand out."),
    "prepped_soil": ("Freshly prepared garden bed soil, level and loose, medium "
                     "chocolate brown #8C5838 #7A4C30 #9C6644, fine soft crumbly texture "
                     "like raked compost-rich earth, tiny soft crumbs with gentle "
                     "low-contrast mottling. NO pebbles, NO stones, NO round clods, NO "
                     "cobbles, no rake lines, no streaks, no diagonal marks, no outlines, no leaves, no plants. Calm and "
                     "quiet so plants drawn on top stand out."),
    "loam": ("Rich dark moist tilled loam, freshly worked garden bed soil. Dark "
             "brown #4A2E1F #5C3A26 #3A2418, fine soft crumbly texture like crumbled "
             "chocolate cake, gentle low-contrast mottling and tiny crumbs. NO pebbles, "
             "NO stones, NO round clods, NO cobbles, no outlines, no leaves, no plants. "
             "Calm and quiet so plants drawn on top stand out."),
}


# Clover-05's own wording. Over-asking ("tiny", "less than 15px") is what
# landed its leaves at about 65 px; the plainer prompt above drew them
# 2.5-3.5x bigger. Never give clover the anchor as a reference: the model
# returns the anchor itself (about 2% RMSE, same flower positions).
CLOVER_TEXT = ("Paint 1200 tiny clover plants seen vertically overhead in a lush dense "
               "green field. All the little leaves are less than 15px wide, flat medium "
               "green with pale V marks, matte gouache and pencil style. Crimson clover "
               "ONLY, three oval leaflets in each tiny cluster; just twelve miniature "
               "crimson buds scattered across the whole 1024 square. Uniform density and "
               "diffuse light. Foliage fills all the way to each outer edge, no empty "
               "space. Muted medium greens #2F6B3F #4F9A3A #7FB255. Entirely fresh "
               "natural arrangement number {n}, no border or text.")


def usage():
    req = urllib.request.Request("https://openrouter.ai/api/v1/credits",
                                 headers={"Authorization": f"Bearer {KEY}"})
    return json.load(urllib.request.urlopen(req))["data"]["total_usage"]


def generate(material, index, with_ref, out):
    if material == "crimson_clover":
        prompt, with_ref = CLOVER_TEXT.format(n=index), False
    else:
        prompt = f"Paint a seamless ground texture. {MATERIALS[material]} {COMMON}"
    content = prompt
    if with_ref:
        with open(ANCHOR, "rb") as f:
            ref = base64.b64encode(f.read()).decode()
        content = [
            {"type": "text", "text": "Use the attached picture ONLY as a guide to painting "
             "style, detail level and the size of shapes. Do not copy its subject or "
             "layout. " + prompt},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{ref}"}},
        ]
    body = {"model": MODEL, "modalities": ["image", "text"],
            "messages": [{"role": "user", "content": content}],
            "image_config": {"aspect_ratio": "1:1"}}
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions",
                                 data=json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {KEY}",
                                          "Content-Type": "application/json"})
    resp = json.load(urllib.request.urlopen(req, timeout=240))
    images = resp["choices"][0]["message"].get("images") or []
    record = {"material": material, "index": index, "reference": with_ref,
              "prompt": prompt, "model": MODEL,
              "cost_usd": resp.get("usage", {}).get("cost")}
    if not images:
        record["error"] = str(resp["choices"][0]["message"].get("content"))[:300]
        return record
    with open(out, "wb") as f:
        f.write(base64.b64decode(images[0]["image_url"]["url"].split(",", 1)[1]))
    record["file"] = os.path.basename(out)
    return record


def main():
    outdir, names = sys.argv[1], sys.argv[2].split(",")
    count = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    first = int(os.environ.get("FIRST", "1"))  # number new candidates after old ones
    # REF: "alternate" (default), "always" or "never". Round 1 showed the
    # anchor reference gives the better soils and grasses.
    ref = os.environ.get("REF", "alternate")
    jobs = [(m, i, ref == "always" or (ref == "alternate" and i % 2 == 0))
            for m in names for i in range(first, first + count)]
    if 0.08 * len(jobs) > MAX_SPEND:
        sys.exit(f"refusing: {len(jobs)} images could pass ${MAX_SPEND}")
    os.makedirs(outdir, exist_ok=True)
    start = usage()
    records = []
    with cf.ThreadPoolExecutor(8) as pool:
        futs = [pool.submit(generate, m, i, r, os.path.join(outdir, f"{m}-c{i:02}.png"))
                for m, i, r in jobs]
        for f in cf.as_completed(futs):
            try:
                rec = f.result()
            except Exception as e:  # noqa: BLE001
                rec = {"error": str(e)[:300]}
            records.append(rec)
            print(json.dumps({k: v for k, v in rec.items() if k != "prompt"}), flush=True)
    spent = usage() - start
    path = os.path.join(outdir, "manifest.json")
    old = json.load(open(path)) if os.path.exists(path) else {"runs": []}
    old["runs"].append({"spent_usd": round(spent, 4), "records": records})
    json.dump(old, open(path, "w"), indent=1)
    print(f"run spent ${spent:.3f}")


if __name__ == "__main__":
    main()
