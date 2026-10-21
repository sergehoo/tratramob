#!/usr/bin/env python3
"""Propositions de sonnerie « nouvelle mission » (≈ 3 s), dans l'esprit des alertes de courses VTC : électroniques, énergiques,
répétitives, très reconnaissables. ORIGINALES : synthèse par code, aucun échantillon, aucune mélodie existante reprise.

  A « Pulse »   : arpège montant en notes piquées (synthé pluck), relancé une quarte plus haut, double « ping » final.
  B « Électro » : la signature Tratra « Ta – Tra – Tra ! » en synthé moderne, réponse une octave plus haut, scintillement final.
  C « Signal »  : deux tons alternés en rafales qui montent (urgence d'une course à prendre), sans imiter une sonnerie d'appel.

Usage : python3 tool/sounds/proposals.py <dossier de sortie>  → flash_A_pulse.wav, flash_B_electro.wav, flash_C_signal.wav"""
import math
import os
import sys
import wave

import numpy as np

RATE = 44100


def hz(note: str) -> float:
    names = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}
    name, octave = note[:-1], int(note[-1])
    return 440.0 * 2 ** ((names[name] + 12 * (octave - 4)) / 12)


def env(n, attack=0.003, release=0.02):
    e = np.ones(n)
    a, r = min(n, int(attack * RATE)), min(n, int(release * RATE))
    e[:a] = np.linspace(0, 1, a)
    e[n - r:] *= np.linspace(1, 0, r) ** 2
    return e


def pluck(freq, dur, *, amp=1.0, decay=9.0, bright=1.0, detune=6.0, maxf=9000):
    """Synthé « pluck » : dent de scie additive dont les harmoniques aigus s'éteignent plus vite (balayage de filtre), deux voix
    légèrement désaccordées (largeur)."""
    n = int(RATE * dur)
    t = np.arange(n) / RATE
    out = np.zeros(n)
    for cents in (-detune, detune):
        f = freq * 2 ** (cents / 1200)
        for k in range(1, 14):
            if f * k > maxf:
                break
            out += (1 / k) * np.sin(2 * np.pi * f * k * t) * np.exp(-t * (decay + k * bright * 7))
    return amp * out / 2 * env(n)


def bell(freq, dur, *, amp=1.0, decay=5.0):
    n = int(RATE * dur)
    t = np.arange(n) / RATE
    phase = 2 * np.pi * freq * t
    sig = np.sin(phase + 1.6 * np.exp(-t * 7) * np.sin(3.5 * phase))
    return amp * sig * np.exp(-t * decay) * env(n)


def chirp(f0, f1, dur, *, amp=0.5):
    n = int(RATE * dur)
    t = np.arange(n) / RATE
    f = f0 * (f1 / f0) ** (t / dur)
    sig = np.sin(2 * np.pi * np.cumsum(f) / RATE)
    return amp * sig * np.sin(np.pi * t / dur) ** 2


def place(buf, start, sig):
    i = int(start * RATE)
    end = min(len(buf), i + len(sig))
    buf[i:end] += sig[: end - i]


def highpass(x, cutoff=110.0):
    rc = 1.0 / (2 * math.pi * cutoff)
    a = rc / (rc + 1.0 / RATE)
    y = np.zeros_like(x)
    px = py = 0.0
    for i, v in enumerate(x):
        py = a * (py + v - px)
        px = v
        y[i] = py
    return y


def master(x, peak_db=-2.0, soft=1.8):
    x = highpass(x - np.mean(x))
    x = np.tanh(soft * x / (np.max(np.abs(x)) or 1)) / np.tanh(soft)
    fade = int(0.04 * RATE)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x * (10 ** (peak_db / 20)) / (np.max(np.abs(x)) or 1)


def proposal_a():
    """« Pulse » : 16e à 150 bpm, arpège mi – si – mi – sol# montant, relancé une quarte plus haut, double ping final."""
    buf = np.zeros(int(RATE * 3.1))
    s = 60 / 150 / 4                                   # double croche
    place(buf, 0.0, chirp(900, 2600, 0.12, amp=0.35))
    seq = ["E6", "B6", "E7", "G#6", "B6", "E7"]
    for i, n in enumerate(seq):
        place(buf, 0.12 + i * s, pluck(hz(n), 0.22, amp=0.9 if i % 3 == 2 else 0.7))
    seq2 = ["A6", "E7", "A7", "C#7", "E7", "A7"]
    for i, n in enumerate(seq2):
        place(buf, 1.0 + i * s, pluck(hz(n), 0.22, amp=0.95 if i % 3 == 2 else 0.75))
    for i, n in enumerate(["E7", "B7"]):
        place(buf, 1.95 + i * 0.16, bell(hz(n), 1.0 - i * 0.16, amp=0.9))
        place(buf, 1.95 + i * 0.16, pluck(hz(n) / 2, 0.3, amp=0.5))
    return master(buf)


def proposal_b():
    """« Électro » : Ta – Tra – Tra ! (court – court – long montant) en pluck + cloche, réponse à l'octave, scintillement."""
    buf = np.zeros(int(RATE * 3.1))
    def motif(at, base, amp):
        place(buf, at, pluck(hz(base[0]), 0.16, amp=0.7 * amp))
        place(buf, at + 0.12, pluck(hz(base[1]), 0.16, amp=0.75 * amp))
        place(buf, at + 0.24, pluck(hz(base[2]), 0.45, amp=amp, decay=5))
        place(buf, at + 0.24, bell(hz(base[2]), 0.5, amp=0.45 * amp))
        place(buf, at + 0.20, chirp(hz(base[1]), hz(base[2]), 0.06, amp=0.25 * amp))
    motif(0.0, ["D6", "A6", "D7"], 0.9)
    motif(0.72, ["F#6", "C#7", "F#7"], 1.0)
    for i, n in enumerate(["D7", "F#7", "A7", "D8"]):         # scintillement final
        place(buf, 1.5 + i * 0.07, bell(hz(n), 1.4 - i * 0.07, amp=0.55 + 0.1 * i, decay=3.2))
    place(buf, 1.5, pluck(hz("D6"), 0.6, amp=0.5, decay=4))
    return master(buf)


def proposal_c():
    """« Signal » : rafales de deux tons alternés (quinte), trois rafales qui montent d'un ton, ponctuées d'un accent."""
    buf = np.zeros(int(RATE * 3.1))
    s = 0.085
    bursts = [("A6", "E7"), ("B6", "F#7"), ("C#7", "G#7")]
    for b, (lo, hi) in enumerate(bursts):
        at = b * 0.82
        for i in range(6):
            n = hi if i % 2 else lo
            place(buf, at + i * s, pluck(hz(n), 0.13, amp=0.65 + 0.06 * b, decay=14, bright=1.4))
        place(buf, at + 6 * s, bell(hz(hi), 0.45, amp=0.6 + 0.08 * b, decay=6))
    place(buf, 2.5, chirp(1800, 3600, 0.18, amp=0.3))
    return master(buf)


def bass(freq, dur, *, amp=1.0, decay=4.0):
    """Basse « pluck » riche en harmoniques 2 à 5 : le haut-parleur d'un téléphone ne rend pas la fondamentale, l'oreille la
    reconstitue à partir des harmoniques (basse perçue sans saturer)."""
    n = int(RATE * dur)
    t = np.arange(n) / RATE
    out = sum((0.9 if k == 1 else 1.0 / k) * np.sin(2 * np.pi * freq * k * t) * np.exp(-t * (decay + k * 2.2)) for k in range(1, 7))
    return amp * out * env(n, attack=0.004)


def pad(freqs, dur, *, amp=0.35):
    """Nappe médium chaude (accord en dents de scie douces, ouverture lente) : remplit le médium sous l'arpège."""
    n = int(RATE * dur)
    t = np.arange(n) / RATE
    out = np.zeros(n)
    for f in freqs:
        for cents in (-8, 8):
            ff = f * 2 ** (cents / 1200)
            out += sum((1 / k) * np.sin(2 * np.pi * ff * k * t) * np.exp(-t * k * 0.9) for k in range(1, 6))
    shape = np.minimum(1, t / 0.08) * np.exp(-t * 1.6)
    return amp * out / (2 * len(freqs)) * shape * env(n)


def thump(dur=0.12, *, amp=0.8):
    """Impulsion grave courte (balayage 190 → 85 Hz) qui marque les temps forts, façon pulsation."""
    n = int(RATE * dur)
    t = np.arange(n) / RATE
    f = 190 * (85 / 190) ** (t / dur)
    return amp * np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t * 28) * env(n, attack=0.001)


def proposal_a_warm(octave_shift=-12, bass_amp=0.75, pad_amp=0.32, bright=0.75, maxf=4500, bell_amp=0.5):
    """« Pulse » plus chaude : même motif, une octave plus bas, basse + nappe médium + pulsation grave, aigus adoucis."""
    buf = np.zeros(int(RATE * 3.1))
    s = 60 / 150 / 4
    tr = lambda n: hz(n) * 2 ** (octave_shift / 12)          # noqa: E731
    place(buf, 0.0, chirp(500, 1300, 0.12, amp=0.25))
    for i, n in enumerate(["E6", "B6", "E7", "G#6", "B6", "E7"]):
        place(buf, 0.12 + i * s, pluck(tr(n), 0.26, amp=0.95 if i % 3 == 2 else 0.75, bright=bright, decay=7, maxf=maxf))
    place(buf, 0.12, bass(hz("E2") * 2, 0.85, amp=bass_amp))
    place(buf, 0.12, thump(amp=0.7))
    place(buf, 0.12, pad([tr("E6"), tr("G#6"), tr("B6")], 0.85, amp=pad_amp))
    for i, n in enumerate(["A6", "E7", "A7", "C#7", "E7", "A7"]):
        place(buf, 1.0 + i * s, pluck(tr(n), 0.26, amp=1.0 if i % 3 == 2 else 0.8, bright=bright, decay=7, maxf=maxf))
    place(buf, 1.0, bass(hz("A2") * 2, 0.85, amp=bass_amp))
    place(buf, 1.0, thump(amp=0.75))
    place(buf, 1.0, pad([tr("A6"), tr("C#7"), tr("E7")], 0.85, amp=pad_amp))
    for i, n in enumerate(["E7", "B7"]):
        place(buf, 1.95 + i * 0.16, bell(tr(n), 1.0 - i * 0.16, amp=bell_amp, decay=4.5))
        place(buf, 1.95 + i * 0.16, pluck(tr(n) / 2, 0.4, amp=0.7, bright=bright, decay=5, maxf=maxf))
    place(buf, 1.95, bass(hz("E2") * 2, 1.1, amp=bass_amp * 1.1, decay=2.8))
    place(buf, 1.95, thump(amp=0.85))
    place(buf, 1.95, pad([tr("E6"), tr("G#6"), tr("B6")], 1.1, amp=pad_amp * 1.1))
    return master(buf, soft=2.6)


def write(path, x):
    pcm = np.clip(np.round(x * 32767), -32767, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    print(f"{os.path.basename(path)}  {len(x) / RATE:.2f} s  crête {20 * math.log10(np.max(np.abs(x))):.1f} dBFS  "
          f"RMS {20 * math.log10(np.sqrt(np.mean(x ** 2))):.1f} dBFS")


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    os.makedirs(out, exist_ok=True)
    write(os.path.join(out, "flash_A_pulse.wav"), proposal_a())
    write(os.path.join(out, "flash_B_electro.wav"), proposal_b())
    write(os.path.join(out, "flash_C_signal.wav"), proposal_c())
    # Retour utilisateur sur A (trop aigu, manque de médium et de basse) : deux versions plus chaudes.
    write(os.path.join(out, "flash_A2_pulse_grave.wav"), proposal_a_warm(octave_shift=-12, bass_amp=0.9, pad_amp=0.36, bright=0.9, maxf=4000, bell_amp=0.45))
    write(os.path.join(out, "flash_A3_pulse_medium.wav"), proposal_a_warm(octave_shift=-7, bass_amp=0.75, pad_amp=0.3, bright=0.9, maxf=5000, bell_amp=0.5))
