"""Generate Animal-Crossing-style textures and feature sprites via OpenRouter.

Usage: python3 gen.py ROUND   (writes into ./ROUND/NAME_vN.png)
Stops before spending past BUDGET (measured from the credits endpoint).
"""
import base64, json, os, sys, urllib.request, concurrent.futures as cf

KEY = os.environ["OPENROUTER_API_KEY"]
MODEL = os.environ.get("MODEL", "google/gemini-3.1-flash-image")
# Spend is measured from the account usage when a run starts.
START_USAGE = float(os.environ.get("START_USAGE", "0"))
BUDGET = 3.0
HERE = os.path.dirname(os.path.abspath(__file__))  # outputs land beside this script

STYLE = ("in the cozy art style of Animal Crossing New Horizons: soft, rounded, "
         "hand-painted, gently saturated colours, clean and cute, no text, no watermark")
TEX = ("A seamless tileable square texture seen straight from above (orthographic top-down, "
       "no perspective, no horizon, no vignette, no border, evenly lit, no cast shadows), "
       "filling the whole frame edge to edge. ")
SPRITE = ("A single object seen exactly straight down from above (orthographic top-down plan view, "
          "no perspective, no side walls visible), centred and filling about 90% of the frame, "
          "on a perfectly flat solid pure magenta #FF00FF background with nothing else in the image. ")

ASSETS = {
    "wild_grass": (TEX + "A wild meadow of uneven grass with scattered tiny white, yellow and pink "
                   "flowers, clover patches and a few little weeds, " + STYLE, "1:1"),
    "lawn": (TEX + "A neat freshly mown lawn: short, even, bright green grass with subtle soft "
             "variation, very tidy, " + STYLE, "1:1"),
    "zone_dirt": (TEX + "Smooth, manicured, raked warm brown garden dirt path surface, tidy and "
                  "even with a few tiny pebbles, " + STYLE, "1:1"),
    "loam": (TEX + "Rich dark brown loamy tilled soil, soft crumbly clumps and moist texture, "
             "freshly hoed garden bed soil, " + STYLE, "1:1"),
    "prepped_soil": (TEX + "Clean, finely prepared garden soil base, level and smooth, medium "
                     "chocolate brown with very fine grain, ready for planting, " + STYLE, "1:1"),
    "loam2": (TEX + "Rich dark brown loamy garden soil, soft rounded crumbly clumps scattered "
              "evenly with no rows, no stripes and no direction, flat simple shading, a few tiny "
              "pebbles, " + STYLE, "1:1"),
    "prepped_soil2": (TEX + "Finely raked, level, prepared garden soil, warm medium chocolate "
                      "brown, lighter than loam, soft little stylized crumbs and a few tiny "
                      "pebbles spread evenly, no rows, no direction, " + STYLE, "1:1"),
    "raised_bed2": (SPRITE + "A rectangular wooden raised garden bed (twice as long as wide, long "
                    "side horizontal) seen exactly from directly above so only the TOP edges of "
                    "the cedar planks show, rounded corner posts, dark soil planted with a cute mix "
                    "of lettuces, carrot tops and radish leaves, " + STYLE, "16:9"),
    "high_tunnel2": (SPRITE + "The roof of a long agricultural high tunnel hoop house seen exactly "
                     "from directly above as a flat rectangle (long side horizontal, about three "
                     "times as long as wide, no end caps visible): bright WHITE slightly "
                     "translucent plastic film (no pink tint) stretched over evenly spaced grey "
                     "metal hoops that cross the short direction, soft blurry green crop rows "
                     "faintly visible through the film, " + STYLE, "21:9"),
    "raised_bed3": (SPRITE + "A rectangular wooden raised garden bed, twice as long as wide, long "
                    "side horizontal, only the top edges of warm honey cedar planks visible, small "
                    "rounded corner posts, filled with dark soil holding neat rows of cute little "
                    "green lettuce and seedling rosettes (all green, no red or purple leaves), "
                    "plants stay inside the frame, " + STYLE, "16:9"),
    "high_tunnel3": (SPRITE + "The roof of a long high tunnel hoop house as a flat rectangle, "
                     "long side horizontal, about three times as long as wide, square ends: clean "
                     "white translucent plastic film with evenly spaced straight grey hoop lines "
                     "running across the short direction, a straight ridge line along the middle, "
                     "faint pastel green crop rows visible through the film, " + STYLE, "21:9"),
    "zone_dirt3": (TEX + "Tidy, smooth, compacted light warm brown garden dirt, lightly speckled "
                   "with tiny warm-coloured crumbs and a few small tan pebbles, no stripes, no "
                   "rows, no ridges, no direction, flat even shading, " + STYLE, "1:1"),
    "raised_bed": (SPRITE + "A rectangular wooden raised garden bed (twice as long as wide, long "
                   "side horizontal) made of warm cedar planks with corner posts, filled with dark "
                   "soil and small rows of green seedlings, " + STYLE, "16:9"),
    "greenhouse": (SPRITE + "The roof of a small rectangular glass greenhouse (long side horizontal): "
                   "white painted frame, pale mint-tinted glass panes, a ridge running along the "
                   "middle, a hint of green plants visible through the glass, " + STYLE, "16:9"),
    "high_tunnel": (SPRITE + "The roof of a long agricultural high tunnel hoop house (long side "
                    "horizontal, about three times as long as wide): translucent milky white "
                    "plastic film stretched over evenly spaced metal hoops running across the "
                    "short direction, " + STYLE, "21:9"),
}


def usage():
    req = urllib.request.Request("https://openrouter.ai/api/v1/credits",
                                 headers={"Authorization": f"Bearer {KEY}"})
    return json.load(urllib.request.urlopen(req))["data"]["total_usage"]


STYLE_REF = os.environ.get("STYLE_REF")


def generate(name, prompt, aspect, out):
    content = prompt
    if STYLE_REF:
        with open(STYLE_REF, "rb") as f:
            ref = base64.b64encode(f.read()).decode()
        content = [
            {"type": "text", "text": "Match the exact art style of this reference image "
             "(flat pastel colours, thin soft dark outlines, minimal shading, strict top-down "
             "plan view on a flat magenta background). Do not copy its subject. " + prompt},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{ref}"}},
        ]
    body = {"model": MODEL, "modalities": ["image", "text"],
            "messages": [{"role": "user", "content": content}],
            "image_config": {"aspect_ratio": aspect}}
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions",
                                 data=json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {KEY}",
                                          "Content-Type": "application/json"})
    resp = json.load(urllib.request.urlopen(req, timeout=240))
    images = resp["choices"][0]["message"].get("images") or []
    if not images:
        return f"{name}: no image ({resp['choices'][0]['message'].get('content')!r:.200})"
    url = images[0]["image_url"]["url"]
    with open(out, "wb") as f:
        f.write(base64.b64decode(url.split(",", 1)[1]))
    return f"{name}: {out} cost={resp.get('usage', {}).get('cost')}"


def main():
    rnd = sys.argv[1]
    names = sys.argv[2].split(",") if len(sys.argv) > 2 else list(ASSETS)
    variants = int(os.environ.get("VARIANTS", "2"))
    spent = usage() - START_USAGE
    print(f"spent so far ${spent:.3f}")
    jobs = [(n, v) for n in names for v in range(1, variants + 1)]
    if spent + 0.1 * len(jobs) > BUDGET:
        sys.exit(f"refusing: {len(jobs)} images could exceed budget (spent ${spent:.2f})")
    os.makedirs(os.path.join(HERE, rnd), exist_ok=True)
    with cf.ThreadPoolExecutor(8) as pool:
        futs = [pool.submit(generate, n, ASSETS[n][0], ASSETS[n][1],
                            os.path.join(HERE, rnd, f"{n}_v{v}.png")) for n, v in jobs]
        for f in cf.as_completed(futs):
            try:
                print(f.result(), flush=True)
            except Exception as e:  # noqa: BLE001
                print("error", e, flush=True)
    print(f"spent total ${usage() - START_USAGE:.3f}")


if __name__ == "__main__":
    main()
