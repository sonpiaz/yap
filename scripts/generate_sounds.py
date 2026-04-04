#!/usr/bin/env python3
"""
Generate premium sound effects for Yap app.
Uses DSP techniques: layered synthesis, convolution reverb, 
biquad filtering, harmonic saturation, stereo imaging.

Output: 48kHz 16-bit WAV files → Resources/Sounds/
"""

import numpy as np
from scipy.signal import butter, lfilter, fftconvolve
import struct
import os

SAMPLE_RATE = 48000
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), '..', 'Resources', 'Sounds')


def write_wav(filename, samples, sample_rate=SAMPLE_RATE):
    """Write 16-bit mono WAV file."""
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    path = os.path.join(OUTPUT_DIR, filename)
    
    # Normalize to -1dB headroom
    peak = np.max(np.abs(samples))
    if peak > 0:
        samples = samples / peak * 0.89  # -1dB
    
    # Convert to int16
    int_samples = np.clip(samples * 32767, -32768, 32767).astype(np.int16)
    
    n_frames = len(int_samples)
    data_size = n_frames * 2
    
    with open(path, 'wb') as f:
        # RIFF header
        f.write(b'RIFF')
        f.write(struct.pack('<I', data_size + 36))
        f.write(b'WAVE')
        # fmt chunk
        f.write(b'fmt ')
        f.write(struct.pack('<I', 16))       # chunk size
        f.write(struct.pack('<H', 1))        # PCM
        f.write(struct.pack('<H', 1))        # mono
        f.write(struct.pack('<I', sample_rate))
        f.write(struct.pack('<I', sample_rate * 2))
        f.write(struct.pack('<H', 2))        # block align
        f.write(struct.pack('<H', 16))       # bits
        # data chunk
        f.write(b'data')
        f.write(struct.pack('<I', data_size))
        f.write(int_samples.tobytes())
    
    duration_ms = n_frames / sample_rate * 1000
    print(f"  ✓ {filename} ({duration_ms:.0f}ms, {os.path.getsize(path)} bytes)")


# ─────────────────────────────────────────────
# DSP Building Blocks
# ─────────────────────────────────────────────

def sine(freq, duration, phase=0):
    """Generate sine wave."""
    t = np.arange(int(SAMPLE_RATE * duration)) / SAMPLE_RATE
    return np.sin(2 * np.pi * freq * t + phase)


def envelope_adsr(n_samples, attack=0.01, decay=0.05, sustain_level=0.7, release=0.1):
    """ADSR envelope — smoother than simple exponential."""
    env = np.zeros(n_samples)
    a = int(attack * SAMPLE_RATE)
    d = int(decay * SAMPLE_RATE)
    r = int(release * SAMPLE_RATE)
    s = n_samples - a - d - r
    
    if a > 0:
        # Sine-curved attack (smoother than linear)
        env[:a] = np.sin(np.linspace(0, np.pi/2, a))
    if d > 0:
        env[a:a+d] = 1.0 - (1.0 - sustain_level) * (1 - np.cos(np.linspace(0, np.pi, d))) / 2
    if s > 0:
        # Gentle sustain decay
        env[a+d:a+d+s] = sustain_level * np.exp(-0.5 * np.linspace(0, 1, max(s, 1)))
    if r > 0:
        start_level = env[max(a+d+s-1, 0)]
        env[a+d+s:] = start_level * (1 + np.cos(np.linspace(0, np.pi, r))) / 2
    
    return env[:n_samples]


def lowpass(signal, cutoff, order=4):
    """Butterworth low-pass filter."""
    nyq = SAMPLE_RATE / 2
    b, a = butter(order, min(cutoff / nyq, 0.99), btype='low')
    return lfilter(b, a, signal)


def highpass(signal, cutoff, order=2):
    """Butterworth high-pass filter."""
    nyq = SAMPLE_RATE / 2
    b, a = butter(order, min(cutoff / nyq, 0.99), btype='high')
    return lfilter(b, a, signal)


def soft_saturate(signal, drive=2.0):
    """Warm tube-like saturation — adds harmonics without harshness."""
    return np.tanh(signal * drive) / np.tanh(drive)


def reverb_ir(duration=0.4, decay=3.0, density=800):
    """Generate a small-room impulse response for subtle reverb."""
    n = int(SAMPLE_RATE * duration)
    ir = np.zeros(n)
    
    # Early reflections (discrete echoes)
    early_times = [0.008, 0.013, 0.019, 0.027, 0.035, 0.044]
    early_gains = [0.7, 0.5, 0.4, 0.3, 0.2, 0.15]
    for t, g in zip(early_times, early_gains):
        idx = int(t * SAMPLE_RATE)
        if idx < n:
            ir[idx] = g
    
    # Late diffuse tail (exponential noise decay)
    start = int(0.05 * SAMPLE_RATE)
    tail = np.random.randn(n - start) * np.exp(-decay * np.linspace(0, duration - 0.05, n - start))
    ir[start:] += tail * 0.15
    
    # Smooth the IR
    ir = lowpass(ir, 6000)
    return ir


def apply_reverb(signal, wet=0.2, ir_duration=0.3):
    """Apply convolution reverb."""
    ir = reverb_ir(duration=ir_duration)
    wet_signal = fftconvolve(signal, ir, mode='full')[:len(signal) + int(ir_duration * SAMPLE_RATE)]
    
    # Pad dry signal to match
    dry = np.pad(signal, (0, len(wet_signal) - len(signal)))
    return dry * (1 - wet) + wet_signal * wet


# ─────────────────────────────────────────────
# Sound Design
# ─────────────────────────────────────────────

def generate_start_tone():
    """
    "I'm listening" — Premium activation sound.
    
    Design: Deep bass bloom with warm overtones and subtle reverb tail.
    Reference: The sound a high-end noise-cancelling headphone makes 
    when it activates — felt in the chest, not in the ears.
    """
    duration = 0.28
    n = int(SAMPLE_RATE * duration)
    t = np.arange(n) / SAMPLE_RATE
    
    # Envelope: soft attack, warm sustain, gentle fade
    env = envelope_adsr(n, attack=0.025, decay=0.08, sustain_level=0.6, release=0.12)
    
    # ── Layer 1: Sub-bass foundation (C2 = 65.41 Hz) ──
    # Felt more than heard — the "weight"
    sub = sine(65.41, duration) * 0.35
    # Slight pitch rise (+2%) for sense of "opening up"
    pitch_rise = np.linspace(1.0, 1.02, n)
    sub = np.sin(2 * np.pi * 65.41 * np.cumsum(pitch_rise) / SAMPLE_RATE) * 0.35
    
    # ── Layer 2: Warm fundamental (C3 = 130.81 Hz) ──
    # The main tone — round and full
    fundamental = sine(130.81, duration) * 0.50
    # Add subtle 2nd harmonic for warmth
    fundamental += sine(261.63, duration) * 0.08
    
    # ── Layer 3: Fifth (G3 = 196.00 Hz) ──
    # Adds musicality — pleasant interval
    fifth = sine(196.00, duration) * 0.18
    
    # ── Layer 4: High shimmer (C5 = 523.25 Hz) ──
    # Very subtle, fast-decaying sparkle on attack only
    shimmer_env = np.exp(-15 * t)  # dies in ~100ms
    shimmer = sine(523.25, duration) * 0.06 * shimmer_env
    shimmer += sine(659.25, duration) * 0.03 * shimmer_env  # E5
    
    # ── Layer 5: Noise texture ──
    # Filtered noise for organic "breath" quality
    noise = np.random.randn(n) * 0.015
    noise = lowpass(noise, 800)
    noise = noise * np.exp(-10 * t)  # only on attack
    
    # Mix
    mix = (sub + fundamental + fifth + shimmer + noise) * env
    
    # Processing chain
    mix = soft_saturate(mix, drive=1.5)     # warm harmonics
    mix = lowpass(mix, 4000)                 # remove any harshness
    mix = highpass(mix, 30)                  # clean sub-bass
    mix = apply_reverb(mix, wet=0.15, ir_duration=0.25)  # subtle space
    
    write_wav('start.wav', mix)


def generate_stop_tone():
    """
    "Got it" — Premium confirmation sound.
    
    Design: Two-note bass motif (fifth → root) with warm resolve.
    Reference: The satisfying "done" sound of a luxury car door — 
    solid, resonant, final.
    """
    duration = 0.38
    n = int(SAMPLE_RATE * duration)
    t = np.arange(n) / SAMPLE_RATE
    
    # Two phases: note 1 (0-150ms) → note 2 (120-380ms) with crossfade
    phase1_end = 0.15
    crossfade = 0.03
    
    # ── Note 1: G3 (196 Hz) — the "lift" ──
    n1 = int(phase1_end * SAMPLE_RATE)
    env1 = np.zeros(n)
    env1_raw = envelope_adsr(n1, attack=0.012, decay=0.04, sustain_level=0.7, release=0.06)
    env1[:n1] = env1_raw
    
    note1 = sine(196.00, duration) * 0.40  # G3
    note1 += sine(98.00, duration) * 0.20   # G2 sub
    note1 += sine(392.00, duration) * 0.05  # G4 overtone
    note1 = note1 * env1
    
    # ── Note 2: C3 (130.81 Hz) — the "resolve" ──
    start2 = int((phase1_end - crossfade) * SAMPLE_RATE)
    n2 = n - start2
    env2 = np.zeros(n)
    env2_raw = envelope_adsr(n2, attack=0.015, decay=0.06, sustain_level=0.55, release=0.15)
    env2[start2:start2+len(env2_raw)] = env2_raw
    
    note2 = sine(130.81, duration) * 0.45   # C3
    note2 += sine(65.41, duration) * 0.25    # C2 sub — deep
    note2 += sine(261.63, duration) * 0.06   # C4 warmth
    # Gentle pitch drop for "settling" feel
    pitch_drop = np.linspace(1.005, 1.0, n)
    note2_pd = np.sin(2 * np.pi * 130.81 * np.cumsum(pitch_drop) / SAMPLE_RATE) * 0.15
    note2 += note2_pd
    note2 = note2 * env2
    
    # ── Subtle high "ting" on resolve ──
    ting_start = start2
    ting = np.zeros(n)
    ting_n = n - ting_start
    ting_env = np.exp(-12 * np.arange(ting_n) / SAMPLE_RATE)
    ting_signal = sine(1046.50, duration)[ting_start:ting_start+ting_n] * 0.02  # C6
    ting[ting_start:ting_start+ting_n] = ting_signal * ting_env
    
    # Mix
    mix = note1 + note2 + ting
    
    # Processing
    mix = soft_saturate(mix, drive=1.4)
    mix = lowpass(mix, 3500)
    mix = highpass(mix, 30)
    mix = apply_reverb(mix, wet=0.18, ir_duration=0.3)
    
    write_wav('stop.wav', mix)


def generate_cancel_tone():
    """
    "Cancelled" — Subtle dismissal.
    
    Design: Muted bass thud, barely there. Like gently setting down 
    a heavy book — you feel it ended, but it doesn't demand attention.
    """
    duration = 0.12
    n = int(SAMPLE_RATE * duration)
    t = np.arange(n) / SAMPLE_RATE
    
    # Very fast decay
    env = np.exp(-12 * t) * np.sin(np.linspace(0, np.pi, n))  # hump shape
    
    # Low thud
    thud = sine(82.41, duration) * 0.40   # E2
    thud += sine(55.00, duration) * 0.25   # A1 — very low
    
    # Muted click texture
    click = np.random.randn(n) * 0.04
    click = lowpass(click, 400)
    click = click * np.exp(-30 * t)
    
    mix = (thud + click) * env
    mix = lowpass(mix, 500)   # very muted
    mix = highpass(mix, 25)
    mix = apply_reverb(mix, wet=0.1, ir_duration=0.15)
    
    write_wav('cancel.wav', mix)


def generate_error_tone():
    """
    "Something went wrong" — Gentle warning, not alarming.
    
    Design: Two soft low notes (minor second) — universally understood 
    as "nope" without being annoying.
    """
    duration = 0.30
    n = int(SAMPLE_RATE * duration)
    t = np.arange(n) / SAMPLE_RATE
    
    # Note 1: E3 (164.81 Hz) — 0-140ms
    n1 = int(0.14 * SAMPLE_RATE)
    env1 = np.zeros(n)
    env1[:n1] = envelope_adsr(n1, attack=0.01, decay=0.03, sustain_level=0.6, release=0.06)
    
    note1 = sine(164.81, duration) * 0.35
    note1 += sine(82.41, duration) * 0.15
    note1 = note1 * env1
    
    # Note 2: Eb3 (155.56 Hz) — drops a half-step, minor feel
    start2 = int(0.13 * SAMPLE_RATE)
    n2 = n - start2
    env2 = np.zeros(n)
    env2_raw = envelope_adsr(n2, attack=0.01, decay=0.04, sustain_level=0.5, release=0.10)
    env2[start2:start2+len(env2_raw)] = env2_raw
    
    note2 = sine(155.56, duration) * 0.30
    note2 += sine(77.78, duration) * 0.15
    note2 = note2 * env2
    
    mix = note1 + note2
    mix = soft_saturate(mix, drive=1.3)
    mix = lowpass(mix, 2000)
    mix = highpass(mix, 30)
    mix = apply_reverb(mix, wet=0.12, ir_duration=0.2)
    
    write_wav('error.wav', mix)


# ─────────────────────────────────────────────
# Generate All
# ─────────────────────────────────────────────

if __name__ == '__main__':
    print("🎵 Generating premium sound effects for Yap...\n")
    
    generate_start_tone()
    generate_stop_tone()
    generate_cancel_tone()
    generate_error_tone()
    
    print(f"\n✨ Done! Files saved to {os.path.abspath(OUTPUT_DIR)}")
    print("   Technique: Layered synthesis + ADSR envelopes + biquad filters")
    print("   + soft saturation + convolution reverb")
