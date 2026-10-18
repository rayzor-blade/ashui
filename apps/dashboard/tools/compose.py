#!/usr/bin/env python3
"""Composes Night Drive, the dashboard's own track, an instrumental made from nothing but arithmetic. The other tracks are
recordings that are licensed to be shared, which prepare.py makes ready.

    python3 apps/dashboard/tools/compose.py [the app's directory]     (needs numpy and ffmpeg)

The track is written as audio/<name>.m4a (AAC, stereo), which the page serves, and levels/<name>.bands, the loudness of 16
bands, 30 times a second, one byte each, which the program embeds and the Media page's visualiser follows as the track plays. The
track is fixed by its seed, so running this again makes the same files. It is original to this repository, and carries no licence of its own beyond its.
"""
import math
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

SR = 44100


def hz(note):
    return 440.0 * 2 ** ((note - 69) / 12)


class Mix:
    """A stereo buffer notes and hits are added to."""

    def __init__(self, seconds):
        self.n = int(seconds * SR)
        self.buffer = np.zeros((self.n, 2), dtype=np.float64)

    def add(self, start, mono, pan=0.0, gain=1.0):
        """Adds `mono` at `start` seconds, panned from -1 (left) to 1 (right)."""
        at = int(start * SR)
        if at >= self.n or len(mono) == 0:
            return
        length = min(len(mono), self.n - at)
        left = math.cos((pan + 1) * math.pi / 4)
        right = math.sin((pan + 1) * math.pi / 4)
        self.buffer[at:at + length, 0] += mono[:length] * gain * left
        self.buffer[at:at + length, 1] += mono[:length] * gain * right


def envelope(n, attack, release, curve=1.0):
    """Rises over `attack` seconds, holds, and falls over the last `release` seconds."""
    e = np.ones(n)
    a = min(n, int(attack * SR))
    r = min(n, int(release * SR))
    if a > 0:
        e[:a] = np.linspace(0, 1, a) ** curve
    if r > 0:
        e[n - r:] *= np.linspace(1, 0, r) ** curve
    return e


def tone(freq, seconds, harmonics, rolloff, detune=0.0, phase=0.0):
    """A sum of harmonics, each `h ** -rolloff` as loud: a saw's brightness when rolloff is 1, softer when it is more."""
    t = np.arange(int(seconds * SR)) / SR
    out = np.zeros_like(t)
    f = freq * 2 ** (detune / 1200)
    for h in range(1, harmonics + 1):
        if f * h > SR * 0.45:
            break
        out += np.sin(2 * math.pi * f * h * t + phase * h) / h ** rolloff
    return out


def pad_note(freq, seconds, rng):
    """A warm pad voice: three slightly detuned saws, slowly in and out, with a slow shimmer."""
    n = int(seconds * SR)
    voice = sum(tone(freq, seconds, 10, 1.4, d, rng.uniform(0, 6.28)) for d in (-9, 0, 9)) / 3
    t = np.arange(n) / SR
    voice *= 1 + 0.06 * np.sin(2 * math.pi * 0.35 * t + rng.uniform(0, 6.28))
    return voice * envelope(n, 0.45, 0.9, 1.5)


def pluck(freq, seconds, bright):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    voice = tone(freq, seconds, 12, 1.1) * np.exp(-t * (7.0 - 2.0 * bright))
    return voice * envelope(n, 0.004, 0.02)


def bass_note(freq, seconds):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    voice = np.sin(2 * math.pi * freq * t) + 0.35 * np.sin(2 * math.pi * freq * 2 * t) * np.exp(-t * 6)
    return voice * np.exp(-t * 2.2) * envelope(n, 0.006, 0.05)


def kick(seconds=0.4):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    phase = 2 * math.pi * (45 * t + 105 * (1 - np.exp(-t * 28)) / 28)
    click = np.exp(-t * 400) * 0.25
    return (np.sin(phase) * np.exp(-t * 11) + click) * envelope(n, 0.0005, 0.01)


def noise_burst(rng, seconds, decay, highpass):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    x = rng.normal(0, 1, n)
    for _ in range(highpass):
        x = np.diff(x, prepend=0)
    x /= max(1e-9, np.abs(x).max())
    return x * np.exp(-t * decay)


def snare(rng):
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * math.pi * 185 * t) * np.exp(-t * 26) * 0.55
    return body + noise_burst(rng, 0.3, 17, 1) * 0.8


def hat(rng, open_=False):
    return noise_burst(rng, 0.25 if open_ else 0.06, 9 if open_ else 55, 2) * 0.5


def reverb(buffer, rng, seconds, wet):
    """Convolves with decaying noise, a different one for each ear, and mixes `wet` of it back in."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros_like(buffer)
    size = 1
    while size < len(buffer) + n:
        size *= 2
    for ch in range(2):
        ir = rng.normal(0, 1, n) * np.exp(-t * 3.4)
        # Darker as it decays, as a room's tail is.
        ir = np.convolve(ir, np.ones(3) / 3, mode="same") * np.linspace(1, 0.35, n)
        ir /= np.sqrt((ir ** 2).sum())
        spectrum = np.fft.rfft(buffer[:, ch], size) * np.fft.rfft(ir, size)
        out[:, ch] = np.fft.irfft(spectrum, size)[: len(buffer)]
    return buffer * (1 - wet * 0.4) + out * wet


def master(buffer):
    peak = np.abs(buffer).max()
    x = buffer / max(peak, 1e-9) * 0.95
    x = np.tanh(x * 1.15) / np.tanh(1.15)
    # A short fade at each end.
    n = len(x)
    fade = int(0.012 * SR)
    x[:fade] *= np.linspace(0, 1, fade)[:, None]
    x[n - int(1.2 * SR):] *= np.linspace(1, 0, int(1.2 * SR))[:, None]
    return x * 0.89


def bands(x, rate=30, count=16):
    """The loudness of `count` log-spaced bands, `rate` times a second, 0 to 255."""
    mono = x.mean(axis=1)
    hop = SR // rate
    window = 2048
    edges = np.geomspace(60, 14000, count + 1)
    freqs = np.fft.rfftfreq(window, 1 / SR)
    frames = []
    shape = np.hanning(window)
    for start in range(0, len(mono) - window, hop):
        spectrum = np.abs(np.fft.rfft(mono[start:start + window] * shape))
        row = []
        for b in range(count):
            band = spectrum[(freqs >= edges[b]) & (freqs < edges[b + 1])]
            row.append(band.mean() if len(band) else 0.0)
        frames.append(row)
    frames = np.array(frames)
    # Each band against its own loudest, with the curve a meter has.
    frames = frames / np.maximum(np.percentile(frames, 99.5, axis=0), 1e-9)
    frames = np.clip(frames, 0, 1) ** 0.7
    return (frames * 255).astype(np.uint8)


# --- the tracks -----------------------------------------------------------------------------------------------------------

KINDS = {"min": [0, 3, 7, 10], "maj": [0, 4, 7, 11], "dom": [0, 4, 7, 10], "sus": [0, 5, 7, 10]}


def chord_notes(root, kind):
    return [root + i for i in KINDS[kind]]


def compose(spec):
    rng = np.random.default_rng(spec["seed"])
    beat = 60.0 / spec["bpm"]
    bar = 4 * beat
    bars = spec["bars"]
    mix = Mix(bars * bar + 3.0)
    progression = spec["progression"]
    for b in range(bars):
        root, kind = progression[b % len(progression)]
        notes = chord_notes(root, kind)
        start = b * bar
        section = spec["sections"][b]
        if "pad" in section:
            for k, n in enumerate(notes[:4]):
                mix.add(start, pad_note(hz(n + 12), bar + 0.6, rng), pan=-0.5 + k * 0.33, gain=0.13)
        if "bass" in section:
            pattern = spec["bass"]
            for step, offset in pattern:
                mix.add(start + step * beat, bass_note(hz(root - 12 + offset), beat * 0.9), gain=0.55)
        if "arp" in section:
            order = spec["arp"]
            for i in range(16):
                n = notes[order[i % len(order)] % len(notes)] + 12 * (order[i % len(order)] // len(notes)) + 12
                velocity = 0.8 + 0.2 * (i % 4 == 0) + rng.uniform(-0.05, 0.05)
                mix.add(start + i * beat / 4 + rng.uniform(0, 0.004), pluck(hz(n), 0.6, spec["bright"]),
                        pan=-0.45 if i % 2 else 0.45, gain=0.2 * velocity)
        if "drums" in section:
            for i in range(4):
                if spec["kick"][i]:
                    mix.add(start + i * beat, kick(), gain=0.8)
                if spec["snare"][i]:
                    mix.add(start + i * beat + rng.uniform(0, 0.006), snare(rng), gain=0.38)
            for i in range(8):
                if spec["hat"] == "off" and i % 2 == 0:
                    continue
                mix.add(start + i * beat / 2 + rng.uniform(0, 0.005), hat(rng, i == 7), pan=0.2, gain=0.16 + 0.05 * (i % 2))
        if "shaker" in section:
            for i in range(16):
                mix.add(start + i * beat / 4 + rng.uniform(0, 0.004), hat(rng) * 0.6, pan=-0.2, gain=0.12 + 0.05 * (i % 4 == 2))
    if spec.get("vinyl"):
        t = np.arange(mix.n)
        dust = np.zeros(mix.n)
        hits = rng.integers(0, mix.n, int(mix.n / SR * 14))
        dust[hits] = rng.uniform(0.2, 1, len(hits))
        crackle = np.convolve(dust, np.exp(-np.arange(80) / 12.0), mode="same") * rng.choice([-1, 1], mix.n)
        mix.buffer += crackle[:, None] * 0.04 + rng.normal(0, 0.0025, (mix.n, 2))
    wet = reverb(mix.buffer, rng, spec["room"], spec["wet"])
    return master(wet)


A = 57  # A3 as a MIDI note

TRACKS = [
    {
        "name": "night-drive", "title": "Night Drive", "seed": 11, "bpm": 92, "bars": 24, "room": 2.2, "wet": 0.32, "bright": 0.4,
        "progression": [(A, "min"), (A - 4, "maj"), (A + 3, "maj"), (A - 2, "dom")],
        "bass": [(0, 0), (0.75, 0), (1.5, 7), (2, 0), (2.75, 0), (3.5, 7)],
        "arp": [0, 1, 2, 3, 2, 1, 4, 3],
        "kick": [1, 0, 1, 0], "snare": [0, 1, 0, 1], "hat": "off",
        "sections": (["pad"] * 2 + ["pad", "pad bass"] * 2 + ["pad bass arp"] * 4 + ["pad bass arp drums"] * 8 + ["pad bass"] * 2
                     + ["pad bass arp drums"] * 3 + ["pad"]),
    },
]


def write_wav(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    base = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)
    out = base / "audio"
    levels = base / "levels"
    out.mkdir(parents=True, exist_ok=True)
    levels.mkdir(parents=True, exist_ok=True)
    for spec in TRACKS:
        assert len(spec["sections"]) == spec["bars"], (spec["name"], len(spec["sections"]), spec["bars"])
        x = compose(spec)
        wav = out / (spec["name"] + ".wav")
        write_wav(wav, x)
        m4a = out / (spec["name"] + ".m4a")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart", str(m4a)],
                       check=True)
        wav.unlink()
        (levels / (spec["name"] + ".bands")).write_bytes(bands(x).tobytes())
        seconds = len(x) / SR
        print(f"{spec['name']}: {seconds:.1f} s, {m4a.stat().st_size // 1024} KB, peak {np.abs(x).max():.2f}")


if __name__ == "__main__":
    main()
