"""Generate overhead plant sprite candidates on a magenta key.

Usage: python3 gen_plants.py OUTDIR [name,name,...] [count]
Descriptions come from plants.json. Candidate 1 of each plant gets the
clover-05 ground texture as a STYLE reference (the matte gouache look of the
ground); candidate 2 gets the prompt only. Never feed a generated sprite back
in as a reference.
"""
import base64, json, os, sys, urllib.request, concurrent.futures as cf

KEY = os.environ["OPENROUTER_API_KEY"]
MODEL = os.environ.get("MODEL", "google/gemini-3.1-flash-image")
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ANCHOR = os.path.join(ROOT, "docs/concepts/whimsy/textures/raw/crimson_clover-05.png")
MAX_SPEND = float(os.environ.get("MAX_SPEND", "6.0"))  # this run only

COMMON = ("Seen from DIRECTLY ABOVE, a strict orthographic top-down overhead view like "
          "a garden plan: we look straight down onto the top of the plant, its centre in "
          "the middle of the picture, leaves spreading out in every direction, nothing "
          "hanging, no side view, no stems seen from the side. One single plant, centred, "
          "about 75% of the frame wide, with a clear empty magenta margin all round it. Matte hand-painted gouache "
          "illustration with soft pencil detail, clear readable leaf shapes, gentle "
          "two-tone shading, diffuse even light, no cast shadow, no soil, no pot, no "
          "outline, no border, no text. Background: perfectly flat solid pure magenta "
          "#FF00FF everywhere around the plant, nothing else.")


def usage():
    req = urllib.request.Request("https://openrouter.ai/api/v1/credits",
                                 headers={"Authorization": f"Bearer {KEY}"})
    return json.load(urllib.request.urlopen(req))["data"]["total_usage"]


def generate(name, desc, index, with_ref, out):
    prompt = f"Paint {desc}. {COMMON}"
    content = prompt
    if with_ref:
        with open(ANCHOR, "rb") as f:
            ref = base64.b64encode(f.read()).decode()
        content = [
            {"type": "text", "text": "The attached picture is ONLY a guide to painting "
             "style and colour (matte gouache, soft shading, muted natural greens). Do not "
             "copy its subject, layout or background. " + prompt},
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
    record = {"plant": name, "index": index, "reference": with_ref, "prompt": prompt,
              "model": MODEL, "cost_usd": resp.get("usage", {}).get("cost")}
    if not images:
        record["error"] = str(resp["choices"][0]["message"].get("content"))[:300]
        return record
    with open(out, "wb") as f:
        f.write(base64.b64decode(images[0]["image_url"]["url"].split(",", 1)[1]))
    record["file"] = os.path.basename(out)
    return record


def main():
    outdir = sys.argv[1]
    plants = {k: v for k, v in json.load(open(os.path.join(HERE, "plants.json"))).items()
              if not k.startswith("_")}
    names = sys.argv[2].split(",") if len(sys.argv) > 2 and sys.argv[2] else list(plants)
    count = int(sys.argv[3]) if len(sys.argv) > 3 else 2
    first = int(os.environ.get("FIRST", "1"))
    ref = os.environ.get("REF", "alternate")
    jobs = [(n, i, ref == "always" or (ref == "alternate" and i % 2 == 1))
            for n in names for i in range(first, first + count)]
    if 0.08 * len(jobs) > MAX_SPEND:
        sys.exit(f"refusing: {len(jobs)} images could pass ${MAX_SPEND}")
    os.makedirs(outdir, exist_ok=True)
    start = usage()
    records = []
    with cf.ThreadPoolExecutor(8) as pool:
        futs = [pool.submit(generate, n, plants[n], i, r,
                            os.path.join(outdir, f"{n}-c{i:02}.png")) for n, i, r in jobs]
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
