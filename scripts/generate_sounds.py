#!/usr/bin/env python3
"""
Generate premium sound effects for Yap app — 3 themes.
Uses DSP techniques: layered synthesis, convolution reverb,
biquad filtering, harmonic saturation.

Output: 48kHz 16-bit WAV files → Resources/Sounds/{theme}/
"""

import numpy as np
from scipy.signal import butter, lfilter, fftconvolve
import struct
import os

SAMPLE_RATE = 48000
BASE_DIR = os.path.join(os.path.dirname(__file__), '..', 'Resources', 'Sounds')


def write_wav(theme, filename, samples, sample_rate=SAMPLE_RATE):
    out_dir = os.path.join(BASE_DIR, theme)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, filename)

    peak = np.max(np.abs(samples))
    if peak > 0:
        samples = samples / peak * 0.89

    int_samples = np.clip(samples * 32767, -32768, 32767).astype(np.int16)
    n_frames = len(int_samples)
    data_size = n_frames * 2

    with open(path, 'wb') as f:
        f.write(b'RIFF')
        f.write(struct.pack('<I', data_size + 36))
        f.write(b'WAVE')
        f.write(b'fmt ')
        f.write(struct.pack('<IHHIIHH', 16, 1, 1, sample_rate, sample_rate * 2, 2, 16))
        f.write(b'data')
        f.write(struct.pack('<I', data_size))
        f.write(int_samples.tobytes())

    duration_ms = n_frames / sample_rate * 1000
    size_kb = os.path.getsize(path) / 1024
    print(f"    ✓ {theme}/{filename} ({duration_ms:.0f}ms, {size_kb:.1f}KB)")


# ─────────────────────────────────────────────
# DSP Building Blocks
# ─────────────────────────────────────────────

def sine(freq, duration):
    t = np.arange(int(SAMPLE_RATE * duration)) / SAMPLE_RATE
    return np.sin(2 * np.pi * freq * t)

def sine_sweep(freq_start, freq_end, duration):
    t = np.arange(int(SAMPLE_RATE * duration)) / SAMPLE_RATE
    freq = np.linspace(freq_start, freq_end, len(t))
    phase = 2 * np.pi * np.cumsum(freq) / SAMPLE_RATE
    return np.sin(phase)

def envelope_adsr(n, attack=0.01, decay=0.05, sustain=0.7, release=0.1):
    env = np.zeros(n)
    a = int(attack * SAMPLE_RATE)
    d = int(decay * SAMPLE_RATE)
    r = int(release * SAMPLE_RATE)
    s = max(n - a - d - r, 0)

    if a > 0: env[:a] = np.sin(np.linspace(0, np.pi/2, a))
    if d > 0: env[a:a+d] = 1.0 - (1.0 - sustain) * (1 - np.cos(np.linspace(0, np.pi, d))) / 2
    if s > 0: env[a+d:a+d+s] = sustain * np.exp(-0.5 * np.linspace(0, 1, max(s, 1)))
    start = env[max(a+d+s-1, 0)] if a+d+s > 0 else sustain
    if r > 0: env[a+d+s:a+d+s+r] = start * (1 + np.cos(np.linspace(0, np.pi, r))) / 2
    return env[:n]

def lowpass(signal, cutoff, order=4):
    b, a = butter(order, min(cutoff / (SAMPLE_RATE/2), 0.99), btype='low')
    return lfilter(b, a, signal)

def highpass(signal, cutoff, order=2):
    b, a = butter(order, min(cutoff / (SAMPLE_RATE/2), 0.99), btype='high')
    return lfilter(b, a, signal)

def soft_saturate(signal, drive=2.0):
    return np.tanh(signal * drive) / np.tanh(drive)

def reverb(signal, wet=0.15, duration=0.3, decay=3.5):
    n = int(SAMPLE_RATE * duration)
    ir = np.zeros(n)
    for t, g in [(0.008,0.6),(0.014,0.45),(0.021,0.35),(0.03,0.25),(0.04,0.18),(0.05,0.12)]:
        idx = int(t * SAMPLE_RATE)
        if idx < n: ir[idx] = g
    start = int(0.05 * SAMPLE_RATE)
    tail = np.random.randn(n - start) * np.exp(-decay * np.linspace(0, duration, n - start))
    ir[start:] += tail * 0.12
    ir = lowpass(ir, 5000)
    wet_sig = fftconvolve(signal, ir, mode='full')[:len(signal) + int(duration * SAMPLE_RATE)]
    dry = np.pad(signal, (0, len(wet_sig) - len(signal)))
    return dry * (1 - wet) + wet_sig * wet


# ═══════════════════════════════════════════════
# THEME 1: DEEP BASS — warm, felt-in-chest
# ═══════════════════════════════════════════════

def deep_start():
    dur = 0.28
    n = int(SAMPLE_RATE * dur)
    t = np.arange(n) / SAMPLE_RATE
    env = envelope_adsr(n, attack=0.025, decay=0.08, sustain=0.6, release=0.12)

    # Sub foundation
    sub = sine_sweep(64, 66, dur) * 0.35
    # Warm fundamental
    fund = sine(130.81, dur) * 0.50 + sine(261.63, dur) * 0.08
    # Musical fifth
    fifth = sine(196.0, dur) * 0.18
    # Shimmer on attack only
    shimmer = (sine(523.25, dur) * 0.06 + sine(659.25, dur) * 0.03) * np.exp(-15 * t)
    # Air texture
    noise = lowpass(np.random.randn(n) * 0.015, 800) * np.exp(-10 * t)

    mix = (sub + fund + fifth + shimmer + noise) * env
    mix = soft_saturate(mix, 1.5)
    mix = lowpass(mix, 4000)
    mix = highpass(mix, 30)
    return reverb(mix, wet=0.15, duration=0.25)

def deep_stop():
    dur = 0.38
    n = int(SAMPLE_RATE * dur)
    t = np.arange(n) / SAMPLE_RATE

    # Note 1: G3 (0-150ms)
    n1 = int(0.15 * SAMPLE_RATE)
    env1 = np.zeros(n)
    env1[:n1] = envelope_adsr(n1, attack=0.012, decay=0.04, sustain=0.7, release=0.06)
    note1 = (sine(196.0, dur)*0.40 + sine(98.0, dur)*0.20 + sine(392.0, dur)*0.05) * env1

    # Note 2: C3 resolve (120-380ms)
    s2 = int(0.12 * SAMPLE_RATE)
    n2 = n - s2
    env2 = np.zeros(n)
    env2[s2:s2+n2] = envelope_adsr(n2, attack=0.015, decay=0.06, sustain=0.55, release=0.15)[:n2]
    note2 = (sine(130.81, dur)*0.45 + sine(65.41, dur)*0.25 + sine(261.63, dur)*0.06) * env2

    # Ting on resolve
    ting = np.zeros(n)
    ting_env = np.exp(-12 * np.arange(n-s2) / SAMPLE_RATE)
    ting[s2:] = sine(1046.5, dur)[s2:] * 0.02 * ting_env[:n-s2]

    mix = note1 + note2 + ting
    mix = soft_saturate(mix, 1.4)
    mix = lowpass(mix, 3500)
    mix = highpass(mix, 30)
    return reverb(mix, wet=0.18, duration=0.3)

def deep_cancel():
    dur = 0.12
    n = int(SAMPLE_RATE * dur)
    t = np.arange(n) / SAMPLE_RATE
    env = np.exp(-12 * t) * np.sin(np.linspace(0, np.pi, n))
    mix = (sine(82.41, dur)*0.40 + sine(55.0, dur)*0.25) * env
    mix += lowpass(np.random.randn(n)*0.04, 400) * np.exp(-30*t) * env
    mix = lowpass(mix, 500)
    mix = highpass(mix, 25)
    return reverb(mix, wet=0.1, duration=0.15)

def deep_error():
    dur = 0.30
    n = int(SAMPLE_RATE * dur)
    n1 = int(0.14 * SAMPLE_RATE)
    env1 = np.zeros(n)
    env1[:n1] = envelope_adsr(n1, attack=0.01, decay=0.03, sustain=0.6, release=0.06)
    note1 = (sine(164.81, dur)*0.35 + sine(82.41, dur)*0.15) * env1

    s2 = int(0.13 * SAMPLE_RATE)
    n2 = n - s2
    env2 = np.zeros(n)
    env2[s2:s2+n2] = envelope_adsr(n2, attack=0.01, decay=0.04, sustain=0.5, release=0.1)[:n2]
    note2 = (sine(155.56, dur)*0.30 + sine(77.78, dur)*0.15) * env2

    mix = soft_saturate(note1 + note2, 1.3)
    mix = lowpass(mix, 2000)
    mix = highpass(mix, 30)
    return reverb(mix, wet=0.12, duration=0.2)


# ═══════════════════════════════════════════════
# THEME 2: CRYSTAL — bright, glass-like, airy
# ═══════════════════════════════════════════════

def crystal_start():
    dur = 0.32
    n = int(SAMPLE_RATE * dur)
    t = np.arange(n) / SAMPLE_RATE
    env = envelope_adsr(n, attack=0.008, decay=0.06, sustain=0.5, release=0.18)

    # High bell tone
    bell = sine(1318.5, dur) * 0.30  # E6
    bell += sine(1567.98, dur) * 0.18  # G6
    bell += sine(2637.0, dur) * 0.06 * np.exp(-8*t)  # E7 shimmer

    # Subtle body
    body = sine(659.25, dur) * 0.15  # E5
    body += sine(329.63, dur) * 0.08  # E4

    # Metallic texture
    metal = np.random.randn(n) * 0.02
    metal = lowpass(metal, 8000)
    metal = highpass(metal, 3000)
    metal *= np.exp(-12 * t)

    mix = (bell + body + metal) * env
    mix = lowpass(mix, 10000)
    mix = highpass(mix, 200)
    return reverb(mix, wet=0.25, duration=0.4)

def crystal_stop():
    dur = 0.35
    n = int(SAMPLE_RATE * dur)
    t = np.arange(n) / SAMPLE_RATE

    # Descending two-note: G6 → E6
    n1 = int(0.14 * SAMPLE_RATE)
    env1 = np.zeros(n)
    env1[:n1] = envelope_adsr(n1, attack=0.005, decay=0.03, sustain=0.6, release=0.06)
    note1 = (sine(1567.98, dur)*0.28 + sine(783.99, dur)*0.12) * env1

    s2 = int(0.12 * SAMPLE_RATE)
    n2 = n - s2
    env2 = np.zeros(n)
    env2[s2:s2+n2] = envelope_adsr(n2, attack=0.005, decay=0.05, sustain=0.5, release=0.15)[:n2]
    note2 = (sine(1318.5, dur)*0.30 + sine(659.25, dur)*0.12 + sine(2637.0, dur)*0.04*np.exp(-10*t)) * env2

    mix = note1 + note2
    mix = lowpass(mix, 10000)
    mix = highpass(mix, 200)
    return reverb(mix, wet=0.28, duration=0.45)

def crystal_cancel():
    dur = 0.15
    n = int(SAMPLE_RATE * dur)
    t = np.arange(n) / SAMPLE_RATE
    env = np.exp(-10*t) * np.sin(np.linspace(0, np.pi, n))
    mix = sine(880.0, dur) * 0.25 * env  # A5
    mix += sine(440.0, dur) * 0.10 * env
    mix = lowpass(mix, 5000)
    return reverb(mix, wet=0.2, duration=0.2)

def crystal_error():
    dur = 0.28
    n = int(SAMPLE_RATE * dur)
    t = np.arange(n) / SAMPLE_RATE

    n1 = int(0.12 * SAMPLE_RATE)
    env1 = np.zeros(n); env1[:n1] = envelope_adsr(n1, attack=0.005, decay=0.03, sustain=0.5, release=0.04)
    note1 = sine(1174.66, dur) * 0.25 * env1  # D6

    s2 = int(0.11 * SAMPLE_RATE)
    n2 = n - s2
    env2 = np.zeros(n)
    env2[s2:s2+n2] = envelope_adsr(n2, attack=0.005, decay=0.04, sustain=0.4, release=0.10)[:n2]
    note2 = sine(1108.73, dur) * 0.22 * env2  # Db6 — half step down

    mix = note1 + note2
    mix = lowpass(mix, 8000)
    return reverb(mix, wet=0.22, duration=0.3)


# ═══════════════════════════════════════════════
# THEME 3: MINIMAL — barely-there clicks & taps
# ═══════════════════════════════════════════════

def minimal_start():
    dur = 0.08
    n = int(SAMPLE_RATE * dur)
    t = np.arange(n) / SAMPLE_RATE

    # Sharp click + tiny resonance
    click = np.random.randn(n) * 0.5
    click = lowpass(click, 2000)
    click = highpass(click, 200)
    click *= np.exp(-40 * t)

    # Tiny resonant ping
    ping = sine(440.0, dur) * 0.15 * np.exp(-25 * t)

    mix = click + ping
    mix = lowpass(mix, 4000)
    return reverb(mix, wet=0.08, duration=0.1)

def minimal_stop():
    dur = 0.12
    n = int(SAMPLE_RATE * dur)
    t = np.arange(n) / SAMPLE_RATE

    # Double click
    click1 = np.zeros(n)
    c1_n = int(0.04 * SAMPLE_RATE)
    c1_t = np.arange(c1_n) / SAMPLE_RATE
    click1[:c1_n] = (np.random.randn(c1_n) * 0.4 + sine(330, 0.04) * 0.15) * np.exp(-35 * c1_t)

    click2 = np.zeros(n)
    s2 = int(0.06 * SAMPLE_RATE)
    c2_n = min(c1_n, n - s2)
    c2_t = np.arange(c2_n) / SAMPLE_RATE
    click2[s2:s2+c2_n] = (np.random.randn(c2_n) * 0.3 + sine(440, 0.04)[:c2_n] * 0.12) * np.exp(-35 * c2_t)

    mix = lowpass(click1 + click2, 3000)
    mix = highpass(mix, 150)
    return reverb(mix, wet=0.06, duration=0.08)

def minimal_cancel():
    dur = 0.06
    n = int(SAMPLE_RATE * dur)
    t = np.arange(n) / SAMPLE_RATE
    mix = np.random.randn(n) * 0.3
    mix = lowpass(mix, 1500)
    mix = highpass(mix, 200)
    mix *= np.exp(-50 * t)
    return mix

def minimal_error():
    dur = 0.15
    n = int(SAMPLE_RATE * dur)
    t = np.arange(n) / SAMPLE_RATE

    # Two quick taps, lower pitch
    tap1 = np.zeros(n)
    t1_n = int(0.04 * SAMPLE_RATE)
    t1_t = np.arange(t1_n) / SAMPLE_RATE
    tap1[:t1_n] = sine(220.0, 0.04) * 0.25 * np.exp(-30 * t1_t)

    tap2 = np.zeros(n)
    s2 = int(0.07 * SAMPLE_RATE)
    t2_n = min(t1_n, n - s2)
    t2_t = np.arange(t2_n) / SAMPLE_RATE
    tap2[s2:s2+t2_n] = sine(196.0, 0.04)[:t2_n] * 0.20 * np.exp(-30 * t2_t)

    mix = lowpass(tap1 + tap2, 2000)
    mix = highpass(mix, 100)
    return reverb(mix, wet=0.08, duration=0.1)


# ─────────────────────────────────────────────
# Generate All Themes
# ─────────────────────────────────────────────

if __name__ == '__main__':
    print("🎵 Generating premium sound themes for Yap...\n")

    themes = {
        'deep': {
            'desc': 'Warm bass, felt-in-chest',
            'start': deep_start, 'stop': deep_stop,
            'cancel': deep_cancel, 'error': deep_error,
        },
        'crystal': {
            'desc': 'Bright glass bells, airy',
            'start': crystal_start, 'stop': crystal_stop,
            'cancel': crystal_cancel, 'error': crystal_error,
        },
        'minimal': {
            'desc': 'Barely-there clicks & taps',
            'start': minimal_start, 'stop': minimal_stop,
            'cancel': minimal_cancel, 'error': minimal_error,
        },
    }

    for name, theme in themes.items():
        print(f"  🎹 {name} — {theme['desc']}")
        for sound in ['start', 'stop', 'cancel', 'error']:
            samples = theme[sound]()
            write_wav(name, f'{sound}.wav', samples)

    # Clean up old flat files
    for old in ['start.wav', 'stop.wav', 'cancel.wav', 'error.wav']:
        old_path = os.path.join(BASE_DIR, old)
        if os.path.exists(old_path):
            os.remove(old_path)
            print(f"  🗑  Removed old {old}")

    print(f"\n✨ Done! 3 themes × 4 sounds = 12 files")
    print(f"   Location: {os.path.abspath(BASE_DIR)}")
