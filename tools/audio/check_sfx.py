#!/usr/bin/env python3
"""Verify the generated SFX palette in assets/audio/sfx.

Checks, per cue: file exists and decodes, peak <= -3 dBFS, duration limit,
no leading/trailing silence over 20 ms. Then: total size, and that the three
alarm-like cues (chip_fail, overheat_warn, explosion) are spectrally
distinguishable. Exit code 1 on any failure.

Usage (from the project root): python3 tools/audio/check_sfx.py [--dir DIR]
"""
import argparse
import subprocess
import sys
from itertools import combinations
from pathlib import Path

import numpy as np

SR = 44100
ROOT = Path(__file__).resolve().parents[2]
CUES = ["place", "remove", "place_rejected", "deliver", "craft_done", "sell",
        "order_complete", "chip_ok", "chip_none", "chip_fail", "blocked",
        "overheat_warn", "explosion", "ui_click"]
MAX_PEAK_DB = -3.0
MAX_DURATION_S = 1.2
MAX_DURATION_OVERRIDE = {"explosion": 1.0}
MAX_EDGE_SILENCE_S = 0.020
SILENCE_LEVEL = 10 ** (-50 / 20)  # -50 dBFS
MAX_TOTAL_BYTES = 300 * 1024
DISTINCT_CUES = ["chip_fail", "overheat_warn", "explosion"]
MIN_RATIO = 1.5  # "clear separation" between two values (ratio of larger/smaller)
BANDS = [(0, 300), (300, 1000), (1000, 3000), (3000, 22050)]


def decode(path):
    cmd = ["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"]
    raw = subprocess.run(cmd, check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype="<f4").astype(np.float64)


def edge_silence(x):
    loud = np.nonzero(np.abs(x) > SILENCE_LEVEL)[0]
    if len(loud) == 0:
        return len(x) / SR, len(x) / SR
    return loud[0] / SR, (len(x) - 1 - loud[-1]) / SR


def spectrum(x):
    mag = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    freq = np.fft.rfftfreq(len(x), 1 / SR)
    centroid = float((freq * mag).sum() / mag.sum())
    energy = [float((mag[(freq >= lo) & (freq < hi)] ** 2).sum()) for lo, hi in BANDS]
    dominant = BANDS[int(np.argmax(energy))]
    return centroid, dominant


def ratio(a, b):
    return max(a, b) / max(min(a, b), 1e-9)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dir", type=Path, default=ROOT / "assets" / "audio" / "sfx")
    args = ap.parse_args()

    failures = []
    stats = {}
    total = 0
    print(f"{'cue':15s} {'bytes':>7s} {'dur ms':>7s} {'peak dB':>8s} {'lead ms':>8s} {'trail ms':>9s} {'centroid':>9s}  dominant band  result")
    for cue in CUES:
        path = args.dir / f"{cue}.ogg"
        if not path.is_file():
            failures.append(f"{cue}: missing {path}")
            print(f"{cue:15s} MISSING")
            continue
        try:
            x = decode(path)
        except subprocess.CalledProcessError as e:
            failures.append(f"{cue}: does not decode ({e})")
            print(f"{cue:15s} DECODE ERROR")
            continue
        size = path.stat().st_size
        total += size
        dur = len(x) / SR
        peak = float(np.abs(x).max()) if len(x) else 0.0
        peak_db = 20 * np.log10(peak) if peak > 0 else -np.inf
        lead, trail = edge_silence(x)
        centroid, band = spectrum(x)
        stats[cue] = (centroid, dur, band)
        problems = []
        if dur <= 0:
            problems.append("empty")
        if dur >= MAX_DURATION_OVERRIDE.get(cue, MAX_DURATION_S):
            problems.append(f"duration >= {MAX_DURATION_OVERRIDE.get(cue, MAX_DURATION_S)} s")
        if peak_db > MAX_PEAK_DB:
            problems.append(f"peak {peak_db:.1f} dBFS > {MAX_PEAK_DB}")
        if lead > MAX_EDGE_SILENCE_S:
            problems.append(f"leading silence {lead * 1000:.0f} ms")
        if trail > MAX_EDGE_SILENCE_S:
            problems.append(f"trailing silence {trail * 1000:.0f} ms")
        failures += [f"{cue}: {p}" for p in problems]
        print(f"{cue:15s} {size:7d} {dur * 1000:7.0f} {peak_db:8.1f} {lead * 1000:8.1f} {trail * 1000:9.1f} {centroid:8.0f}Hz  "
              f"{band[0]:>5d}-{band[1]:<5d}  {'ok' if not problems else 'FAIL'}")

    print(f"\ntotal size: {total} bytes ({total / 1024:.1f} KB), limit {MAX_TOTAL_BYTES // 1024} KB")
    if total > MAX_TOTAL_BYTES:
        failures.append(f"total size {total} > {MAX_TOTAL_BYTES}")

    print(f"\nDistinguishability of {', '.join(DISTINCT_CUES)} "
          f"(pair passes when spectral centroid differs by >= {MIN_RATIO}x; duration ratio shown for information)")
    if all(c in stats for c in DISTINCT_CUES):
        for a, b in combinations(DISTINCT_CUES, 2):
            ca, da, ba = stats[a]
            cb, db, bb = stats[b]
            cr, dr = ratio(ca, cb), ratio(da, db)
            ok = cr >= MIN_RATIO
            print(f"  {a} vs {b}: centroid {ca:.0f} Hz vs {cb:.0f} Hz (x{cr:.2f}), "
                  f"duration {da * 1000:.0f} ms vs {db * 1000:.0f} ms (x{dr:.2f}), "
                  f"dominant band {ba} vs {bb} -> {'ok' if ok else 'FAIL'}")
            if not ok:
                failures.append(f"{a} vs {b}: centroid ratio {cr:.2f} < {MIN_RATIO}")
    else:
        failures.append("distinguishability check skipped: cue missing")

    if failures:
        print("\nFAILED:")
        for f in failures:
            print("  -", f)
        return 1
    print("\nAll checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
