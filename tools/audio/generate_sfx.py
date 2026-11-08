#!/usr/bin/env python3
"""Generate the Promptorio sound-effect palette (original, synthesized).

Pipeline: numpy synthesis (fixed seeds) -> mono 44.1 kHz 16-bit WAV (stdlib
`wave`) -> ffmpeg/libvorbis -> assets/audio/sfx/<cue>.ogg.

Deterministic: every cue seeds its own RNG from a fixed constant, so the WAVs
are byte-identical between runs. The Ogg muxer is run in bitexact mode (fixed
stream serial, no encoder tag) so the .ogg files are normally identical too.

Usage (from the project root):
    python3 tools/audio/generate_sfx.py [--out assets/audio/sfx] [--wav-dir DIR]
"""
import argparse
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

SR = 44100
SEED = 20260811
ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "assets" / "audio" / "sfx"

# Edge trim threshold (-50 dBFS) and end fade, so cues carry no dead air.
TRIM_LEVEL = 10 ** (-50 / 20)
END_FADE_S = 0.006


# ---------------------------------------------------------------- primitives
def _rng(name):
    return np.random.default_rng([SEED, *name.encode()])


def _time(dur):
    return np.arange(int(round(dur * SR))) / SR


def _phase(freq, n):
    freq = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,))
    return np.cumsum(freq) / SR


def sine(freq, n):
    return np.sin(2 * np.pi * _phase(freq, n))


def tri(freq, n):
    return 2 * np.abs(2 * (_phase(freq, n) % 1.0) - 1) - 1


def square(freq, n, duty=0.5):
    return np.where(_phase(freq, n) % 1.0 < duty, 1.0, -1.0)


def sweep(f0, f1, dur, curve=4.0):
    """Exponential-ish glide from f0 to f1 (curve > 0 moves fast first)."""
    t = _time(dur)
    k = 1 - np.exp(-curve * t / dur)
    k /= k[-1]
    return f0 + (f1 - f0) * k


def env(n, attack=0.003, tau=0.05):
    t = np.arange(n) / SR
    return np.minimum(t / max(attack, 1 / SR), 1.0) * np.exp(-t / tau)


def lowpass(x, cutoff, poles=2):
    """One-pole low-pass cascade; cutoff may be a scalar or per-sample array."""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=np.float64), x.shape)
    a = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = x.astype(np.float64)
    for _ in range(poles):
        out = np.empty_like(y)
        acc = 0.0
        for i in range(len(y)):
            acc += a[i] * (y[i] - acc)
            out[i] = acc
        y = out
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff, poles=1)


def mix(length, *parts):
    """Sum (start_seconds, signal) parts into a buffer of `length` seconds."""
    out = np.zeros(int(round(length * SR)))
    for start, sig in parts:
        i = int(round(start * SR))
        j = min(i + len(sig), len(out))
        out[i:j] += sig[: j - i]
    return out


def over(base, extra):
    """Add a shorter signal onto the start of `base` (length of base is kept)."""
    out = base.copy()
    m = min(len(base), len(extra))
    out[:m] += extra[:m]
    return out


def note(freq_hz, dur, shape="square", tau=0.08, attack=0.004, duty=0.5, **kw):
    n = int(round(dur * SR))
    osc = {"square": lambda: square(freq_hz, n, duty),
           "tri": lambda: tri(freq_hz, n),
           "sine": lambda: sine(freq_hz, n)}[shape]()
    return osc * env(n, attack, tau)


def click(rng, dur=0.008, cutoff=3000.0, tau=0.002):
    """Tiny filtered-noise transient."""
    n = int(round(dur * SR))
    return lowpass(highpass(rng.standard_normal(n), 400.0), cutoff, poles=1) * env(n, 0.0005, tau)


# ---------------------------------------------------------------------- cues
# Each recipe returns a float signal; finish() trims, fades and normalizes.
def place(rng):
    n = int(0.2 * SR)
    f = sweep(330, 130, 0.2)
    body = (sine(f, n) + 0.5 * tri(f, n)) * env(n, 0.004, 0.045)
    return mix(0.2, (0, lowpass(body, 1500)), (0, 0.35 * click(rng, 0.007, 2800)))


def remove(rng):
    n = int(0.26 * SR)
    f = sweep(440, 110, 0.26, curve=3.0)
    body = (sine(f, n) + 0.5 * tri(f, n)) * env(n, 0.004, 0.07)
    return lowpass(body, 1400) + 0.12 * lowpass(rng.standard_normal(n), 600) * env(n, 0.002, 0.03)


def place_rejected(rng):
    def tick(freq, tau):
        n = int(0.06 * SR)
        return over(lowpass(tri(freq, n) * env(n, 0.003, tau), 1000), 0.15 * click(rng, 0.006, 1500))
    return mix(0.2, (0, tick(260, 0.014)), (0.095, tick(200, 0.016)))


def deliver(rng):
    n = int(0.03 * SR)
    return over(lowpass(sine(720, n) * env(n, 0.001, 0.006), 2500, poles=1), 0.3 * click(rng, 0.004, 2500, 0.001))


def craft_done(rng):
    a = note(784, 0.06, "square", tau=0.05, duty=0.25)
    b = note(1175, 0.12, "square", tau=0.06, duty=0.25)
    return lowpass(mix(0.18, (0, a), (0.055, b)), 4200)


def sell(rng):
    a = note(988, 0.07, "square", tau=0.05, duty=0.5)
    b = note(1319, 0.28, "square", tau=0.09, duty=0.5)
    shimmer = note(2637, 0.28, "tri", tau=0.05) * 0.2
    return lowpass(mix(0.34, (0, a), (0.06, b), (0.06, shimmer)), 4800)


def order_complete(rng):
    parts = []
    for i, f in enumerate((523.25, 659.25, 783.99)):
        last = i == 2
        dur = 0.34 if last else 0.12
        tau = 0.13 if last else 0.07
        parts.append((0.115 * i, note(f, dur, "square", tau=tau) * 0.6 + note(f, dur, "tri", tau=tau)))
    return lowpass(mix(0.115 * 2 + 0.34, *parts), 3600)


def chip_ok(rng):
    a = note(440, 0.05, "tri", tau=0.04)
    b = note(587.33, 0.1, "tri", tau=0.05)
    return lowpass(mix(0.15, (0, a), (0.05, b)), 3000)


def chip_none(rng):
    n = int(0.06 * SR)
    return over(lowpass(tri(280, n) * env(n, 0.003, 0.012), 1200), 0.15 * click(rng, 0.005, 1200))


def chip_fail(rng):
    a = note(220, 0.14, "square", tau=0.12)
    b = note(155.56, 0.2, "square", tau=0.11)
    return lowpass(mix(0.34, (0, a), (0.13, b)), 1100)


def blocked(rng):
    n = int(0.15 * SR)
    f = sweep(230, 150, 0.15)
    return lowpass(sine(f, n) * env(n, 0.004, 0.028), 900) + 0.2 * lowpass(rng.standard_normal(n), 450) * env(n, 0.002, 0.012)


def overheat_warn(rng):
    pulse = lowpass(note(1175, 0.085, "square", tau=0.2, attack=0.004)
                    + 0.35 * note(2350, 0.085, "square", tau=0.2, attack=0.004, duty=0.25), 6500)
    pulse *= np.minimum(1.0, np.linspace(1, 0, len(pulse)) * 6)  # soft release
    return mix(0.27, (0, pulse), (0.15, pulse))


def explosion(rng):
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    cutoff = 250 + 3600 * np.exp(-t / 0.12)
    noise = lowpass(rng.standard_normal(n), cutoff, poles=2) * env(n, 0.004, 0.17)
    thump = sine(sweep(130, 40, 0.9, curve=5.0), n) * env(n, 0.006, 0.22)
    return noise * 0.8 + thump * 1.2


def ui_click(rng):
    n = int(0.025 * SR)
    return over(lowpass(sine(900, n) * env(n, 0.001, 0.005), 3000, poles=1), 0.25 * click(rng, 0.004, 3000, 0.001))


# name -> (recipe, peak dBFS). Most cues sit at -6; frequent, background-ish
# cues are baked quieter so the palette has a built-in hierarchy.
CUES = {
    "place": (place, -6),
    "remove": (remove, -6),
    "place_rejected": (place_rejected, -8),
    "deliver": (deliver, -14),
    "craft_done": (craft_done, -8),
    "sell": (sell, -7),
    "order_complete": (order_complete, -6),
    "chip_ok": (chip_ok, -9),
    "chip_none": (chip_none, -10),
    "chip_fail": (chip_fail, -7),
    "blocked": (blocked, -8),
    "overheat_warn": (overheat_warn, -6),
    "explosion": (explosion, -6),
    "ui_click": (ui_click, -10),
}


def finish(sig, peak_db):
    above = np.nonzero(np.abs(sig) > np.abs(sig).max() * TRIM_LEVEL)[0]
    sig = sig[above[0]: above[-1] + 1].copy()
    nf = min(int(END_FADE_S * SR), len(sig))
    sig[-nf:] *= np.linspace(1, 0, nf) ** 2
    sig = sig - sig.mean()
    sig *= 10 ** (peak_db / 20) / np.abs(sig).max()
    return sig


def write_wav(path, sig):
    pcm = np.round(sig * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def encode(wav, ogg):
    cmd = ["ffmpeg", "-y", "-v", "error", "-i", str(wav), "-map_metadata", "-1",
           "-fflags", "+bitexact", "-flags:a", "+bitexact",
           "-c:a", "libvorbis", "-q:a", "3", "-ar", str(SR), "-ac", "1", str(ogg)]
    subprocess.run(cmd, check=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT, help="directory for the .ogg files")
    ap.add_argument("--wav-dir", type=Path, help="keep the intermediate WAVs here (default: temp dir)")
    args = ap.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    tmp = None
    if args.wav_dir:
        wav_dir = args.wav_dir
        wav_dir.mkdir(parents=True, exist_ok=True)
    else:
        tmp = tempfile.TemporaryDirectory()
        wav_dir = Path(tmp.name)

    for name, (recipe, peak_db) in CUES.items():
        sig = finish(recipe(_rng(name)), peak_db)
        wav = wav_dir / f"{name}.wav"
        write_wav(wav, sig)
        encode(wav, args.out / f"{name}.ogg")
        print(f"{name:15s} {len(sig) / SR * 1000:6.0f} ms  peak {peak_db:4d} dBFS")


if __name__ == "__main__":
    sys.exit(main())
