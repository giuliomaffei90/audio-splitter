# Audio Splitter

A macOS app that cuts one audio file into the separate sounds inside it, using the silences between
them as the cut points. Drag a file onto the window (or choose **File › Open…**, ⌘O) and every
non-silent stretch becomes its own clip:
audition them, drop the ones you don't want, export the rest as **WAV**.

It was written for sample libraries — a single take holding twenty dice rolls, footsteps or door
slams, that has to end up as twenty files.

There are no dependencies, and nothing to install alongside it: reading and writing audio is
AVFoundation, the envelope analysis is Accelerate. No ffmpeg.

## How it works

The file is read once into memory and reduced to an envelope — one RMS value and one peak value per
10 ms window, taken from whichever channel is loudest, so a sound that only appears on one side is
never treated as silence.

A stretch is silence when its level stays under **Threshold** for at least **Minimum silence**.
Everything between two silences is a clip. Each clip then grows by **Margin** on both sides so it
doesn't start and end on an abrupt edge, and anything shorter than **Minimum clip** is dropped.

The margin never lets two clips overlap: it is capped at half the silence next to it, whatever value
the slider is set to.

| Control | Default | What it does |
|---|---|---|
| Threshold | −40 dB | The level under which sound counts as silence. Raise it for quiet recordings, lower it for noisy ones. |
| Minimum silence | 0.50 s | How long a quiet stretch has to last before it splits the file. Shorter values cut more. |
| Margin | 0.10 s | Silence kept at both ends of every clip. |
| Minimum clip | 0.15 s | Clips shorter than this are thrown away — it removes clicks and breaths. |

The four sliders live in the options panel on the right of the window; the toolbar button or
**View › Hide Options** (⌃⌘I) hides it. All four retune the split live, without re-reading the file: the envelope is already in memory, so
dragging a slider re-cuts the whole thing as you drag. Clips you had deselected stay deselected.

## The clips

Each clip is a tile showing its waveform, its number and its length.

- **Click the waveform** to play the clip, click again to stop. The bars turn from light blue to deep
  blue as it plays, so the tile itself is the progress bar.
- **Click the circle** in the corner to leave a clip out. Deselected tiles fade and their waveform
  goes grey.
- **All** / **None** in the toolbar (also in the Edit menu) select and deselect every clip at once.

The window title is the file name; the subtitle counts the clips and how many are selected.

Bar heights are normalised against the loudest peak in the whole file, not per clip, so a quiet clip
looks quiet next to a loud one instead of being stretched to fill its tile.

## Exporting

**Export…** (toolbar or **File › Export…**, ⌘E) asks for a folder and writes only the selected clips, as `<source name> <n>.wav` —
`footsteps 1.wav`, `footsteps 2.wav`, and so on. Sample rate, channel count and bit depth are taken
from the source file, so a 16-bit 48 kHz mono recording comes back out as 16-bit 48 kHz mono. The
original file is never touched.

Anything AVFoundation can read can go in: WAV, AIFF, CAF, MP3, M4A, and more. Output is always WAV.

## Requirements

- macOS 14 or later. On macOS 26 and later the toolbar and panels use Liquid Glass; earlier
  versions get the standard look of their system, with the same controls.
- Xcode 26 to build (`actool` compiles the Liquid Glass icon)

## Building

```bash
./build.sh
```

Produces `dist/AudioSplitter.app`. While developing, `./scripts/build_dev_mac.sh` quits the running
app, rebuilds it, copies it to `~/Downloads` and launches it again.

The split logic has no dependency on AVFoundation, so it checks on its own:

```bash
swiftc -O -o /tmp/check AudioSplitter/SilenceDetector.swift check/main.swift && /tmp/check
```

It covers the threshold, silences too short to cut, clips too short to keep, a margin large enough to
make clips collide, a file that is all silence and a file with none. The checks use `precondition`
rather than `assert` on purpose — `assert` is compiled out of optimised builds and would pass without
running.

## Structure

```
AudioSplitter/
  AudioSplitterApp.swift   window, drop zone, tiles, waveform
  SplitterModel.swift      file reading, envelope, slicing, WAV export
  SilenceDetector.swift    where the cuts fall — pure logic, no AVFoundation
  Player.swift             playback of one clip from the in-memory buffer
  AppIcon.icon             icon (Icon Composer document)
check/                     checks for the split logic
scripts/                   development build
```

The whole file is held in memory as 32-bit float — roughly 23 MB per minute of 48 kHz stereo. That is
what makes re-cutting instant while you drag a slider, and it is fine for the takes this app is for;
hours-long files would want block-by-block reading instead.

## License

[MIT](LICENSE).
