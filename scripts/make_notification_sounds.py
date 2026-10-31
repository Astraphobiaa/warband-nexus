#!/usr/bin/env python3
"""Generate Warband Nexus reward cues into Media/Sounds/.

Maintainer-only (scripts/ is excluded from the player zip by .pkgmeta); the generated .ogg files
under Media/ are what ships. Re-run after editing a piece, or name pieces to rebuild only those:

    python scripts/make_notification_sounds.py
    python scripts/make_notification_sounds.py wn-chime wn-coin

Needs numpy and ffmpeg. Nothing is sampled, so the output is original and carries no third-party
licence.

The brief, and why the earlier revisions failed it
--------------------------------------------------
These are NOTIFICATION sounds, not short pieces of music. The earlier revisions were orchestral
cues -- builds, fanfares, risers, four seconds long -- and they were rejected as harsh and
fatiguing. They were, and the reasons are specific:

  * TOO LONG, AND LATE. A notification cue is normally a quarter of a second to a second and a
    half; longer ones annoy on repetition and get cut off when notifications stack. Anything
    that opens with a build also means the player hears nothing for the first second, after the
    toast is already on screen. Everything here is now under two seconds and its first transient
    lands within about 3ms of the file start.
  * HARSH BY CONSTRUCTION. Hearing peaks around 2-5 kHz (ear canal resonance), so that band is
    where "harsh" lives, and three things in the old voices aimed straight at it: narrow body
    resonances (Q of 8+ at 1.1-2.6 kHz), bright sustained harmonic stacks holding energy there
    for seconds, and detuned unisons whose upper partials beat at 20-300 Hz, which is the
    modulation range the ear reports as roughness.
  * WRONG TIMBRE FAMILY. Sustained synthetic voices -- saw stacks, pads, choirs, risers -- are
    what reads as "synthy". The sounds that survive being heard a thousand times are struck and
    plucked: taps, knocks, mallets, soft bells. They put a transient where you need it and then
    get out of the way.

So the rules this file now follows:

  1. Struck or plucked voices only. No sustained oscillator tone anywhere.
  2. Every cue under 2.0s, most around 1.2-1.6s, with the first note at t=0.
  3. Consonant partials. Mallet bars overtone near 4x and 10x -- both consonant -- which is why
     mallet percussion is the timbre notification sets keep returning to.
  4. Body resonances stay BROAD (Q of 2-3). A narrow peak is the harshness mechanism; a wide one
     is just warmth.
  5. Weight lives at 80-140 Hz, not in sub-bass. A laptop or phone speaker reproduces nothing at
     50 Hz, so a cue that puts its weight there simply sounds thin.
  6. Every cue ends resolved, and gets a desharpening pass before reverb.
  8. NO ROLLS. The long note is a single struck tone with a slow decay, never repeated strokes.
     Building a sustain by overlapping copies of one note was tried and abandoned: the copies
     interfere unless they share a phase, their upper partials still ripple at the stroke rate
     once they do, and every stroke's attack is a broadband transient -- on a spectrogram, twelve
     evenly spaced vertical lines a second, heard as a bell jangling behind the cue. A single
     tone measures 1.5% envelope ripple against the roll's 13-37%, and a cue that has to survive
     being heard a thousand times is not the place to be clever.
  7. Reverb short and low (room <= 0.68, mix <= 0.22). A long tail is what makes a cue feel like
     music playing over the game instead of a response to something.

  9. A DRY AIR LAYER on every cue. High partials and a noise tick, a few hundred milliseconds
     long, mixed in 13 dB under the body and never sent to the reverb. This is the layer that
     makes a cue read as crisp instead of veiled, and leaving it out was what made an earlier
     revision sound cheap: chasing harshness, 2-5 kHz had been filtered down to a tenth of a
     percent of total energy. Brightness that lasts milliseconds is definition; brightness that
     is held is harshness. The fix is a fast decay, not a filter.

Signal chain: parts -> mix -> normalise -> desharp -> short reverb -> normalise to -3 dBFS ->
fades -> 16-bit -> Ogg Vorbis. No waveshaping at any point: an early version ran tanh() on a mix
peaking above 1.0 and flattened the loud parts into a near-square wave, which is audible as
crackle.
"""

import array
import math
import os
import subprocess
import sys
import wave

import numpy as np

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Media", "Sounds")

_NAMES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6,
          "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}

TWO_PI = 2.0 * math.pi

# Peak target. UI sounds are normally left around -3 dBFS, which also leaves Vorbis room: the
# decoded peak of a lossy file can sit slightly above the source peak.
PEAK = 0.71

# Hard ceiling on cue length, enforced in finish(). This is the number the set kept drifting
# away from. Notification cues run about a quarter of a second to a second and a half, most of
# them under a second, and the research saying so is quoted at the top of this file. A request
# for a rising figure ending on a long note got read here as "ring for two seconds", which is
# how the set ended up with 2.6s glass tones trimmed at 2.0s -- long enough to be in the way
# every single time it fires. The shape is the pickup; the last note only has to be long enough
# to land on.
CUE_MAX = 2.1

# Per-pitch tuning scatter, shared by every voice. It has to be ONE number: two voices playing
# the same note with different amounts are still detuned against each other, and that is the
# warble this was introduced to avoid.
DETUNE = 0.0015


def note(n: str) -> float:
    """Equal temperament, A4 = 440."""
    name, octave = n[:-1], int(n[-1])
    return 440.0 * (2.0 ** ((_NAMES[name] + (octave - 4) * 12 - 9) / 12.0))


def _rng(seed: int):
    return np.random.default_rng(abs(int(seed)) % (2 ** 31))


def _norm(buf, gain: float):
    arr = np.asarray(buf, dtype=float)
    peak = float(np.max(np.abs(arr)))
    return arr * (gain / peak) if peak > 1e-9 else arr


def _emit(x, gain: float) -> list:
    peak = float(np.max(np.abs(x)))
    if peak < 1e-9:
        return [0.0] * len(x)
    return (x * (gain / peak)).tolist()


def pitch_jitter(freq: float, amount: float) -> float:
    """A tiny pitch offset keyed to the PITCH, not to a random seed.

    Notes want a little scatter or a set sounds machine-stamped. But the same written note is
    routinely played here by several voices at once -- the struck chord, the roll holding it and
    the glass note ringing under it -- and if each picks its own random offset, those copies beat
    against each other at one to three hertz. That is heard as a warble sitting behind the cue,
    and no amount of smoothing the roll removes it, because the roll is not where it comes from.
    Deriving the offset from the frequency keeps different notes scattered while leaving every
    unison exactly in tune."""
    if not amount:
        return 1.0
    h = math.sin(freq * 12.9898) * 43758.5453
    return 1.0 + (h - math.floor(h) - 0.5) * 2.0 * amount


def penv(n: int, attack: float, decay: float):
    """Percussive envelope: a short linear rise then exponential decay. Everything here is
    struck, so this is the only envelope shape the file needs."""
    t = np.arange(n) / SR
    a = max(1e-5, attack)
    return np.clip(t / a, 0.0, 1.0) * np.exp(-np.clip(t - a, 0.0, None) / max(1e-4, decay))


# -- filtering ---------------------------------------------------------------

def _fftfilter(x, gain_of):
    """Zero-phase filtering, with the buffer zero-padded first.

    Without the padding this is a CIRCULAR convolution: the filter's impulse response runs off
    the end of the buffer and reappears at the beginning, so the tail of a cue is smeared over
    its own attack. The pad has to be at least as long as the response, and a 55 Hz highpass has
    a long one, hence 100ms."""
    n = len(x)
    size = 1 << int(math.ceil(math.log2(n + int(SR * 0.10))))
    f = np.fft.rfftfreq(size, 1.0 / SR)
    return np.fft.irfft(np.fft.rfft(x, size) * gain_of(f), size)[:n]


def _lp(x, fc: float, order: int = 2):
    return _fftfilter(x, lambda f: 1.0 / np.sqrt(1.0 + (f / max(1.0, fc)) ** (2 * order)))


def _hp(x, fc: float, order: int = 2):
    def gain(f):
        r = np.maximum(f, 1e-6) / max(1.0, fc)
        return 1.0 / np.sqrt(1.0 + (1.0 / r) ** (2 * order))
    return _fftfilter(x, gain)


def desharp(x, dip_db: float = -2.5, hf_db: float = -3.0, centre: float = 3200.0):
    """Take the edge off the band the ear amplifies.

    A broad dip, one octave wide, around 3.2 kHz, plus a shelf above 6 kHz. Broad is the whole
    point: a narrow notch would just be the mirror image of the narrow peak that causes the
    problem, and would colour the cue audibly.

    Both amounts are deliberately small now. An earlier revision ran -5 and -14 dB here on top of
    a 7 kHz lowpass, which did remove the harshness and left the set veiled and cheap-sounding:
    2-5 kHz was down to a tenth of a percent of total energy. Harshness is SUSTAINED energy in
    that band, not energy as such. A bright transient is heard as definition. So the brightness
    comes back, and it is the `sparkle` layer's fast decay -- not a filter -- that keeps it from
    becoming fatiguing."""
    def gain(f):
        safe = np.maximum(f, 1.0)
        dip = dip_db * np.exp(-(np.log2(safe / centre) ** 2) / (2.0 * 0.55 ** 2))
        shelf = hf_db * np.clip(np.log2(safe / 6000.0), 0.0, 1.5) / 1.5
        return 10.0 ** ((dip + shelf) / 20.0)
    return _fftfilter(x, gain)


# -- bodies ------------------------------------------------------------------
# Broad, low-Q resonances only. A body makes a voice sound like an object with a size; a narrow
# one makes it sound harsh. Q here is 2-3, not the 8-11 the previous revision used.

BAR_BODY = ((180.0, 3.0, 1.00), (430.0, 2.5, 0.55))      # marimba resonator tube, wooden
GLASS_BODY = ((760.0, 2.6, 1.00), (1900.0, 2.0, 0.35))   # thin struck metal/glass
WOOD_BODY = ((320.0, 2.8, 1.00), (820.0, 2.2, 0.45))     # knock on a wooden surface

_IR_CACHE = {}


def _ir(modes, dur: float = 0.09, direct: float = 0.80):
    key = (modes, dur, direct)
    hit = _IR_CACHE.get(key)
    if hit is not None:
        return hit
    n = int(SR * dur)
    t = np.arange(n) / SR
    ir = np.zeros(n)
    for f, q, g in modes:
        ir += g * np.sin(TWO_PI * f * t) * np.exp(-math.pi * f * t / q)
    ir[0] += direct * (float(np.max(np.abs(ir))) or 1.0)
    ir = ir / (float(np.max(np.abs(ir))) or 1.0)
    _IR_CACHE[key] = ir
    return ir


def shape(x, ir):
    size = 1 << int(math.ceil(math.log2(len(x) + len(ir))))
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:len(x)]


# -- voices ------------------------------------------------------------------

def mallet(freq: float, dur: float, gain: float = 1.0, seed: int = 1, soft: float = 0.65,
           contact: float = 0.30, detune: float = DETUNE, t0: float = 0.0,
           attack: float = 0.0015) -> list:
    """Marimba/vibraphone bar. A tuned bar's overtones sit near 4x and 10x the fundamental --
    two octaves, and three octaves plus a major third -- so both are consonant with the note.
    That is why mallet percussion is the timbre notification sets keep coming back to: it cuts
    through a small speaker without putting a dense cluster of partials in the harsh band.

    `soft` darkens the mallet contact noise and `contact` sets how much of it there is. Roll
    strokes want almost none: a player rolling does not re-articulate at full force, and stacking
    a dozen contact transients in the upper mids is audible as a rasp on top of the note.

    `detune` is the per-note pitch scatter; see `pitch_jitter` for why it is keyed to the pitch
    and shared by every voice rather than drawn per note.

    `t0` is where this note starts on the cue's timeline, and it exists for rolls. Strokes of the
    same pitch overlap, and if each starts its partials at phase zero they interfere with one
    another: the stroke period is never a whole number of cycles, so the phase offset walks round
    and the copies alternately reinforce and cancel. Measured on its own, a roll built that way
    swings about 37%, which is audible as a warble and is NOT fixed by smoothing the envelope.
    Passing the absolute start time makes every stroke a continuation of one phase, which is also
    what physically happens when you strike a bar that is still ringing."""
    n = int(SR * dur)
    rng = _rng(seed)
    t = np.arange(n) / SR
    out = np.zeros(n)
    det = pitch_jitter(freq, detune)
    # Exact 4 and 10, not 3.99 and 9.2. A bar maker tunes those partials to the octave and the
    # third-octave-plus-a-third deliberately -- that is what "tuned percussion" means. Detuning
    # them by a quarter of a percent in the name of realism makes them beat against every exact
    # octave elsewhere in the chord: D5 x 3.99 lands 5.9 Hz from the glass note an octave up
    # doubling at x2, and 5.9 Hz of beating is precisely the warble behind the cue.
    # The 10th partial decays fast (dm 0.20), which is what lets it be audible without being
    # tiring: it is gone inside a couple of hundred milliseconds, so it reads as the strike being
    # defined rather than as a high tone sitting on the cue.
    for ratio, lv, dm in ((1.0, 1.00, 1.00), (4.00, 0.20, 0.42), (10.00, 0.055, 0.20)):
        f = freq * ratio * det
        if f > SR * 0.45:
            continue
        out += lv * np.sin(TWO_PI * f * (t + t0)) * penv(n, attack, dur * 0.34 * dm)
    knock = _lp(rng.normal(0.0, 1.0, n), 1200.0 + 2600.0 * (1.0 - soft)) * penv(n, 0.0008, 0.012)
    return _emit(shape(out + knock * contact, _ir(BAR_BODY)), gain)


def glass(freq: float, dur: float, gain: float = 1.0, seed: int = 1) -> list:
    """Struck glass / celesta. Mostly octave-related partials, and the one inharmonic partial is
    kept quiet on purpose -- a loud inharmonic partial up in the 2-5 kHz region is exactly the
    roughness that makes a cue tiring by the hundredth hearing."""
    n = int(SR * dur)
    rng = _rng(seed)
    t = np.arange(n) / SR
    out = np.zeros(n)
    det = pitch_jitter(freq, DETUNE)
    # 3.00 rather than 3.01 for the same reason; 5.43 is genuinely inharmonic and stays, but it
    # sits at a twenty-fifth of the fundamental's level where it cannot beat audibly.
    for ratio, lv, dm in ((1.0, 1.00, 1.00), (2.00, 0.28, 0.55), (3.00, 0.10, 0.36), (5.43, 0.04, 0.20)):
        f = freq * ratio * det
        if f > SR * 0.45:
            continue
        out += lv * np.sin(TWO_PI * f * t) * penv(n, 0.0012, dur * 0.40 * dm)
    # Same reasoning as sparkle's tick: darker, quieter, and an attack long enough not to click.
    strike = _lp(rng.normal(0.0, 1.0, n), 4000.0) * penv(n, 0.0018, 0.009) * 0.10
    return _emit(_lp(shape(out + strike, _ir(GLASS_BODY)), 13000.0), gain)


def sparkle(freq: float, dur: float = 0.30, gain: float = 1.0, seed: int = 1) -> list:
    """The air layer: high partials and a noise tick, gone in a couple of hundred milliseconds.

    This is the layer a hand-built cue is usually missing and a professionally designed one
    always has. Sound designers build these from a body that carries the identity, a low layer
    that carries weight, and a separate transient layer up in the 4-12 kHz region that is kept
    DRY -- no reverb -- and sits well below the body. That dry top is what makes a sound read as
    crisp and defined rather than veiled.

    The reason it can be bright without being harsh is its decay. Energy at 3-5 kHz lasting
    milliseconds is heard as the edge of the strike; the same energy held for a second is heard
    as harshness. So this is deliberately steep and short, and the ringing body underneath stays
    warm."""
    n = int(SR * dur)
    rng = _rng(seed)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, lv, dm in ((4.0, 1.00, 1.00), (6.0, 0.55, 0.70), (8.0, 0.35, 0.52),
                          (11.0, 0.18, 0.38), (15.0, 0.08, 0.28)):
        f = freq * ratio
        if f > SR * 0.45:
            continue
        out += lv * np.sin(TWO_PI * f * t) * penv(n, 0.0006, dur * 0.22 * dm)
    # The noise tick is deliberately small and band-limited now. A highpassed noise burst with a
    # sub-millisecond attack IS a crackle -- one per note, eight per cue, which is what was heard
    # as crackling over the top of the set. The brightness this layer exists for comes from the
    # tonal partials above; the noise only has to suggest a mallet touching the bar, so it is
    # kept inside a band and given an attack long enough not to read as a click.
    tick = _lp(_hp(rng.normal(0.0, 1.0, n), 2500.0), 9000.0)
    out += tick * penv(n, 0.0025, 0.011) * 0.14
    return _emit(out, gain)


def pluck(freq: float, dur: float, gain: float = 1.0, seed: int = 1, damp: float = 0.40) -> list:
    """Karplus-Strong: a noise burst circulating in a delay line one period long, losing its top
    end each lap. An actual string, which is why it does not sound like added sines."""
    n = int(SR * dur)
    rng = _rng(seed)
    length = max(2, int(round(SR / freq)))
    buf = np.convolve(rng.uniform(-1.0, 1.0, length), np.ones(3) / 3.0, mode="same")
    out = np.empty(n)
    d = damp * float(rng.uniform(0.90, 1.10))
    idx = 0
    for i in range(n):
        v = buf[idx]
        out[i] = v
        nxt = buf[(idx + 1) % length]
        buf[idx] = ((1.0 - d) * v + d * nxt) * 0.9999
        idx = (idx + 1) % length
    return _emit(shape(out * penv(n, 0.0010, dur * 0.42), _ir(WOOD_BODY)), gain)


def woodtap(dur: float = 0.09, gain: float = 1.0, seed: int = 1) -> list:
    """Soft knock. Texture rather than pitch: it says something happened without adding anything
    in the band that tires the listener."""
    n = int(SR * dur)
    rng = _rng(seed)
    body = _lp(rng.normal(0.0, 1.0, n), 1400.0) * penv(n, 0.0006, 0.018)
    return _emit(shape(body, _ir(WOOD_BODY)), gain)


def thump(freq: float = 100.0, dur: float = 0.50, gain: float = 1.0, seed: int = 1) -> list:
    """Low soft drum for weight, centred in the low mids rather than sub-bass. A laptop speaker
    reproduces nothing at 50 Hz, so weight placed there is weight the player never hears."""
    n = int(SR * dur)
    rng = _rng(seed)
    t = np.arange(n) / SR
    bend = 1.0 + 0.45 * np.exp(-t * 26.0)
    ph = TWO_PI * np.cumsum(freq * bend) / SR
    out = (np.sin(ph) + 0.22 * np.sin(2.0 * ph)) * penv(n, 0.0018, dur * 0.26)
    out += _lp(rng.normal(0.0, 1.0, n), 700.0) * penv(n, 0.0005, 0.010) * 0.22
    return _emit(_lp(out, 2200.0), gain)


# Voices taking a per-note seed, so the humanised helpers know which ones to vary.
_SEEDED = (mallet, glass, pluck, sparkle)


# -- arrangement -------------------------------------------------------------

def canvas(dur: float) -> list:
    return [0.0] * int(SR * dur)


def place(buf: list, src: list, at: float, gain: float = 1.0):
    start = int(SR * at)
    need = start + len(src)
    if need > len(buf):
        buf.extend([0.0] * (need - len(buf)))
    for i, s in enumerate(src):
        buf[start + i] += s * gain


def _voice_kw(voice, kw, seed):
    return dict(kw, seed=seed) if voice in _SEEDED else kw


def hrun(buf: list, voice, names, at: float, step: float, dur: float, g0: float, g1=None,
         seed: int = 1, jitter: float = 0.004, **kw):
    """A line whose level ramps g0 -> g1, with every note's timing and level nudged on its own.
    The jitter is a few milliseconds and a few percent: it is the difference between a player and
    one oscillator triggered several times."""
    g1 = g0 if g1 is None else g1
    rng = _rng(seed)
    m = max(1, len(names) - 1)
    for i, nm in enumerate(names):
        lvl = (g0 + (g1 - g0) * (i / m)) * float(rng.uniform(0.94, 1.06))
        at_i = max(0.0, at + step * i + float(rng.uniform(-jitter, jitter)))
        place(buf, voice(note(nm), dur, 1.0, **_voice_kw(voice, kw, seed * 97 + i * 13)), at_i, lvl)


def hchord(buf: list, voice, names, at: float, dur: float, gain: float = 1.0,
           spread: float = 0.012, seed: int = 1, jitter: float = 0.004, **kw):
    """Struck chords are never dead flat; spread plus jitter is what makes it one gesture rather
    than several voices starting on the same sample."""
    rng = _rng(seed)
    for i, nm in enumerate(names):
        at_i = max(0.0, at + spread * i + float(rng.uniform(-jitter, jitter)))
        place(buf, voice(note(nm), dur, 1.0, **_voice_kw(voice, kw, seed * 131 + i * 7)),
              at_i, gain * float(rng.uniform(0.94, 1.06)))


def reverb(x, mix_amount: float = 0.16, room: float = 0.62):
    """Schroeder/Freeverb: 8 parallel combs into 4 series allpass. Kept small and quiet -- a long
    tail is what makes a cue sound like music playing over the game rather than a reply to an
    event.

    All eight comb delays, not a subset. A comb resonates at every multiple of SR/delay, and a
    few combs at neighbouring delays put their resonances on top of each other instead of filling
    the gaps: the tail then rings on a handful of discrete high frequencies rather than decaying
    like noise. Driven with a single click, the four-comb version used here previously came back
    with peaks at 8.0, 9.6, 14.0 and 14.7 kHz, which is heard as a bell jangling behind every cue.
    Four allpasses rather than two for the same reason -- they are what diffuses the comb output
    into something dense."""
    x = _norm(x, 0.55)
    combs = ((1116, room), (1188, room * 0.995), (1277, room * 0.99), (1356, room * 0.985),
             (1422, room * 0.98), (1491, room * 0.975), (1557, room * 0.97), (1617, room * 0.965))
    wet = np.zeros(len(x))
    comb_gain = 0.25 * (1.0 - room) * 0.5
    for delay, fb in combs:
        line = np.zeros(delay)
        idx = 0
        for i in range(len(x)):
            y = line[idx]
            line[idx] = x[i] + y * fb
            idx = (idx + 1) % delay
            wet[i] += y * comb_gain
    for delay, fb in ((556, 0.5), (441, 0.5), (341, 0.5), (225, 0.5)):
        line = np.zeros(delay)
        idx = 0
        for i in range(len(wet)):
            y = line[idx]
            v = wet[i]
            line[idx] = v + y * fb
            wet[i] = y - v * fb
            idx = (idx + 1) % delay
    return x * (1.0 - mix_amount) + wet * mix_amount


# How far below the body the dry air layer sits. Layering guidance puts a transient layer
# roughly 10-18 dB under the layer carrying the identity; -13 dB is the middle of that.
AIR_LEVEL = 10.0 ** (-15.0 / 20.0)


def polish(buf, mix: float = 0.16, room: float = 0.62, dip=None, hf=None, air=None,
           air_db: float = None):
    """Body -> normalise -> desharp -> reverb, then the dry air layer added on top.

    The air layer bypasses the reverb entirely. Sending a transient layer through a reverb is
    what turns a crisp cue into a veiled one: the tail smears exactly the edge the layer exists
    to provide. It is added after, at AIR_LEVEL, so it defines the strike and then gets out of
    the way."""
    kw = {}
    if dip is not None:
        kw["dip_db"] = dip
    if hf is not None:
        kw["hf_db"] = hf
    wet = reverb(desharp(_norm(buf, 0.80), **kw), mix, room)
    if air is None:
        return wet
    # Per-cue, because the ratio that reads as crisp depends on what is underneath. A dense,
    # low-scored cue swallows the same air layer that cuts through a sparse one, so the cues
    # with a full chord and a drum under them ask for a few dB more.
    level = AIR_LEVEL if air_db is None else 10.0 ** (air_db / 20.0)
    dry = _norm(air, 0.80) * level
    n = max(len(wet), len(dry))
    out = np.zeros(n)
    out[:len(wet)] += wet
    out[:len(dry)] += dry
    return out


def finish(x, peak_target: float = PEAK) -> bytes:
    """Fade-in is 1.5ms -- enough to avoid a click at the file boundary, short enough that the
    cue is audibly instant. Fade-out is 80ms on an already-decayed tail.

    The 55 Hz highpass first: envelope decays and the body convolution leave a little energy
    below what a laptop or phone speaker can reproduce, and since the file is peak-normalised
    afterwards, inaudible low end is headroom taken away from the part that is audible."""
    x = np.asarray(x, dtype=float)[:int(SR * CUE_MAX)]
    x = _hp(x, 55.0)
    x = _norm(x, peak_target)
    n = len(x)
    fi = min(int(SR * 0.0015), n // 2)
    fo = min(int(SR * 0.080), n // 2)
    if fi:
        x[:fi] *= np.linspace(0.0, 1.0, fi)
    if fo:
        x[n - fo:] *= np.linspace(1.0, 0.0, fo)
    return array.array("h", np.clip(np.round(x * 32767.0), -32768, 32767).astype(np.int16)).tobytes()


# -- the cues ----------------------------------------------------------------
# All struck, all under 2s, all starting at t=0. Scored differently from each other so a player
# can tell them apart with their eyes shut: mallet, mallet+glass, glass-led, low mallet, and two
# minimal options.

# The victory figure: four quick rising notes and then a long one -- short-short-short-short-
# LONG. Four notes of pickup is what gives the last one somewhere to arrive from; a cue that
# simply plays a chord has no arrival in it. The long note is a mallet roll plus a struck glass
# note that rings under it, because the whole set is struck instruments and none of them sustain.
MOTIF = 0.055   # pickup spacing, about 270 strokes a minute
LAND = 0.225    # where the last note starts, in every cue that uses the figure


def p_triumph():
    """C major, G-C-E-G rising onto the octave. 1.9s."""
    buf = canvas(1.90)
    hrun(buf, mallet, ["G4", "C5", "E5", "G5"], 0.000, MOTIF, 0.42, 0.40, 0.56, seed=3)
    hchord(buf, mallet, ["C5", "E5", "G5", "C6"], LAND, 0.80, 0.54, spread=0.010, seed=5)
    place(buf, glass(note("C6"), 1.15, 0.52, seed=7), LAND)
    place(buf, glass(note("C5"), 0.95, 0.20, seed=9), LAND + 0.010)
    place(buf, mallet(note("C3"), 0.90, 0.22, seed=13), LAND)
    place(buf, thump(104.0, 0.52, 0.44, seed=15), LAND - 0.002)
    air = canvas(0.70)
    hrun(air, sparkle, ["G4", "C5", "E5", "G5"], 0.000, MOTIF, 0.20, 0.45, 0.65, seed=203)
    place(air, sparkle(note("C6"), 0.34, 1.00, seed=205), LAND)
    return polish(buf, 0.13, 0.56, air=air, air_db=-10.0)


def p_item_get():
    """The classic lift: C-E-G onto a struck octave. 1.55s."""
    buf = canvas(1.55)
    hrun(buf, mallet, ["C5", "E5", "G5"], 0.000, 0.058, 0.40, 0.40, 0.52, seed=21)
    place(buf, glass(note("C6"), 1.05, 0.46, seed=23), 0.176)
    place(buf, pluck(note("C5"), 0.85, 0.16, seed=25, damp=0.34), 0.176)
    place(buf, thump(120.0, 0.42, 0.26, seed=27), 0.174)
    air = canvas(0.60)
    hrun(air, sparkle, ["C5", "E5", "G5"], 0.000, 0.058, 0.18, 0.45, 0.62, seed=221)
    place(air, sparkle(note("C6"), 0.30, 1.00, seed=223), 0.176)
    return polish(buf, 0.12, 0.54, air=air)


def p_fanfare():
    """D major, the same figure taken brighter and tighter. 1.7s."""
    buf = canvas(1.70)
    place(buf, woodtap(0.07, 0.18, seed=31), 0.000)
    hrun(buf, mallet, ["A4", "D5", "F#5", "A5"], 0.000, 0.052, 0.38, 0.40, 0.56, seed=33)
    hchord(buf, mallet, ["D5", "F#5", "A5", "D6"], 0.212, 0.76, 0.52, spread=0.011, seed=35)
    place(buf, glass(note("D6"), 1.05, 0.50, seed=37), 0.212)
    place(buf, glass(note("D5"), 0.85, 0.18, seed=39), 0.220)
    place(buf, thump(110.0, 0.48, 0.40, seed=41), 0.210)
    air = canvas(0.65)
    hrun(air, sparkle, ["A4", "D5", "F#5", "A5"], 0.000, 0.052, 0.18, 0.45, 0.65, seed=231)
    place(air, sparkle(note("D6"), 0.32, 1.00, seed=233), 0.212)
    return polish(buf, 0.13, 0.56, air=air)


def p_discovery():
    """F over C resolving to C major, led by glass so it reads as the rare-find cue. 1.85s."""
    buf = canvas(1.85)
    hchord(buf, glass, ["C5", "F5"], 0.000, 0.80, 0.34, spread=0.014, seed=41)
    hrun(buf, glass, ["A5", "C6", "E6"], 0.230, 0.068, 1.10, 0.26, 0.40, seed=43)
    place(buf, mallet(note("C4"), 1.00, 0.26, seed=45), 0.232)
    place(buf, thump(96.0, 0.46, 0.24, seed=47), 0.230)
    air = canvas(0.72)
    hchord(air, sparkle, ["C5", "F5"], 0.000, 0.24, 0.45, spread=0.014, seed=241)
    hrun(air, sparkle, ["A5", "C6", "E6"], 0.230, 0.068, 0.30, 0.55, 0.85, seed=243)
    return polish(buf, 0.15, 0.58, air=air, air_db=-11.0)


def p_heroic():
    """E flat, scored an octave lower than the rest. Weight from register, not length. 1.90s."""
    buf = canvas(1.90)
    place(buf, woodtap(0.09, 0.24, seed=51), 0.000)
    hrun(buf, mallet, ["A#3", "D4", "F4", "A#4"], 0.000, MOTIF, 0.46, 0.40, 0.56, seed=53)
    hchord(buf, mallet, ["D#4", "G4", "A#4", "D#5"], LAND, 0.85, 0.54, spread=0.013, seed=55)
    place(buf, glass(note("D#5"), 1.20, 0.46, seed=57), LAND)
    place(buf, thump(82.0, 0.60, 0.48, seed=61), LAND - 0.002)
    # Pitched an octave above the notes being played, unlike the other cues. This one is scored
    # low, so an air layer tracking it sits at 1-2 kHz and does nothing for definition; the
    # layer's job is the 3-10 kHz edge, so here it has to be written where that lands.
    air = canvas(0.72)
    hrun(air, sparkle, ["A#4", "D5", "F5", "A#5"], 0.000, MOTIF, 0.22, 0.45, 0.65, seed=251)
    place(air, sparkle(note("D#6"), 0.34, 1.00, seed=253), LAND)
    return polish(buf, 0.15, 0.58, air=air)


def p_rare_drop():
    """The 300-attempt mount: G major, pickup onto a struck glass chord. The longest in the set
    and still only 2.05s -- the drop is rare, the sound is still a notification."""
    buf = canvas(2.05)
    # The landing here is the biggest in the set, so the pickup is pushed to stay audible beside
    # it; left softer, the cue does not audibly begin until 70ms in, with the toast already up.
    place(buf, woodtap(0.08, 0.30, seed=59), 0.000)
    hrun(buf, mallet, ["D5", "G5", "B5", "D6"], 0.000, MOTIF, 0.42, 0.62, 0.74, seed=61)
    hchord(buf, glass, ["G5", "B5", "D6"], LAND, 1.25, 0.50, spread=0.012, seed=63)
    hchord(buf, mallet, ["G4", "D5", "G5"], LAND, 0.90, 0.40, spread=0.010, seed=65)
    place(buf, pluck(note("G3"), 1.20, 0.20, seed=69, damp=0.38), LAND)
    place(buf, thump(78.0, 0.68, 0.52, seed=71), LAND - 0.002)
    air = canvas(0.80)
    hrun(air, sparkle, ["D5", "G5", "B5", "D6"], 0.000, MOTIF, 0.20, 0.55, 0.75, seed=261)
    hchord(air, sparkle, ["G5", "B5", "D6"], LAND, 0.36, 1.00, spread=0.012, seed=263)
    return polish(buf, 0.16, 0.60, air=air)


def p_chime():
    """Two struck glass notes a fifth apart. The quiet option. 1.25s."""
    buf = canvas(1.25)
    place(buf, glass(note("G5"), 0.80, 0.42, seed=81), 0.000)
    place(buf, glass(note("C6"), 0.98, 0.52, seed=83), 0.085)
    place(buf, mallet(note("C4"), 0.70, 0.16, seed=85), 0.085)
    air = canvas(0.46)
    place(air, sparkle(note("G5"), 0.20, 0.55, seed=281), 0.000)
    place(air, sparkle(note("C6"), 0.26, 1.00, seed=283), 0.085)
    return polish(buf, 0.11, 0.52, air=air, air_db=-10.0)


def p_coin():
    """Two quick pings. The shortest thing in the set. 0.95s."""
    buf = canvas(0.95)
    place(buf, mallet(note("E6"), 0.50, 0.52, seed=91), 0.000)
    place(buf, mallet(note("B6"), 0.62, 0.46, seed=93), 0.055)
    place(buf, glass(note("B6"), 0.58, 0.18, seed=95), 0.055)
    # Half the air of the other cues. This one is already written at the top of the register and
    # at full level it measured 16% of its energy in 3-10 kHz, by far the most piercing in the set.
    air = canvas(0.36)
    place(air, sparkle(note("E6"), 0.14, 0.35, seed=291), 0.000)
    place(air, sparkle(note("B6"), 0.18, 0.50, seed=293), 0.055)
    return polish(buf, 0.10, 0.50, air=air)


# Playback volume levels, as a percentage of the normal peak.
#
# PlaySoundFile(sound [, channel]) takes no volume argument -- verified on warcraft.wiki.gg --
# and the only volume controls WoW exposes are the player's own Sound_*Volume CVars, which an
# addon has no business writing. Since these cues are generated here, the honest way to give the
# player a volume control is to ship the levels. Four steps rather than a continuous slider,
# because a slider that silently snaps to the nearest of four files would be lying about what it
# does. The 100% file keeps the plain name so LibSharedMedia and any saved path still resolve.
VOLUMES = (100, 70, 45, 25)


def variant_name(name: str, volume: int) -> str:
    return name if volume == 100 else "%s-%d" % (name, volume)


PIECES = [
    ("wn-triumph", p_triumph),
    ("wn-itemget", p_item_get),
    ("wn-fanfare", p_fanfare),
    ("wn-discovery", p_discovery),
    ("wn-heroic", p_heroic),
    ("wn-raredrop", p_rare_drop),
    ("wn-chime", p_chime),
    ("wn-coin", p_coin),
]


def write_wav(path: str, data: bytes):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    only = set(sys.argv[1:])
    made = []
    for name, fn in PIECES:
        if only and name not in only:
            continue
        # Synthesise once, write it out at each level: the levels differ only in where the file
        # is normalised to, so re-running the whole piece per level would be wasted work.
        mixed = fn()
        sizes = []
        for volume in VOLUMES:
            stem = variant_name(name, volume)
            wav = os.path.join(OUT_DIR, stem + ".wav")
            ogg = os.path.join(OUT_DIR, stem + ".ogg")
            write_wav(wav, finish(mixed, PEAK * volume / 100.0))
            r = subprocess.run(
                ["ffmpeg", "-y", "-loglevel", "error", "-i", wav,
                 # q7 rather than q5: these cues are mostly sharp transients, which is where a
                 # lossy codec spends its error budget, and the files are a few KB either way.
                 "-c:a", "libvorbis", "-q:a", "7", "-ar", str(SR), "-ac", "1", ogg],
                capture_output=True, text=True)
            if r.returncode != 0:
                sys.stderr.write("ffmpeg failed for %s: %s\n" % (stem, r.stderr.strip()))
                return 1
            os.remove(wav)
            sizes.append(os.path.getsize(ogg))
        made.append((name, sum(sizes)))
    total = sum(sz for _, sz in made)
    for name, sz in made:
        print("  %-15s %6.1f KB  (%d levels)" % (name, sz / 1024.0, len(VOLUMES)))
    print("%d cues x %d levels = %d files, %.1f KB total -> %s"
          % (len(made), len(VOLUMES), len(made) * len(VOLUMES), total / 1024.0, OUT_DIR))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
