#!/usr/bin/env python3
"""Makes a recording ready for the dashboard: one that is licensed to be shared, such as a CC0 track.

    python3 apps/dashboard/tools/prepare.py <recording> <name> [the app's directory]     (needs numpy and ffmpeg)

The recording is trimmed of the silence at its end, faded in over a few milliseconds so it starts without a click, brought to a
common loudness (-14 LUFS, true peak -1 dB) and written as audio/<name>.m4a (AAC, stereo). levels/<name>.bands is the loudness of 16
bands, 30 times a second, for the Media page's visualiser, made as compose.py makes it. The length is printed, for `Music.TRACKS`.
"""
import json
import re
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from compose import SR, bands  # noqa: E402

TARGET = {"I": -14, "TP": -1, "LRA": 11}
TRIM = "areverse,silenceremove=start_periods=1:start_threshold=-60dB,areverse"
FADE_IN = "afade=t=in:d=0.03"


def ffmpeg(*args):
    return subprocess.run(["ffmpeg", "-y", "-hide_banner", "-nostats", *args], check=True, capture_output=True, text=True)


def measure(source):
    """What loudnorm finds in the trimmed recording, which its second pass is told."""
    flt = f"{TRIM},{FADE_IN},loudnorm=I={TARGET['I']}:TP={TARGET['TP']}:LRA={TARGET['LRA']}:print_format=json"
    log = ffmpeg("-i", str(source), "-af", flt, "-f", "null", "-").stderr
    return json.loads(re.findall(r"\{[^{}]*\}", log)[-1])


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    source, name = Path(sys.argv[1]), sys.argv[2]
    base = Path(sys.argv[3] if len(sys.argv) > 3 else Path(__file__).resolve().parent.parent)
    audio, levels = base / "audio", base / "levels"
    audio.mkdir(parents=True, exist_ok=True)
    levels.mkdir(parents=True, exist_ok=True)
    m = measure(source)
    flt = (f"{TRIM},{FADE_IN},loudnorm=I={TARGET['I']}:TP={TARGET['TP']}:LRA={TARGET['LRA']}"
           f":measured_I={m['input_i']}:measured_TP={m['input_tp']}:measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}"
           f":offset={m['target_offset']}:linear=true")
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "level.wav"
        ffmpeg("-i", str(source), "-af", flt, "-ar", str(SR), "-ac", "2", "-c:a", "pcm_s16le", str(wav))
        with wave.open(str(wav), "rb") as w:
            x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").reshape(-1, 2).astype(np.float64) / 32768
        m4a = audio / (name + ".m4a")
        ffmpeg("-i", str(wav), "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", str(m4a))
    (levels / (name + ".bands")).write_bytes(bands(x).tobytes())
    print(f"{name}: {len(x) / SR:.1f} s, {m4a.stat().st_size // 1024} KB, peak {np.abs(x).max():.2f}")


if __name__ == "__main__":
    main()
