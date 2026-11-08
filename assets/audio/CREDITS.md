# Sound effects

Original work of this project, synthesized from scratch by `tools/audio/generate_sfx.py` (numpy: square / triangle / sine oscillators and filtered noise, with envelopes and one-pole low-pass filters). No recorded, downloaded or third-party material is used. License: original work of this project, no attribution required.

Regenerate (needs Python 3, numpy and ffmpeg with libvorbis), from the project root:

```
python3 tools/audio/generate_sfx.py     # writes assets/audio/sfx/*.ogg
python3 tools/audio/check_sfx.py        # peak, duration, edge silence, size, spectral checks
```

The generator uses fixed RNG seeds and writes mono 44.1 kHz 16-bit WAVs (byte-identical between runs), then encodes them with ffmpeg/libvorbis (`-q:a 3`, bitexact mode). Every cue is under 1.2 s (explosion under 1.0 s) with a peak between -14 and -6 dBFS; frequent or background cues are baked quieter. Edit the recipes in `generate_sfx.py`, never the `.ogg` files.

| File | Used for | Recipe |
|------|----------|--------|
| `sfx/place.ogg` | machine / conveyor placed | sine + triangle thump gliding 330 to 130 Hz, low-passed at 1.5 kHz, plus a faint noise click |
| `sfx/remove.ogg` | machine removed | same thump gliding down 440 to 110 Hz, longer decay, a little low-passed noise |
| `sfx/place_rejected.ogg` | placement refused | two dull triangle ticks (260 Hz then 200 Hz), low-passed at 1 kHz |
| `sfx/deliver.ogg` | item delivered | 720 Hz sine tick of 25 ms plus a tiny noise click; very quiet (-14 dBFS) |
| `sfx/craft_done.ogg` | craft finished | two quick 25 % duty square blips (784 then 1175 Hz), low-passed at 4.2 kHz |
| `sfx/sell.ogg` | item sold | coin chirp: square 988 then 1319 Hz, with a triangle shimmer at 2637 Hz, low-passed at 4.8 kHz |
| `sfx/order_complete.ogg` | order completed | the only musical cue: three rising notes C5, E5, G5 (square + triangle), last one held, low-passed at 3.6 kHz |
| `sfx/chip_ok.ogg` | chip action applied | soft triangle up-blip, 440 then 587 Hz |
| `sfx/chip_none.ogg` | chip chose no action | neutral triangle tick at 280 Hz, 50 ms |
| `sfx/chip_fail.ogg` | chip failed | low square two-tone descending 220 then 155 Hz, low-passed at 1.1 kHz |
| `sfx/blocked.ogg` | machine blocked | single muted knock: sine glide 230 to 150 Hz plus dark noise, low-passed at 900 Hz |
| `sfx/overheat_warn.ogg` | machine overheating | two bright pulses of a 1175 Hz square with an octave-up layer, low-passed at 6.5 kHz (higher, repeated and brighter than `chip_fail`) |
| `sfx/explosion.ogg` | machine exploded | noise burst through a low-pass sweeping 3.8 kHz down to 250 Hz, plus a sine thump gliding 130 to 40 Hz; 0.9 s |
| `sfx/ui_click.ogg` | UI button | 900 Hz sine tick of 22 ms plus a tiny noise click |
