"""Music loops: dusty desert western meets scrap-yard industrial. Each track renders seamlessly
loopable stereo audio (the reverb tail is folded back onto the start)."""

import numpy as np

from dsp import (SR, adsr, drive, env, filt, glide, midi, noise, osc, pink, pluck, reverb, sweep_filt)


class Track:
    def __init__(self, bpm, bars, rng, beats_per_bar=4):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.bars = bars
        self.bpb = beats_per_bar
        self.length = int(round(bars * beats_per_bar * self.beat * SR))
        self.tail = int(4.0 * SR)
        self.rng = rng
        self.buses = {}

    def bus(self, name):
        if name not in self.buses:
            self.buses[name] = np.zeros((self.length + self.tail, 2))
        return self.buses[name]

    def at(self, bar, beat=0.0):
        return int(round((bar * self.bpb + beat) * self.beat * SR))

    def add(self, name, sig, start, gain=1.0, pan=0.0):
        b = self.bus(name)
        if start >= len(b):
            return
        end = min(len(b), start + len(sig))
        l = np.sqrt(0.5 * (1.0 - pan))
        r = np.sqrt(0.5 * (1.0 + pan))
        b[start:end, 0] += sig[: end - start] * gain * l
        b[start:end, 1] += sig[: end - start] * gain * r

    def mix(self, sends):
        """sends: bus -> (gain, reverb mix, reverb size). Returns the looped stereo master."""
        out = np.zeros((self.length + self.tail, 2))
        for name, b in self.buses.items():
            g, wet, size = sends.get(name, (1.0, 0.15, 1.0))
            for ch in range(2):
                x = b[:, ch]
                if wet > 0:
                    x = reverb(x, size=size * (1.0 if ch == 0 else 1.07), mix=wet)
                out[:, ch] += x * g
        loop = out[: self.length].copy()
        loop[: self.tail] += out[self.length:]
        loop = drive(loop * 1.1, 1.3)
        return loop / max(1e-9, np.max(np.abs(loop))) * 0.9


# ---------------------------------------------------------------- instruments

def kick(rng, punch=1.0):
    n = int(0.35 * SR)
    body = osc(glide(140, 42, n, 0.35), n) * env(n, 0.001, 0.22)
    click = filt(noise(n, rng), "high", 3000) * env(n, 0.0, 0.004) * 0.4
    return drive(body * punch + click, 2.0)


def snare(rng, dirt=1.0):
    n = int(0.3 * SR)
    tone = osc(glide(230, 180, n), n) * env(n, 0.0, 0.06)
    rattle = filt(noise(n, rng), "band", (1200, 8000)) * env(n, 0.001, 0.13) * dirt
    return drive(tone * 0.7 + rattle, 1.8)


def hat(rng, open_=False):
    n = int((0.25 if open_ else 0.06) * SR)
    return filt(noise(n, rng), "high", 7000) * env(n, 0.0, 0.18 if open_ else 0.03)


def clank(rng, f=None):
    """Scrap metal percussion: a few inharmonic partials."""
    n = int(0.4 * SR)
    f = f or rng.uniform(300, 520)
    x = sum(osc(f * r, n) * env(n, 0.0, d) * a for r, d, a in ((1.0, 0.25, 1.0), (2.41, 0.14, 0.6), (3.93, 0.08, 0.4), (5.7, 0.05, 0.3)))
    return x * 0.5 + filt(noise(n, rng), "band", (800, 4000)) * env(n, 0.0, 0.01) * 0.5


def shaker(rng):
    n = int(0.09 * SR)
    return filt(noise(n, rng), "band", (3000, 9000)) * adsr(n, 0.02, 0.02, 0.4, 0.04)


def bass(note, dur, rng, cut=900.0, dirt=2.0):
    n = int(dur * SR)
    f = midi(note)
    x = osc(f, n, shape="saw") + osc(f * 0.5, n, shape="square") * 0.5
    x = sweep_filt(x, "low", cut * 2.5, cut * 0.5) * adsr(n, 0.004, 0.08, 0.7, 0.04)
    return filt(drive(x, dirt), "low", cut * 3.5)


def guitar(note, dur, rng, dist=0.0, bright=0.6):
    x = pluck(midi(note), dur + 0.05, rng, bright=bright, damp=0.997)[: int(dur * SR)]
    x = x * adsr(len(x), 0.001, 0.05, 1.0, 0.04)
    if dist > 0:
        x = filt(drive(x * dist, 3.0), "low", 3500)
    return x


def power_chord(root, dur, rng, dist=4.0):
    x = sum(guitar(root + iv, dur, rng, 0.0, 0.8) for iv in (0, 7, 12))
    return filt(drive(x * dist, 3.0), "low", 3200) * 0.5


def pad(notes, dur, rng, cut=1400.0, attack=0.6):
    n = int(dur * SR)
    x = np.zeros(n)
    for m in notes:
        f = midi(m)
        for det in (-0.004, 0.0, 0.005):
            x += osc(f * (1.0 + det) * (1.0 + 0.002 * osc(0.3 + det * 50, n)), n, shape="saw")
    x = filt(x / (3 * len(notes)), "low", cut) * adsr(n, attack, 0.3, 0.8, min(attack * 1.5, dur * 0.4))
    return x


def lead(note, dur, rng, vib=5.5, shape="square", cut=2600.0):
    n = int(dur * SR)
    f = midi(note) * (1.0 + 0.008 * osc(vib, n) * np.clip(np.arange(n) / SR / 0.25, 0, 1))
    x = osc(f, n, shape=shape) * 0.6 + osc(f * 1.004, n, shape="saw") * 0.4
    return filt(x, "low", cut) * adsr(n, 0.02, 0.1, 0.75, 0.08)


def wind(n, rng, lo=300, hi=1600):
    x = pink(n, rng)
    swell = 0.6 + 0.4 * np.sin(np.linspace(0, 2 * np.pi * 3, n) + rng.uniform(0, 6))
    return filt(x, "band", (lo, hi)) * swell


# ---------------------------------------------------------------- tracks
# D phrygian / harmonic minor colour: D Eb F G A Bb C (C# as the leading tone in places).

def menu(rng):
    """Dune Sea: a slow, lonely desert ballad over wind."""
    t = Track(76, 16, rng)
    prog = [(38, [50, 53, 57]), (39, [51, 55, 58]), (36, [48, 52, 55]), (38, [50, 53, 57]),
            (34, [46, 50, 53]), (36, [48, 52, 55]), (39, [51, 55, 58]), (37, [49, 52, 57])]
    arp = [0, 1, 2, 1, 2, 1, 0, 2]
    for bar in range(t.bars):
        root, ch = prog[bar % len(prog)]
        t.add("pad", pad([n + 12 for n in ch] + [root + 12], 4 * t.beat, rng, 1100, 1.0), t.at(bar), 0.5)
        t.add("bass", bass(root, 3.5 * t.beat, rng, 300, 1.2), t.at(bar), 0.35)
        if bar >= 2:
            for i, k in enumerate(arp):
                note = ch[k] + 12 + (12 if i == 4 and bar % 4 == 3 else 0)
                t.add("gtr", guitar(note, 1.6, rng, bright=0.45), t.at(bar, i * 0.5), 0.3, -0.3 + 0.6 * (i % 2))
    melody = [(4, 0, 69, 1.5), (4, 1.5, 70, 0.5), (4, 2, 69, 2), (5, 0, 67, 1), (5, 1, 65, 1), (5, 2, 67, 2),
              (6, 0, 64, 3), (7, 0, 65, 1), (7, 1, 64, 1), (7, 2, 61, 2),
              (12, 0, 74, 1.5), (12, 1.5, 75, 0.5), (12, 2, 74, 2), (13, 0, 72, 1), (13, 1, 70, 1), (13, 2, 69, 2),
              (14, 0, 67, 2), (14, 2, 69, 2), (15, 0, 62, 4)]
    for bar, beat, note, length in melody:
        t.add("lead", lead(note, length * t.beat, rng, 4.5, "tri", 1800), t.at(bar, beat), 0.28, 0.15)
    t.add("wind", wind(t.length, rng), 0, 0.05)
    return t.mix({"pad": (1.0, 0.35, 1.5), "bass": (1.0, 0.05, 1.0), "gtr": (1.0, 0.35, 1.4),
                  "lead": (1.0, 0.4, 1.5), "wind": (1.0, 0.0, 1.0)})


def workshop(rng):
    """Scrap Yard: a laid-back groove with clanking tools and a twangy guitar."""
    t = Track(96, 16, rng)
    prog = [(38, [62, 65, 69]), (38, [62, 65, 69]), (36, [60, 64, 67]), (39, [63, 67, 70]),
            (38, [62, 65, 69]), (34, [58, 62, 65]), (36, [60, 64, 67]), (37, [61, 64, 69])]
    bass_line = [0, None, 0, 12, None, 7, None, 10]
    for bar in range(t.bars):
        root, ch = prog[bar % len(prog)]
        for s in range(8):
            if s in (0, 5):
                t.add("drums", kick(rng, 0.8), t.at(bar, s * 0.5), 0.55)
            if s in (2, 6):
                t.add("drums", snare(rng, 0.6), t.at(bar, s * 0.5), 0.32)
            t.add("drums", shaker(rng), t.at(bar, s * 0.5 + (0.08 if s % 2 else 0.0)), 0.18 if s % 2 else 0.12, 0.3)
            off = bass_line[s]
            if off is not None:
                t.add("bass", bass(root + off, 0.45 * t.beat, rng, 600, 1.5), t.at(bar, s * 0.5), 0.4)
        if bar % 2 == 1:
            t.add("perc", clank(rng), t.at(bar, 3.5), 0.22, rng.uniform(-0.6, 0.6))
        if bar % 4 == 0:
            t.add("perc", clank(rng, 260), t.at(bar, 1.75), 0.15, 0.5)
        t.add("pad", pad(ch, 4 * t.beat, rng, 900, 0.3), t.at(bar), 0.22)
        # twang: chord stabs on the off-beats, a lick every other bar
        for b in (1.5, 3.5):
            for k, m in enumerate(ch):
                t.add("gtr", guitar(m, 0.35, rng, bright=0.7), t.at(bar, b) + k * 180, 0.16, -0.4)
        if bar % 2 == 1:
            lick = [ch[2] + 12, ch[1] + 12, ch[0] + 12, ch[1] + 12 - 2] if bar % 4 == 1 else [ch[0] + 12, ch[0] + 15, ch[0] + 17, ch[0] + 19]
            for i, m in enumerate(lick):
                t.add("lead", guitar(m, 0.6, rng, 1.5, 0.8), t.at(bar, 2 + i * 0.5), 0.22, 0.35)
    return t.mix({"drums": (1.0, 0.08, 0.8), "bass": (1.0, 0.03, 1.0), "perc": (1.0, 0.3, 1.2),
                  "pad": (1.0, 0.3, 1.2), "gtr": (1.0, 0.25, 1.0), "lead": (1.0, 0.3, 1.2)})


def combat(rng):
    """Convoy: driving war-rig rock with a distorted bass ostinato and alien glass on top."""
    t = Track(138, 32, rng)
    prog = [38, 38, 39, 36, 38, 38, 34, 37]  # roots per bar (D D Eb C D D Bb C#)
    ost = [0, 0, 12, 0, 1, 0, 10, 0, 0, 0, 12, 0, 7, 0, 3, 1]
    for bar in range(t.bars):
        root = prog[bar % len(prog)]
        section = bar // 8  # 0 intro-ish, 1 full, 2 breakdown, 3 full with lead
        for s in range(16):
            beat = s * 0.25
            if s % 4 == 0 and not (section == 2 and s in (4, 12)):
                t.add("drums", kick(rng, 1.1), t.at(bar, beat), 0.6)
            if s == 10 and section != 2:
                t.add("drums", kick(rng, 0.9), t.at(bar, beat), 0.45)
            if s in (4, 12):
                t.add("drums", snare(rng, 1.0), t.at(bar, beat), 0.42)
            if section != 0 or bar % 8 >= 4:
                t.add("drums", hat(rng, s == 14), t.at(bar, beat), 0.13 if s % 2 else 0.2, 0.25)
            t.add("bass", bass(root + ost[s], 0.24 * t.beat, rng, 700, 2.4), t.at(bar, beat), 0.32)
        if bar % 8 == 7:
            for k in range(4):
                t.add("drums", snare(rng, 1.2), t.at(bar, 3 + k * 0.25), 0.25 + 0.06 * k)
        if section in (1, 3):
            t.add("gtr", power_chord(root + 12, 1.4 * t.beat, rng), t.at(bar), 0.32, -0.45)
            t.add("gtr", power_chord(root + 12, 0.45 * t.beat, rng), t.at(bar, 1.5), 0.26, 0.45)
            t.add("gtr", power_chord(root + 12 + (1 if bar % 2 else 0), 0.9 * t.beat, rng), t.at(bar, 2.5), 0.28, -0.45)
        if section == 2:
            t.add("pad", pad([root + 24, root + 27, root + 31], 4 * t.beat, rng, 1600, 0.8), t.at(bar), 0.25)
            t.add("perc", clank(rng), t.at(bar, 2.75), 0.2, rng.uniform(-0.7, 0.7))
        # alien glass: bell blips in phrygian, sparse, panned wide
        if bar % 2 == 0:
            for k in range(3):
                m = 74 + [0, 1, 5, 7, 8, 12][int(rng.integers(0, 6))]
                n = int(0.6 * SR)
                bell = (osc(midi(m), n) + 0.3 * osc(midi(m) * 2.76, n)) * env(n, 0.002, 0.4)
                t.add("glass", bell, t.at(bar, 0.75 + k * 1.25), 0.07, rng.uniform(-0.8, 0.8))
    riff = [(0, 0, 74, 0.75), (0, 0.75, 75, 0.75), (0, 1.5, 74, 0.5), (0, 2, 72, 1), (0, 3, 69, 1),
            (1, 0, 70, 1.5), (1, 1.5, 69, 0.5), (1, 2, 67, 2),
            (2, 0, 74, 0.75), (2, 0.75, 75, 0.75), (2, 1.5, 77, 0.5), (2, 2, 79, 1), (2, 3, 77, 1),
            (3, 0, 75, 1), (3, 1, 74, 1), (3, 2, 73, 2)]
    for rep in (24, 28):
        for b, beat, note, length in riff:
            t.add("lead", guitar(note, length * t.beat, rng, 2.5, 0.8), t.at(rep + b, beat), 0.24, 0.2)
            t.add("lead", lead(note - 12, length * t.beat, rng, 6.0, "saw", 1800), t.at(rep + b, beat), 0.08, -0.2)
    return t.mix({"drums": (1.0, 0.07, 0.8), "bass": (1.0, 0.0, 1.0), "gtr": (1.0, 0.12, 1.0),
                  "pad": (1.0, 0.4, 1.5), "perc": (1.0, 0.35, 1.3), "glass": (1.0, 0.5, 1.6), "lead": (1.0, 0.22, 1.2)})


def boss(rng):
    """Hive Queen: half-time, crushing, dissonant; a choir of glass over the drums."""
    t = Track(150, 16, rng)
    prog = [26, 26, 27, 27, 26, 26, 32, 31]  # D D Eb Eb D D Ab G (tritone colour)
    for bar in range(t.bars):
        root = prog[bar % len(prog)]
        for s in range(16):
            beat = s * 0.25
            if s in (0, 3, 6, 10) or (bar % 2 and s == 14):
                t.add("drums", kick(rng, 1.3), t.at(bar, beat), 0.65)
            if s == 8:
                t.add("drums", snare(rng, 1.4), t.at(bar, beat), 0.5)
            if s % 2 == 0:
                t.add("drums", hat(rng, s == 6), t.at(bar, beat), 0.12, -0.3)
            if s in (0, 3, 6, 10, 12):
                t.add("bass", bass(root + (12 if s == 12 else 0), 0.5 * t.beat, rng, 450, 4.0), t.at(bar, beat), 0.38)
        t.add("gtr", power_chord(root + 24, 1.8 * t.beat, rng, 6.0), t.at(bar), 0.3, -0.5)
        t.add("gtr", power_chord(root + 24 + 1, 1.0 * t.beat, rng, 6.0), t.at(bar, 2.5), 0.26, 0.5)
        t.add("pad", pad([root + 36, root + 37, root + 43], 4 * t.beat, rng, 2400, 0.5), t.at(bar), 0.2)
        if bar % 4 == 3:
            t.add("perc", clank(rng, 200), t.at(bar, 3), 0.3, 0.0)
            t.add("perc", clank(rng, 280), t.at(bar, 3.5), 0.3, 0.3)
    return t.mix({"drums": (1.0, 0.12, 1.0), "bass": (1.0, 0.0, 1.0), "gtr": (1.0, 0.15, 1.2),
                  "pad": (1.0, 0.5, 1.7), "perc": (1.0, 0.4, 1.4)})


TRACKS = {"menu": menu, "workshop": workshop, "combat": combat, "boss": boss}
