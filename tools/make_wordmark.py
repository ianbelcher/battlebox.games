#!/usr/bin/env python3
"""Trace the BattleBox neon sign out of the intro video.

    python3 tools/make_wordmark.py web/demo.mp4 game/assets/ui/wordmark.png

THE LETTERFORMS ARE NOT A TYPEFACE. The sign was built and lit in
Minecraft and its shapes are its own; matching them to an open font was
tried first and it is not close, which is obvious the moment the two are
put side by side. So they are traced out of the film instead, and what
the game draws IS the sign.

WHY A THRESHOLD IS ENOUGH: a lit neon tube is the brightest thing in the
frame by a distance, so it cuts cleanly out of a daylit field. The
scaffold it hangs on is lit too — but its rails run the full width of the
shot and no letter does, so a row that is mostly lit is a rail. What
survives is a double contour of every stroke, which is what a glass tube
looks like head on.

WHICH FRAME MATTERS. Earlier in the video the word is bigger, and it is
unusable: explosions go off behind the sign and blow out to a white that
is every bit as bright as the tube and joined to it, so no filter of any
kind can tell them apart. The film settles at the end — same sign, calm
field, nothing behind it. Smaller, and perfect.

The colour is rebuilt rather than sampled. Sampled, it drags in the sky
and the grass showing through the letters; rebuilt, rings grown out from
the trace give the haze, the pink glass, the blue inside it and the white
filament, and nothing of the field it was filmed in.
"""

import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

## Seconds into the film. The last stretch, after the explosions are out.
FRAME_AT = 14.5
## A lit tube is this bright, never this dark in any channel, and always
## has blue in it — the glass is pink, the core is white and the inner
## line is blue, and none of those is orange like a spark.
MIN_VALUE, MIN_CHANNEL, MIN_BLUE = 232, 120, 150
## A row this lit, right across the frame, is the scaffold.
RAIL_ROW = 0.45
## Below this a lit patch is a cloud edge or a bit of grass, not a letter.
MIN_BLOB, MIN_TALL = 150, 18
## The source is 720p and the trace comes off it in stair-steps, so it is
## scaled up and then rounded back into curves.
UPSCALE = 3
## Ring radii, in the scaled-up trace's pixels: haze, pink glass, the blue
## inside it, and the filament (which is the trace pulled IN, so the
## colour has somewhere to sit).
RINGS = ((18, 26.0, (1.00, 0.16, 0.58), 0.60),
         (10, 3.0, (1.00, 0.18, 0.60), 1.00),
         (4, 1.6, (1.00, 0.42, 0.80), 1.00),
         (0, 1.2, (0.45, 0.82, 1.00), 1.00),
         (-3, 0.9, (1.00, 0.98, 1.00), 1.00))
## Room around the letters for the haze to fall off in.
MARGIN = 46


def grab(video: str, seconds: float, into: Path) -> Image.Image:
    subprocess.run(["ffmpeg", "-v", "error", "-ss", str(seconds), "-i", video,
                    "-frames:v", "1", "-y", str(into)], check=True)
    return Image.open(into).convert("RGB")


def trace(frame: Image.Image) -> np.ndarray:
    a = np.asarray(frame).astype(np.int16)
    lit = ((a.max(axis=2) >= MIN_VALUE) & (a.min(axis=2) >= MIN_CHANNEL)
           & (a[..., 2] >= MIN_BLUE) & (a[..., 0] >= a[..., 2] - 45))
    lit[lit.mean(axis=1) > RAIL_ROW, :] = False
    labels, count = ndimage.label(lit, np.ones((3, 3)))
    sizes = ndimage.sum(lit, labels, range(1, count + 1))
    boxes = ndimage.find_objects(labels)
    keep = np.zeros_like(lit)
    for i, (size, box) in enumerate(zip(sizes, boxes), start=1):
        if size >= MIN_BLOB and (box[0].stop - box[0].start) >= MIN_TALL:
            keep |= labels == i
    if not keep.any():
        raise SystemExit("make_wordmark: found no sign in that frame")
    return keep


def tidy(keep: np.ndarray) -> np.ndarray:
    ys, xs = np.where(keep)
    y0, y1 = max(0, ys.min() - 4), min(keep.shape[0], ys.max() + 5)
    x0, x1 = max(0, xs.min() - 4), min(keep.shape[1], xs.max() + 5)
    art = Image.fromarray((keep[y0:y1, x0:x1] * 255).astype(np.uint8))
    art = art.resize((art.width * UPSCALE, art.height * UPSCALE), Image.LANCZOS)
    art = art.filter(ImageFilter.GaussianBlur(UPSCALE * 0.8)).point(
        lambda p: 255 if p > 110 else 0)
    grown = Image.new("L", (art.width + MARGIN * 2, art.height + MARGIN * 2), 0)
    grown.paste(art, (MARGIN, MARGIN))
    return np.asarray(grown).astype(np.float32) / 255.0


def _disc(r: int) -> np.ndarray:
    yy, xx = np.ogrid[-r:r + 1, -r:r + 1]
    return (yy * yy + xx * xx) <= r * r


def ring(mask: np.ndarray, grow: int, soft: float) -> np.ndarray:
    """The trace, fattened (or pulled in) and softened at its edge."""
    shape = mask > 0.5
    if grow > 0:
        shape = ndimage.binary_dilation(shape, _disc(grow))
    elif grow < 0:
        shape = ndimage.binary_erosion(shape, _disc(-grow))
    img = Image.fromarray((shape * 255).astype(np.uint8))
    return np.asarray(img.filter(ImageFilter.GaussianBlur(soft))
                      ).astype(np.float32) / 255.0


def paint(mask: np.ndarray) -> Image.Image:
    """Widest ring first. Each one inside covers the middle of the one
    before it, so what is left of each is a band — which is a tube seen
    end on."""
    h, w = mask.shape
    rgb = np.zeros((h, w, 3), np.float32)
    alpha = np.zeros((h, w), np.float32)
    for grow, soft, colour, gain in RINGS:
        band = np.clip(ring(mask, grow, soft) * gain, 0.0, 1.0)
        rgb = rgb * (1 - band[..., None]) + np.array(colour) * band[..., None]
        alpha = np.maximum(alpha, band)
    return Image.fromarray(np.dstack(
        [np.clip(rgb, 0, 1) * 255, np.clip(alpha, 0, 1) * 255]
    ).astype(np.uint8), "RGBA")


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2
    video, out = argv[1], argv[2]
    with tempfile.TemporaryDirectory() as scratch:
        frame = grab(video, FRAME_AT, Path(scratch) / "frame.png")
    art = paint(tidy(trace(frame)))
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    art.save(out)
    print("make_wordmark: %dx%d -> %s" % (art.width, art.height, out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
