#!/usr/bin/env python3
"""Identité sonore Tratra — signature « Ta – Tra – Tra ! » (sons ORIGINAUX, entièrement synthétisés par ce script).

Aucun échantillon, aucune boucle, aucune mélodie existante : trois notes ascendantes (sol – ré – sol à l'octave, quinte puis quarte),
rythme court – court – long accentué, timbre de type cloche/marimba obtenu par modulation de fréquence. Le script est la preuve de
l'origine : il régénère les fichiers à l'identique.

  tratra_flash         ≈ 3 s : la signature deux fois, puis un « Tra ! » final en accord qui résonne (nouvelles missions).
  tratra_notification  ≈ 1 s : la signature une fois, plus douce (notifications ordinaires).

Réglages pour haut-parleur de téléphone : fondamentales entre 780 et 2 000 Hz (zone où ces haut-parleurs sont efficaces), coupe-bas
à 300 Hz (rien d'inaudible qui ferait saturer), crête à −2 dBFS (flash) et −6 dBFS (notification), marge pour l’encodage, limiteur doux, aucune saturation.

Usage : python3 tool/sounds/generate_tratra_sounds.py  → tool/sounds/*.wav, puis conversions (voir build_sounds.sh)."""
import math
import os
import wave

import numpy as np

RATE = 44100
OUT = os.path.dirname(os.path.abspath(__file__))

G5, D6, G6, B6, D7 = 783.99, 1174.66, 1567.98, 1975.53, 2349.32


def note(freq, dur, *, amp=1.0, brightness=2.2, decay=6.0, attack=0.004, bend_from=None, bend_time=0.035):
    """Note « cloche » : porteuse + modulateur 2:1 dont l'indice décroît (attaque brillante, résonance douce)."""
    n = int(RATE * dur)
    t = np.arange(n) / RATE
    if bend_from:   # petite montée vers la note (le « ! » final)
        f = np.where(t < bend_time, bend_from + (freq - bend_from) * (t / bend_time), freq)
        phase = 2 * np.pi * np.cumsum(f) / RATE
    else:
        phase = 2 * np.pi * freq * t
    index = brightness * np.exp(-t * 9.0)
    sig = np.sin(phase + index * np.sin(2.0 * phase))
    sig += 0.18 * np.sin(3.0 * phase) * np.exp(-t * 14.0)          # éclat de l'attaque
    env = np.minimum(1.0, t / attack) * np.exp(-t * decay)
    release = min(n, int(0.025 * RATE))                              # fin de note sans « clic »
    env[n - release:] *= np.linspace(1.0, 0.0, release) ** 2
    return amp * sig * env


def place(buf, start, sig):
    i = int(start * RATE)
    end = min(len(buf), i + len(sig))
    buf[i:end] += sig[: end - i]


def highpass(x, cutoff=300.0):
    rc = 1.0 / (2 * math.pi * cutoff)
    a = rc / (rc + 1.0 / RATE)
    y = np.zeros_like(x)
    prev_x = prev_y = 0.0
    for i, v in enumerate(x):
        prev_y = a * (prev_y + v - prev_x)
        prev_x = v
        y[i] = prev_y
    return y


def master(x, peak_db):
    x = highpass(x - np.mean(x))
    x = np.tanh(1.6 * x / (np.max(np.abs(x)) or 1)) / np.tanh(1.6)   # limiteur doux (aucun écrêtage)
    fade = int(0.03 * RATE)
    x[-fade:] *= np.linspace(1, 0, fade)
    x[: int(0.002 * RATE)] *= np.linspace(0, 1, int(0.002 * RATE))
    return x * (10 ** (peak_db / 20)) / (np.max(np.abs(x)) or 1)


def signature(buf, at, *, amp=1.0, soft=False):
    """Ta (court) – Tra (court) – Tra ! (long, accentué)."""
    b = 1.4 if soft else 2.4
    place(buf, at + 0.00, note(G5, 0.16, amp=0.70 * amp, brightness=b, decay=16))
    place(buf, at + 0.13, note(D6, 0.16, amp=0.78 * amp, brightness=b, decay=16))
    place(buf, at + 0.26, note(G6, 0.55 if soft else 0.48, amp=1.0 * amp, brightness=b + 0.4, decay=5.5 if soft else 7.0,
                               bend_from=None if soft else G6 * 0.94))


def flash():
    buf = np.zeros(int(RATE * 3.05))
    signature(buf, 0.00, amp=0.92)
    signature(buf, 0.80, amp=1.0)
    # Finale : Ta – Tra – puis « Tra ! » en accord majeur qui résonne (sol – si – ré).
    place(buf, 1.60, note(G5, 0.16, amp=0.75, decay=16))
    place(buf, 1.73, note(D6, 0.16, amp=0.82, decay=16))
    for f, a in ((G6, 1.0), (B6, 0.55), (D7, 0.42)):
        place(buf, 1.86, note(f, 1.18, amp=a, brightness=2.8, decay=2.9, bend_from=f * 0.95))
    return master(buf, -2.0)


def notification():
    buf = np.zeros(int(RATE * 1.0))
    signature(buf, 0.0, amp=0.8, soft=True)
    return master(buf, -6.0)


def write(name, x):
    path = os.path.join(OUT, f"{name}.wav")
    pcm = np.clip(np.round(x * 32767), -32767, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    print(f"{path}  {len(x) / RATE:.2f} s  crête {20 * math.log10(np.max(np.abs(x))):.1f} dBFS  "
          f"RMS {20 * math.log10(np.sqrt(np.mean(x ** 2))):.1f} dBFS")


if __name__ == "__main__":
    write("tratra_flash", flash())
    write("tratra_notification", notification())
