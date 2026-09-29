#!/usr/bin/env bash
# Turns the picked generations into app assets:
#   textures -> 512 px seamless JPEGs, sprites -> magenta keyed, trimmed PNGs.
set -euo pipefail
cd "$(dirname "$0")"
OUT=out
mkdir -p "$OUT" work

# Seamless tile: blend the image with a half-offset copy of itself. The
# mask is opaque in the middle (keep the original) and clear at the edges
# (show the rolled copy, whose edges are the original's continuous middle).
seamless() {
  local src=$1 dst=$2 size=512
  magick "$src" -resize ${size}x${size}! work/a.png
  magick work/a.png -roll +$((size/2))+$((size/2)) work/b.png
  magick -size ${size}x${size} xc: -fx \
    'min(1,max(0,(min(min(i,w-1-i),min(j,h-1-j))/(w/2)-0.08)/0.30))' \
    work/mask.png
  magick work/b.png work/a.png work/mask.png -composite -quality 88 "$dst"
}

seamless r1/wild_grass_v1.png   "$OUT/wild_grass.jpg"
seamless r1/lawn_v2.png         "$OUT/lawn.jpg"
seamless r3/zone_dirt3_v2.png   "$OUT/dirt.jpg"
seamless r2/loam2_v2.png        "$OUT/loam.jpg"
seamless r2/prepped_soil2_v1.png "$OUT/prepped_soil.jpg"

# Sprites: key out magenta (with a soft edge), remove pink fringe, trim.
sprite() {
  local src=$1 dst=$2 width=$3
  magick "$src" -alpha set -channel RGBA -fuzz 28% -fill none \
    -draw "color 0,0 floodfill" -draw "color %[fx:w-1],0 floodfill" \
    -draw "color 0,%[fx:h-1] floodfill" -draw "color %[fx:w-1],%[fx:h-1] floodfill" \
    work/keyed.png
  # Shrink the alpha one pixel to drop the magenta halo, then trim.
  magick work/keyed.png \( +clone -alpha extract -morphology Erode Disk:1.2 -blur 0x0.6 \) \
    -compose CopyOpacity -composite -trim +repage -resize ${width}x work/trim.png
  # Magenta despill: where red and blue both exceed green, pull them down
  # by the excess so tinted film goes back to neutral white/grey.
  magick work/trim.png -channel RB -fx 'u-max(0,min(r,b)-g)*0.85' +channel "$dst"
}

sprite r3/raised_bed3_v1.png  "$OUT/raised_bed.png"  768
sprite r1/greenhouse_v1.png   "$OUT/greenhouse.png"  768
sprite r3/high_tunnel3_v2.png work/high_tunnel.png 1024
# The tunnel is cut into pieces drawn 5 ft each: the left end (up to just
# past its first straight hoop), one middle bay (hoop to hoop) and the
# real right end. Keep the right end rather than mirroring the left, or
# the glare streaks flip.
magick work/high_tunnel.png -crop 160x368+0+0 +repage "$OUT/tunnel_end_left.png"
magick work/high_tunnel.png -crop 100x368+461+0 +repage "$OUT/tunnel_mid.png"
magick work/high_tunnel.png -crop 163x368+861+0 +repage "$OUT/tunnel_end_right.png"

for f in "$OUT"/*; do
  echo "$f $(magick identify -format '%wx%h' "$f") $(du -k "$f" | cut -f1)K"
done
