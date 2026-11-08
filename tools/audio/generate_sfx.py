#!/usr/bin/env python3
"""Synthesize the Promptorio SFX palette (original work, no third-party audio).

Usage: python3 tools/audio/generate_sfx.py [--out assets/audio/sfx] [--keep-wav DIR]

Every cue is built from numpy oscillators/noise with a fixed seed, written as
a 16-bit mono 44.1 kHz WAV (byte-identical between runs), then encoded to
.ogg with ffmpeg (libvorbis). Only the .ogg files are shipped; WAVs go to
--keep-wav (default tools/audio/.build, git-ignored).
"""
import argparse
import hashlib
import pathlib
import subprocess
import sys
import wave

import numpy as np

SR = 44100
ROOT = pathlib.Path(__file__).resolve().parents[2]


def t_axis(dur):
    return np.arange(int(round(dur * SR))) / SR


def env(n, attack=0.002, decay=0.05, curve=4.0):
    """Fast linear attack then exponential decay, ending at exactly zero."""
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    d = np.exp(-curve * t / max(decay, 1e-4))
    e = a * d
    fade = min(n, int(0.004 * SR))  # 4 ms tail fade avoids end clicks
    e[n - fade:] *= np.linspace(1, 0, fade)
    return e


def sine(freq, dur, phase=0.0):
    """freq may be a scalar or an array (Hz over time) for pitch sweeps."""
    t = t_axis(dur)
    f = np.full(len(t), freq, dtype=float) if np.isscalar(freq) else freq
    return np.sin(2 * np.pi * np.cumsum(f) / SR + phase)


def square(freq, dur, duty=0.5):
    """Band-limited-ish pixel square (sum of a few odd harmonics, soft)."""
    t = t_axis(dur)
    f = np.full(len(t), freq, dtype=float) if np.isscalar(freq) else freq
    ph = 2 * np.pi * np.cumsum(f) / SR
    return (np.sin(ph) + np.sin(3 * ph) / 3 + np.sin(5 * ph) / 5) * 0.8


def sweep(f0, f1, dur, curve=3.0):
    t = t_axis(dur)
    k = np.exp(-curve * t / dur)
    return f1 + (f0 - f1) * k


def lowpass(x, cutoff):
    """One-pole lowpass, run twice for a softer slope."""
    a = np.exp(-2 * np.pi * cutoff / SR)
    for _ in range(2):
        y = np.empty_like(x)
        s = 0.0
        for i, v in enumerate(x):
            s = (1 - a) * v + a * s
            y[i] = s
        x = y
    return x


def noise(rng, dur):
    return rng.uniform(-1, 1, int(round(dur * SR)))


def place_at(buf, sig, start):
    i = int(round(start * SR))
    end = min(len(buf), i + len(sig))
    buf[i:end] += sig[: end - i]


def mix(total, parts):
    buf = np.zeros(int(round(total * SR)))
    for start, sig in parts:
        place_at(buf, sig, start)
    return buf


def tone(f, dur, decay, wave_fn=sine, attack=0.002, curve=4.0):
    s = wave_fn(f, dur)
    return s * env(len(s), attack, decay, curve)


def thunk(rng, f0, f1, dur, click=0.3):
    """Soft low body with a short filtered noise click."""
    body = tone(sweep(f0, f1, dur, 6.0), dur, dur * 0.9, attack=0.003)
    c = lowpass(noise(rng, 0.012), 2500) * env(int(0.012 * SR), 0.0005, 0.006)
    out = body.copy()
    out[: len(c)] += click * c
    return out


# --- cue definitions: each returns (samples, target_peak_dBFS) --------------

def cue_place(rng):
    return thunk(rng, 190, 90, 0.16, click=0.35), -6


def cue_remove(rng):
    body = tone(sweep(150, 55, 0.2, 3.0), 0.2, 0.09, attack=0.004)
    scuff = lowpass(noise(rng, 0.06), 1800) * env(int(0.06 * SR), 0.004, 0.03)
    return mix(0.2, [(0, body), (0, 0.25 * scuff)]), -7


def cue_place_rejected(rng):
    a = thunk(rng, 140, 120, 0.07, click=0.2) * 0.9
    return mix(0.2, [(0, a), (0.095, a * 0.8)]), -8


def cue_deliver(rng):
    t = tone(620, 0.04, 0.012, attack=0.001) + 0.3 * tone(1240, 0.04, 0.008, attack=0.001)
    return t, -18


def cue_craft_done(rng):
    # Short bright blip; the caller pitch-jitters it per machine type.
    a = tone(sweep(680, 1020, 0.1, 6.0), 0.1, 0.05, wave_fn=square, attack=0.002)
    return lowpass(a, 4200), -8


def cue_sell(rng):
    a = tone(1320, 0.07, 0.035, attack=0.001)
    b = tone(1980, 0.16, 0.08, attack=0.001) + 0.25 * tone(3960, 0.16, 0.04, attack=0.001)
    return mix(0.23, [(0, a), (0.06, b)]), -8


def cue_order_complete(rng):
    notes = [(392.00, 0.0), (493.88, 0.11), (587.33, 0.22)]  # G4 B4 D5
    parts = []
    for f, st in notes:
        d = 0.16 if st < 0.22 else 0.4
        n = tone(f, d, d * 0.5, wave_fn=square, attack=0.003) * 0.7
        parts.append((st, lowpass(n, 3500)))
    return mix(0.62, parts), -7


def cue_chip_ok(rng):
    a = tone(sweep(520, 780, 0.09, 8.0), 0.09, 0.045, attack=0.003)
    return a + 0.2 * tone(1560, 0.09, 0.02, attack=0.002), -10


def cue_chip_none(rng):
    return tone(300, 0.06, 0.025, attack=0.002) * 0.9, -14


def cue_chip_fail(rng):
    a = tone(330, 0.15, 0.1, wave_fn=square, attack=0.004)
    b = tone(220, 0.26, 0.15, wave_fn=square, attack=0.004)
    return lowpass(mix(0.42, [(0, a), (0.14, b)]), 1500), -7


def cue_blocked(rng):
    k = thunk(rng, 120, 85, 0.14, click=0.15)
    return lowpass(k, 700), -11


def cue_overheat_warn(rng):
    # Two high pitched pulses (hi-lo at 1 kHz range), well above chip_fail.
    p = tone(1480, 0.11, 0.07, attack=0.002) + 0.35 * tone(2960, 0.11, 0.04, attack=0.002)
    q = p * 1.0
    return mix(0.34, [(0, p), (0.17, q)]), -6


def cue_explosion(rng):
    n = lowpass(noise(rng, 0.8), 2600)
    # Cutoff falls over time: crossfade a darker copy for a rumble tail.
    dark = lowpass(noise(rng, 0.8), 450)
    t = np.linspace(0, 1, len(n))
    nz = n * np.exp(-6 * t) * 0.8 + dark * np.exp(-2.0 * t)
    thump = tone(sweep(110, 32, 0.6, 3.0), 0.6, 0.55, attack=0.004)
    sig = nz * env(len(nz), 0.002, 1.1, 3.5) + 1.2 * np.pad(thump, (0, len(nz) - len(thump)))
    return sig, -6


def cue_ui_click(rng):
    a = tone(900, 0.03, 0.016, attack=0.0008)
    c = lowpass(noise(rng, 0.01), 4000) * env(int(0.01 * SR), 0.0003, 0.004)
    a[: len(c)] += 0.3 * c
    return a, -12


CUES = [
    "place", "remove", "place_rejected", "deliver", "craft_done", "sell",
    "order_complete", "chip_ok", "chip_none", "chip_fail", "blocked",
    "overheat_warn", "explosion", "ui_click",
]


def trim_tail(sig, floor_db=-40.0, keep=0.002):
    """Cut the inaudible decay tail (below floor_db) and fade the last few ms."""
    loud = np.where(np.abs(sig) > 10 ** (floor_db / 20))[0]
    end = min(len(sig), (loud[-1] if len(loud) else 0) + int(keep * SR))
    sig = sig[:end].copy()
    fade = min(len(sig), int(0.004 * SR))
    sig[-fade:] *= np.linspace(1, 0, fade)
    return sig


def render(name, seed):
    rng = np.random.RandomState(seed)
    sig, peak_db = globals()["cue_" + name](rng)
    sig = sig - sig.mean()
    sig = sig / np.max(np.abs(sig)) * 10 ** (peak_db / 20)
    sig = trim_tail(sig)
    return np.round(sig * 32767).astype("<i2")


def write_wav(path, pcm):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "assets/audio/sfx"))
    ap.add_argument("--keep-wav", default=str(ROOT / "tools/audio/.build"))
    args = ap.parse_args()
    out, wavs = pathlib.Path(args.out), pathlib.Path(args.keep_wav)
    out.mkdir(parents=True, exist_ok=True)
    wavs.mkdir(parents=True, exist_ok=True)
    for name in CUES:
        seed = int(hashlib.sha256(name.encode()).hexdigest()[:8], 16)
        pcm = render(name, seed)
        wav = wavs / f"{name}.wav"
        write_wav(wav, pcm)
        ogg = out / f"{name}.ogg"
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis",
             "-q:a", "5", "-ac", "1", "-fflags", "+bitexact", "-flags:a", "+bitexact", str(ogg)],
            check=True)
        print(f"{name}: {len(pcm) / SR * 1000:.0f} ms, {ogg.stat().st_size} B")


if __name__ == "__main__":
    sys.exit(main())
