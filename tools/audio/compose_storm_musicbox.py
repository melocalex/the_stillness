#!/usr/bin/env python3
"""THE STILLNESS - "The Mechanism" (storm-night music box). Original composition.

An original, slow 3/4 music-box waltz for storm and bad nights: high,
repetitive, a little out of tune, winding down as if the mechanism is
running out. It is written note by note here and does not quote or vary
any existing melody.

Synthesis: inharmonic music-box partials with exponential decay, slow tape
wobble, a few deliberately detuned notes on the second pass, a missing note,
a very quiet low fifth underneath (leaves room for rain), and a simple
noise-convolution reverb.

Usage: python3 -I tools/audio/compose_storm_musicbox.py <out.wav>
"""
import sys
import wave

import numpy as np

SR = 44100
BPM = 66.0
BEAT = 60.0 / BPM

# Melody: (midi note or None for silence, beats). 8 bars of 3/4.
THEME = [
    (83, 1), (79, 1), (78, 1),          # B5 G5 F#5
    (77, 2), (79, 1),                   # F5 - G5
    (83, 1), (84, 1), (79, 1),          # B5 C6 G5
    (78, 3),                            # F#5 held
    (76, 1), (79, 1), (74, 1),          # E5 G5 D5
    (73, 1), (74, 1), (77, 1),          # C#5 D5 F5
    (76, 1), (72, 1), (71, 1),          # E5 C5 B4
    (71, 2), (None, 1),                 # B4 held, breath
]

# Second pass: same shape, but wrong in small ways.
VARIATION = [
    (83, 1), (79, 1), (78, 1),
    (77, 2), (None, 1),                 # the G never comes
    (83, 1), (84, 1), (80, 1),          # G#5 instead of G5
    (78, 3),
    (76, 1), (79, 1), (74, 1),
    (73, 1), (74, 1), (77, 1),
    (76, 1), (72, 1.3), (71, 1.6),      # slowing
    (71, 3.5),                          # last note rings out
]
DETUNE_CENTS = {9: -45, 14: +30, 17: -25}  # note index in VARIATION -> cents


def midi_hz(m: float) -> float:
    return 440.0 * 2 ** ((m - 69) / 12)


def music_box_note(freq: float, dur: float, vel: float) -> np.ndarray:
    n = int((dur + 2.5) * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    # Inharmonic comb-tooth partials: ratio, amplitude, decay seconds.
    for ratio, amp, tau in ((1.0, 1.0, 1.4), (2.76, 0.42, 0.55), (5.40, 0.18, 0.22), (8.93, 0.06, 0.1)):
        out += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t / tau)
    click = np.random.default_rng(int(freq)).normal(0, 1, n) * np.exp(-t / 0.004) * 0.08
    attack = np.minimum(t / 0.002, 1.0)
    return (out + click) * attack * vel


def render(sequence, start: float, track: np.ndarray, detune=None, tempo_drag: float = 0.0):
    pos = start
    total = len(sequence)
    for i, (note, beats) in enumerate(sequence):
        drag = 1.0 + tempo_drag * (i / total) ** 2
        dur = beats * BEAT * drag
        if note is not None:
            cents = (detune or {}).get(i, 0)
            freq = midi_hz(note + cents / 100.0)
            vel = 0.55 + 0.08 * np.sin(i * 1.7)
            sig = music_box_note(freq, dur, vel)
            a = int(pos * SR)
            b = min(a + len(sig), len(track))
            track[a:b] += sig[: b - a]
        pos += dur
    return pos


def main():
    out_path = sys.argv[1]
    length = 60.0
    n = int(length * SR)
    mel = np.zeros(n)
    t1 = render(THEME, 1.0, mel)
    render(VARIATION, t1 + BEAT * 1.5, mel, DETUNE_CENTS, tempo_drag=0.18)

    # Slow wobble (pitch drift approximated with a tiny time-varying delay).
    t = np.arange(n) / SR
    delay = (0.0016 * (1 + np.sin(2 * np.pi * 0.23 * t))) * SR
    idx = np.clip(np.arange(n) - delay, 0, n - 1)
    mel = np.interp(idx, np.arange(n), mel)

    # Very quiet low fifth (B1 + F#2), breathing in and out.
    pad = 0.035 * (np.sin(2 * np.pi * midi_hz(35) * t) + 0.7 * np.sin(2 * np.pi * midi_hz(42) * t))
    pad *= 0.5 * (1 - np.cos(2 * np.pi * t / length))

    dry = mel + pad
    # Reverb: convolution with decaying noise (2.8 s).
    rng = np.random.default_rng(7)
    ir_len = int(2.8 * SR)
    ir = rng.normal(0, 1, ir_len) * np.exp(-np.arange(ir_len) / SR / 0.9)
    ir /= np.sqrt(np.sum(ir**2))
    wet = np.convolve(dry, ir)[:n] * 0.35

    left = dry * 0.8 + wet
    right = np.interp(np.clip(np.arange(n) - 0.00035 * SR, 0, n - 1), np.arange(n), dry) * 0.8 + wet
    fade = np.minimum(1.0, (length - t) / 3.0)
    stereo = np.stack([left * fade, right * fade], axis=1)
    stereo /= np.max(np.abs(stereo)) * 1.12
    pcm = (stereo * 32767).astype(np.int16)
    with wave.open(out_path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"wrote {out_path} ({length:.0f}s)")


if __name__ == "__main__":
    main()
