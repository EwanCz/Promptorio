#!/usr/bin/env python3
"""Verify the SFX palette. Usage: python3 tools/audio/check_sfx.py [--dir assets/audio/sfx]
       [--determinism] [--spectrogram out.png]

Checks every expected cue (decoded from the shipped .ogg): exists, <= 1.2 s,
peak <= -3 dBFS, no clipping, no leading/trailing silence > 20 ms, total size
< 300 KB. --determinism renders the WAVs twice and compares bytes.
--spectrogram writes a comparison image of chip_fail / overheat_warn / explosion
(needs matplotlib) and prints a feature table either way.
"""
import argparse
import importlib.util
import pathlib
import subprocess
import sys
import tempfile

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[2]
SR = 44100
SILENCE = 10 ** (-40 / 20)  # below this counts as silence
MAX_LEN, MAX_SILENCE, PEAK_LIMIT_DB, MAX_TOTAL = 1.2, 0.020, -3.0, 300 * 1024


def load_gen():
    spec = importlib.util.spec_from_file_location("generate_sfx", ROOT / "tools/audio/generate_sfx.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def decode(path):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(path), "-f", "f32le",
                          "-ac", "1", "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype="<f4")
    # ffmpeg decodes the whole last Vorbis block; players (Godot) stop at the
    # stream's granule position, which ffprobe reports as duration_ts.
    n = int(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=duration_ts", "-of",
                            "csv=p=0", str(path)], capture_output=True, check=True).stdout.split()[0])
    return x[:n]


def features(x):
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return {"dur_ms": len(x) / SR * 1000, "centroid_hz": float((spec * f).sum() / spec.sum()),
            "peak_hz": float(f[spec.argmax()])}


def spectrogram(d, names, out):
    """Waveform over spectrogram per cue, side by side (ffmpeg only, no matplotlib)."""
    tmp = pathlib.Path(tempfile.mkdtemp())
    cols = []
    for n in names:
        col = tmp / f"{n}.png"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(d / f"{n}.ogg"), "-filter_complex",
                        "[0:a]aformat=channel_layouts=mono,asplit[a][b];"
                        "[a]showwavespic=s=480x120:colors=white[w];"
                        "[b]showspectrumpic=s=480x300:legend=0:scale=log:fscale=lin[s];"
                        "[w][s]vstack[o]", "-map", "[o]", "-frames:v", "1", str(col)], check=True)
        cols.append(col)
    cmd = ["ffmpeg", "-y", "-loglevel", "error"]
    for c in cols:
        cmd += ["-i", str(c)]
    cmd += ["-filter_complex", "".join(f"[{i}:v]" for i in range(len(cols))) + f"hstack=inputs={len(cols)}",
            str(out)]
    subprocess.run(cmd, check=True)
    print("spectrogram (left to right: " + ", ".join(names) + "):", out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=str(ROOT / "assets/audio/sfx"))
    ap.add_argument("--determinism", action="store_true")
    ap.add_argument("--spectrogram")
    args = ap.parse_args()
    gen = load_gen()
    d = pathlib.Path(args.dir)
    errors, total, sigs = [], 0, {}
    for name in gen.CUES:
        p = d / f"{name}.ogg"
        if not p.exists():
            errors.append(f"{name}: missing {p}")
            continue
        total += p.stat().st_size
        x = decode(p)
        sigs[name] = x
        peak = np.abs(x).max()
        peak_db = 20 * np.log10(max(peak, 1e-9))
        loud = np.where(np.abs(x) > SILENCE)[0]
        lead = loud[0] / SR if len(loud) else 9
        trail = (len(x) - 1 - loud[-1]) / SR if len(loud) else 9
        if len(x) / SR > MAX_LEN:
            errors.append(f"{name}: {len(x) / SR:.2f}s > {MAX_LEN}s")
        if peak_db > PEAK_LIMIT_DB:
            errors.append(f"{name}: peak {peak_db:.1f} dBFS > {PEAK_LIMIT_DB}")
        if peak >= 0.999:
            errors.append(f"{name}: clipping")
        if lead > MAX_SILENCE or trail > MAX_SILENCE:
            errors.append(f"{name}: silence lead {lead * 1000:.0f} ms / trail {trail * 1000:.0f} ms > 20 ms")
        print(f"{name:15s} {len(x) / SR * 1000:5.0f} ms  peak {peak_db:6.1f} dBFS  "
              f"lead {lead * 1000:4.1f} ms trail {trail * 1000:4.1f} ms  {p.stat().st_size:6d} B")
    if total > MAX_TOTAL:
        errors.append(f"total size {total} B > {MAX_TOTAL}")
    print(f"total {total} B")

    if args.determinism:
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            for tmp in (a, b):
                for name in gen.CUES:
                    seed = int(gen.hashlib.sha256(name.encode()).hexdigest()[:8], 16)
                    gen.write_wav(pathlib.Path(tmp) / f"{name}.wav", gen.render(name, seed))
            for name in gen.CUES:
                if (pathlib.Path(a) / f"{name}.wav").read_bytes() != (pathlib.Path(b) / f"{name}.wav").read_bytes():
                    errors.append(f"{name}: WAV not deterministic")
        print("determinism: checked")

    trio = [n for n in ("chip_fail", "overheat_warn", "explosion") if n in sigs]
    print("\ndistinguishability (spectral features):")
    for n in trio:
        f = features(sigs[n])
        print(f"  {n:14s} dur {f['dur_ms']:4.0f} ms  centroid {f['centroid_hz']:6.0f} Hz  peak bin {f['peak_hz']:6.0f} Hz")
    if args.spectrogram and trio:
        spectrogram(d, trio, pathlib.Path(args.spectrogram))

    for e in errors:
        print("FAIL", e)
    print("OK" if not errors else f"{len(errors)} problem(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
