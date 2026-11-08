# Audio credits and license

All sound effects in `assets/audio/sfx/` are **original work of this project**.
They are synthesized from scratch (sine/square oscillators, filtered noise,
envelopes) by `tools/audio/generate_sfx.py`. No sample, recording, library or
third-party material is used, nothing was downloaded or purchased, so there is
no attribution requirement. They are released under the same license as the
rest of the Promptorio project.

## Files

Format: Ogg Vorbis, mono, 44.1 kHz. Peak levels are set per cue (the
frequent cues are quieter); every file peaks at or below -3 dBFS. Lengths
are measured on the shipped files.

| File | Cue | How it is made |
|---|---|---|
| `place.ogg` | machine placed | low sine thunk (190 to 90 Hz sweep) + tiny filtered-noise click |
| `remove.ogg` | machine removed | descending low sine (150 to 55 Hz) + soft noise scuff |
| `place_rejected.ogg` | placement refused | two dull low ticks (140 Hz), not a buzz |
| `deliver.ogg` | item handed machine to machine | very quiet 620 Hz tick (-18 dBFS); the caller must rate-limit it |
| `craft_done.ogg` | a machine finished a unit | short rising band-limited square blip; the caller varies the pitch per machine type |
| `sell.ogg` | item sold | coin chirp: 1320 Hz then 1980 Hz with a shimmer overtone |
| `order_complete.ogg` | order fulfilled | three rising square notes G4-B4-D5; the only musical cue |
| `chip_ok.ogg` | chip answered with an action | soft up-blip (520 to 780 Hz) |
| `chip_none.ogg` | chip answered with no action | neutral 300 Hz tick, quiet |
| `chip_fail.ogg` | chip request failed | low descending two-tone (330 Hz, 220 Hz), low-passed square |
| `blocked.ogg` | machine blocked (output full / input empty) | single muted knock, low-passed thunk |
| `overheat_warn.ogg` | machine overheating | two identical high pulses around 1.5 kHz with an octave overtone |
| `explosion.ogg` | machine exploded | noise burst falling to a rumble + 110 to 32 Hz sub thump |
| `ui_click.ogg` | UI click | 900 Hz tick with a noise transient, very short |

`chip_fail` (low, two falling pitched tones), `overheat_warn` (high, two equal
pulses) and `explosion` (broadband noise with a sub thump) are kept apart in
pitch, rhythm and timbre; see `tools/audio/reports/`.

## Regenerate and verify

```
python3 tools/audio/generate_sfx.py            # needs Python 3, numpy, ffmpeg (libvorbis)
python3 tools/audio/check_sfx.py --determinism # length, peak, clipping, silence, size, byte-identical WAVs
godot --headless --import                      # (re)creates the .import files
```

The generator uses a fixed per-cue seed, so the intermediate WAVs are
byte-identical on every run (`check_sfx.py --determinism` verifies this). The
`.ogg` bytes depend on the ffmpeg/libvorbis version. The WAVs are written to
`tools/audio/.build/` (git-ignored). To tweak a sound, edit its `cue_*`
function in `generate_sfx.py`, regenerate and commit the new `.ogg`.
