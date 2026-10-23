"""Render BulletHwaven's music and sound effects (all procedural, no samples, no licences).

Usage:  python tools/audiogen/generate.py              all sounds and music into game/assets/audio/
        python tools/audiogen/generate.py --only mg,cannon,combat
Needs numpy, scipy (requirements.txt) and ffmpeg with libvorbis for the music loops.
"""

import argparse
import os
import subprocess
import sys
import tempfile
import wave
import zlib

import numpy as np

import music
import sfx
from dsp import SR, fade, filt

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "game", "assets", "audio")


def write_wav(path, x, sr=SR):
    data = np.clip(x, -1.0, 1.0)
    pcm = (data * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1 if data.ndim == 1 else data.shape[1])
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def seed_of(name):
    return zlib.crc32(name.encode())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="comma-separated names")
    args = ap.parse_args()
    only = set(filter(None, args.only.split(",")))
    os.makedirs(os.path.join(OUT, "sfx"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "music"), exist_ok=True)
    for name, (fn, level) in sfx.SOUNDS.items():
        if only and name not in only:
            continue
        x = fn(np.random.default_rng(seed_of(name)))
        x = filt(x, "high", 30.0)  # no DC or sub rumble
        x = fade(x, 0.0005, min(0.03, len(x) / SR * 0.2))
        x = x / max(1e-9, np.max(np.abs(x))) * level
        write_wav(os.path.join(OUT, "sfx", name + ".wav"), x)
        print("sfx   %-16s %.2f s" % (name, len(x) / SR))
    for name, fn in music.TRACKS.items():
        if only and name not in only:
            continue
        x = fn(np.random.default_rng(seed_of(name)))
        x = np.stack([filt(x[:, c], "high", 25.0) for c in range(2)], axis=1)
        dst = os.path.join(OUT, "music", name + ".ogg")
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, name + ".wav")
            write_wav(src, x)
            r = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-c:a", "libvorbis", "-q:a", "4",
                                "-map_metadata", "-1", "-fflags", "+bitexact", dst])
            if r.returncode != 0:
                sys.exit("ffmpeg failed for %s" % name)
        print("music %-16s %.1f s" % (name, len(x) / SR))


if __name__ == "__main__":
    main()
