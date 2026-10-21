"""Sound effects. Every function takes a seeded numpy Generator and returns a mono float array at
dsp.SR. Style: dry, gritty, scrap-metal desert; aliens are wet and chitinous with a glassy shimmer."""

import numpy as np

from dsp import (SR, adsr, crush, drive, env, filt, glide, midi, noise, osc, pink, pluck, reverb, secs,
                 sweep_filt)


def _thump(dur, f0, f1, rng, decay=None):
    n = int(dur * SR)
    return osc(glide(f0, f1, n, 0.5), n) * env(n, 0.001, decay or dur * 0.6)


def _crackle(dur, rng, density=0.004, lo=1500.0):
    n = int(dur * SR)
    x = np.where(rng.random(n) < density, rng.uniform(-1, 1, n), 0.0)
    return filt(x, "high", lo) * 3.0


# ---------------------------------------------------------------- weapons (warm, mechanical)

def mg(rng):
    n = int(0.11 * SR)
    crack = filt(noise(n, rng), "band", (900, 5000)) * env(n, 0.0005, 0.03)
    body = _thump(0.11, 190, 70, rng, 0.05) * 0.8
    click = filt(noise(n, rng), "high", 5000) * env(n, 0.0, 0.006) * 0.5
    return drive(crack + body + click, 2.2)


def shotgun(rng):
    n = int(0.32 * SR)
    blast = filt(noise(n, rng), "low", 2600) * env(n, 0.001, 0.12)
    boom = _thump(0.32, 140, 45, rng, 0.14)
    tail = sweep_filt(noise(n, rng), "low", 3000, 300) * env(n, 0.01, 0.3) * 0.35
    return drive(blast * 1.1 + boom + tail, 2.5)


def cannon(rng):
    n = int(0.75 * SR)
    boom = _thump(0.75, 110, 32, rng, 0.45) * 1.2
    blast = sweep_filt(noise(n, rng), "low", 5000, 180, shape=0.5) * env(n, 0.001, 0.4)
    clank = osc(midi(81), n, shape="tri") * env(n, 0.0, 0.04) * 0.15
    return drive(boom + blast + clank, 2.0)


def flamer(rng):
    n = int(0.34 * SR)
    whoosh = sweep_filt(pink(n, rng), "low", 700, 2600) * adsr(n, 0.03, 0.1, 0.6, 0.15)
    roar = filt(noise(n, rng), "band", (180, 700)) * adsr(n, 0.02, 0.1, 0.7, 0.15) * 0.8
    return drive(whoosh + roar + _crackle(0.34, rng, 0.006) * 0.4, 1.6)


def ram(rng):
    n = int(0.4 * SR)
    hit = _thump(0.4, 90, 40, rng, 0.25) * 1.2
    crunch = filt(noise(n, rng), "band", (300, 3000)) * env(n, 0.0, 0.12)
    ring = sum(osc(f, n) * env(n, 0.0, 0.25) for f in (412, 655, 1033)) * 0.12
    return drive(hit + crunch + ring, 2.5)


# ---------------------------------------------------------------- impacts and alien deaths

def hit(rng):
    n = int(0.06 * SR)
    return filt(noise(n, rng), "band", (1500, 6000)) * env(n, 0.0, 0.02) + osc(2400 + rng.uniform(-300, 300), n) * env(n, 0.0, 0.01) * 0.3


def hit_heavy(rng):
    n = int(0.18 * SR)
    return drive(_thump(0.18, 160, 55, rng, 0.08) + filt(noise(n, rng), "band", (600, 3500)) * env(n, 0.0, 0.05), 2.0)


def acid_hit(rng):
    n = int(0.32 * SR)
    sizzle = filt(noise(n, rng), "high", 3500) * adsr(n, 0.005, 0.05, 0.5, 0.2) * 0.7
    splat = sweep_filt(noise(n, rng), "low", 2500, 300) * env(n, 0.0, 0.08)
    return sizzle + splat + _crackle(0.32, rng, 0.01, 3000) * 0.3


def _squelch(dur, f_hi, f_lo, rng, wet=1.0):
    n = int(dur * SR)
    body = sweep_filt(noise(n, rng), "low", f_hi, f_lo, shape=0.6) * env(n, 0.002, dur * 0.5) * 1.4
    blip = osc(glide(f_lo * 0.5 + 120, 60, n), n) * env(n, 0.0, dur * 0.3) * 0.6 * wet
    gurgle = osc(glide(300, 90, n), n) * (0.5 + 0.5 * osc(38, n)) * env(n, 0.01, dur * 0.6) * 0.25 * wet
    return drive(body + blip + gurgle, 1.8)


def kill_mite(rng):
    return _squelch(0.2, 3800, 400, rng)


def kill_spitter(rng):
    x = _squelch(0.32, 2600, 250, rng, 1.3)
    n = len(x)
    return x + filt(noise(n, rng), "high", 3000) * env(n, 0.04, 0.15) * 0.25


def kill_boulder(rng):
    n = int(0.55 * SR)
    crack = filt(noise(n, rng), "band", (700, 4000)) * env(n, 0.0, 0.05) * 1.2
    rubble = filt(_crackle(0.55, rng, 0.02, 200), "low", 1500) * env(n, 0.02, 0.4) * 1.3
    thud = _thump(0.55, 85, 38, rng, 0.25)
    return drive(crack + rubble + thud, 2.0)


def kill_glass(rng):
    n = int(0.55 * SR)
    shards = np.zeros(n)
    for _ in range(9):
        f = rng.uniform(2200, 7500)
        at = int(rng.uniform(0, 0.08) * SR)
        m = n - at
        shards[at:] += osc(f, m) * env(m, 0.0, rng.uniform(0.08, 0.3)) * rng.uniform(0.15, 0.35)
    tink = filt(noise(n, rng), "high", 4000) * env(n, 0.0, 0.04)
    return shards + tink + _squelch(0.55, 1800, 300, rng, 0.6) * 0.5


def kill_big(rng):
    """Brood carrier / shrieker: a fat wet burst."""
    x = _squelch(0.6, 2000, 120, rng, 1.6)
    n = len(x)
    return drive(x + _thump(0.6, 70, 30, rng, 0.3) * 0.8, 1.5)


def spit(rng):
    n = int(0.22 * SR)
    p = sweep_filt(noise(n, rng), "low", 600, 3500, shape=0.4) * env(n, 0.01, 0.08)
    pop = osc(glide(180, 520, n), n) * env(n, 0.005, 0.05) * 0.6
    return p + pop


def brood(rng):
    x = _squelch(0.5, 1500, 200, rng, 1.0)
    n = len(x)
    skitter = _crackle(0.5, rng, 0.02, 2500) * env(n, 0.1, 0.3)
    return x * 0.8 + skitter * 0.6


def shriek(rng):
    n = int(0.9 * SR)
    f = glide(1100, 2600, n, 0.5) * (1.0 + 0.04 * osc(28, n))
    v = osc(f, n, shape="saw") + 0.6 * osc(f * 1.5, n, shape="saw")
    v = filt(v, "band", (900, 4500)) * adsr(n, 0.05, 0.2, 0.7, 0.3)
    glass = osc(f * 2.01, n) * 0.15 * adsr(n, 0.1, 0.2, 0.5, 0.3)
    return reverb(drive(v + glass, 1.5), size=0.8, mix=0.3)


# ---------------------------------------------------------------- explosions and abilities

def explosion(rng, dur=1.5, low=26):
    n = int(dur * SR)
    boom = _thump(dur, 95, low, rng, dur * 0.55) * 1.3
    blast = sweep_filt(noise(n, rng), "low", 7000, 120, shape=0.4) * env(n, 0.002, dur * 0.7)
    debris = _crackle(dur, rng, 0.01, 1200) * env(n, 0.08, dur * 0.8) * 0.5
    return reverb(drive(boom + blast + debris, 2.4), size=1.3, mix=0.25)


def explosion_small(rng):
    return explosion(rng, 0.8, 40)


def shock(rng):
    n = int(0.9 * SR)
    whomp = _thump(0.9, 70, 28, rng, 0.5) * 1.3
    air = sweep_filt(pink(n, rng), "low", 1500, 100) * env(n, 0.01, 0.5) * 0.8
    return drive(whomp + air, 2.0)


def emp(rng):
    n = int(0.8 * SR)
    zap = osc(glide(2400, 90, n, 0.4), n, shape="square") * env(n, 0.0, 0.5) * 0.5
    buzz = osc(60, n, shape="saw") * (0.5 + 0.5 * osc(17, n, shape="square")) * env(n, 0.05, 0.6) * 0.4
    return crush(filt(zap + buzz, "low", 6000), 6)


def zap(rng):
    n = int(0.25 * SR)
    arc = noise(n, rng) * (rng.random(n) < 0.3) * env(n, 0.0, 0.15)
    tone = osc(glide(1800, 600, n), n, shape="square") * env(n, 0.0, 0.08) * 0.35
    return filt(arc, "high", 1500) * 1.5 + tone


def nitro(rng):
    n = int(0.9 * SR)
    roar = sweep_filt(noise(n, rng), "low", 400, 4000, shape=0.7) * adsr(n, 0.05, 0.2, 0.7, 0.4)
    rev = osc(glide(55, 140, n, 0.6), n, shape="saw") * adsr(n, 0.05, 0.2, 0.8, 0.4) * 0.5
    return drive(roar + filt(rev, "low", 900), 2.0)


def boom_turbine(rng):
    return drive(shock(rng) * 0.7 + nitro(rng)[: int(0.9 * SR)] * 0.6, 1.5)


def jam(rng):
    n = int(0.3 * SR)
    clunk = _thump(0.3, 220, 90, rng, 0.06) + filt(noise(n, rng), "band", (400, 2000)) * env(n, 0.0, 0.03)
    click = np.zeros(n)
    click[int(0.12 * SR):] = filt(noise(n - int(0.12 * SR), rng), "high", 3000) * env(n - int(0.12 * SR), 0.0, 0.01)
    return clunk + click


def steam(rng):
    n = int(0.7 * SR)
    return filt(noise(n, rng), "high", 2500) * adsr(n, 0.02, 0.2, 0.6, 0.4) * 0.8


def saw_blade(rng):
    n = int(0.35 * SR)
    whine = osc(glide(900, 1400, n), n, shape="saw") * (0.6 + 0.4 * osc(70, n))
    return filt(whine, "band", (600, 5000)) * adsr(n, 0.01, 0.1, 0.6, 0.15) * 0.6 + _crackle(0.35, rng, 0.01) * 0.4


def sparks(rng):
    n = int(0.35 * SR)
    return _crackle(0.35, rng, 0.03, 3500) * env(n, 0.0, 0.2) + \
        sum(osc(f, n) * env(n, 0.0, 0.12) for f in (1650, 2470)) * 0.1


def shrapnel(rng):
    n = int(0.4 * SR)
    out = np.zeros(n)
    for _ in range(6):
        at = int(rng.uniform(0, 0.15) * SR)
        m = n - at
        out[at:] += osc(rng.uniform(1500, 4200), m) * env(m, 0.0, 0.05) * 0.3
    return out + filt(noise(n, rng), "high", 2000) * env(n, 0.0, 0.03)


def execute(rng):
    n = int(0.45 * SR)
    crack = drive(filt(noise(n, rng), "band", (1500, 7000)) * env(n, 0.0, 0.02) * 2.0, 2.0)
    ding = (osc(midi(88), n) + 0.5 * osc(midi(95), n)) * env(n, 0.002, 0.35) * 0.3
    return crack + ding + _thump(0.45, 150, 50, rng, 0.08) * 0.5


def cash(rng):
    """Contract paid: a ratchet and two warm bell tones."""
    n = int(0.6 * SR)
    out = np.zeros(n)
    for i in range(5):
        at = int(i * 0.025 * SR)
        m = n - at
        out[at:] += filt(noise(m, rng), "band", (2000, 6000)) * env(m, 0.0, 0.008) * 0.5
    for k, note in enumerate((79, 86)):
        at = int((0.12 + k * 0.09) * SR)
        m = n - at
        out[at:] += (osc(midi(note), m) + 0.3 * osc(midi(note) * 2.76, m)) * env(m, 0.002, 0.35) * 0.35
    return out


def dodge(rng):
    n = int(0.25 * SR)
    return sweep_filt(noise(n, rng), "low", 500, 5000, shape=0.5) * np.sin(np.linspace(0, np.pi, n)) * 0.8


def shed(rng):
    n = int(0.5 * SR)
    clank = sum(osc(f, n) * env(n, 0.0, d) for f, d in ((310, 0.25), (523, 0.18), (877, 0.12), (1420, 0.08)))
    return clank * 0.3 + filt(noise(n, rng), "band", (500, 3000)) * env(n, 0.0, 0.03) + _thump(0.5, 120, 60, rng, 0.08) * 0.5


def respawn(rng):
    n = int(0.9 * SR)
    rev = osc(glide(45, 110, n, 0.5), n, shape="saw")
    rev = filt(rev, "low", 1100) * adsr(n, 0.05, 0.2, 0.8, 0.3)
    horn = (osc(midi(62), n, shape="square") + osc(midi(69), n, shape="square")) * adsr(n, 0.4, 0.05, 0.8, 0.3) * 0.08
    return drive(rev + filt(horn, "low", 2500), 1.8)


def drain(rng):
    """Fuel siphoned: glugs."""
    n = int(0.7 * SR)
    out = np.zeros(n)
    for i in range(4):
        at = int(i * 0.15 * SR)
        m = int(0.12 * SR)
        g = osc(glide(380 - i * 40, 140, m), m) * env(m, 0.005, 0.06)
        out[at:at + m] += g * 0.7
    return out + filt(pink(n, rng), "low", 500) * 0.15 * env(n, 0.05, 0.6)


# ---------------------------------------------------------------- alarms and big moments

def _horn(dur, notes, rng, shape="saw", cut=1800.0, vib=5.0):
    n = int(dur * SR)
    out = np.zeros(n)
    for m in notes:
        f = midi(m) * (1.0 + 0.006 * osc(vib, n))
        out += osc(f, n, shape=shape) + 0.5 * osc(f * 1.003, n, shape=shape)
    return filt(out / len(notes), "low", cut) * adsr(n, 0.08, 0.2, 0.8, 0.35)


def surge(rng):
    """The hive surges: a rising alien siren with a glassy beat."""
    n = int(1.6 * SR)
    f = glide(220, 660, n, 0.7) * (1.0 + 0.03 * osc(9, n))
    v = osc(f, n, shape="saw") + osc(f * 1.5, n, shape="tri") * 0.5
    v = filt(v, "band", (300, 3500)) * adsr(n, 0.1, 0.3, 0.8, 0.4)
    pulse = (0.6 + 0.4 * osc(6, n, shape="square"))
    return reverb(drive(v * pulse, 1.6), size=1.0, mix=0.3)


def klaxon(rng):
    """PvP on: a two-tone scrap-yard klaxon."""
    n = int(1.6 * SR)
    out = np.zeros(n)
    for i in range(4):
        at = int(i * 0.4 * SR)
        m = int(0.36 * SR)
        out[at:at + m] += _horn(0.36, [57 if i % 2 == 0 else 53], rng, "square", 2200)
    return reverb(drive(out, 2.0), size=1.1, mix=0.25)


def bounty(rng):
    n = int(1.4 * SR)
    bell = sum(osc(midi(50) * r, n) * env(n, 0.002, d) * a for r, d, a in ((1, 1.2, 1), (2.76, 0.6, 0.4), (5.4, 0.3, 0.25), (8.9, 0.15, 0.1)))
    return reverb(bell * 0.6, size=1.4, mix=0.35)


def boss_warn(rng):
    """A boss is coming: a deep alien horn swelling under the sand."""
    n = int(3.0 * SR)
    f = midi(31) * (1.0 + 0.01 * osc(0.7, n))
    drone = osc(f, n, shape="saw") + osc(f * 1.01, n, shape="saw") + osc(f * 1.5, n, shape="saw") * 0.6
    drone = sweep_filt(drone, "low", 120, 1400, shape=0.6) * adsr(n, 1.2, 0.5, 0.8, 0.8)
    rumble = filt(pink(n, rng), "low", 120) * adsr(n, 0.5, 0.5, 0.8, 0.8) * 1.2
    shimmer = filt(osc(glide(1500, 3000, n), n, shape="saw"), "band", (1500, 4000)) * adsr(n, 2.0, 0.3, 0.5, 0.5) * 0.08
    return reverb(drive(drone * 0.6 + rumble + shimmer, 1.8), size=1.6, mix=0.3)


def boss_roar(rng):
    n = int(1.6 * SR)
    f = glide(160, 70, n, 0.7) * (1.0 + 0.05 * osc(23, n))
    v = osc(f, n, shape="saw") + osc(f * 1.47, n, shape="saw") * 0.7 + noise(n, rng) * 0.6
    v = filt(v, "band", (90, 2200)) * adsr(n, 0.08, 0.3, 0.8, 0.5)
    return reverb(drive(v, 2.5), size=1.4, mix=0.3)


def boss_kill(rng):
    n = int(2.6 * SR)
    out = np.zeros(n)
    out += np.pad(boss_roar(rng), (0, max(0, n - int(1.6 * SR))))[:n] * 0.6
    ex = explosion(rng, 2.4, 22)
    out[int(0.25 * SR):int(0.25 * SR) + len(ex)] += ex[: n - int(0.25 * SR)]
    return out


def boss_charge(rng):
    n = int(1.0 * SR)
    rumble = filt(noise(n, rng), "low", 250) * adsr(n, 0.2, 0.2, 0.8, 0.3) * 1.5
    stomp = np.zeros(n)
    for i in range(4):
        at = int(i * 0.22 * SR)
        s = _thump(0.2, 80, 35, rng, 0.1)
        stomp[at:at + len(s)] += s[: n - at]
    return drive(rumble + stomp, 2.0)


# ---------------------------------------------------------------- UI and round flow

def ui_click(rng):
    n = int(0.06 * SR)
    return filt(noise(n, rng), "band", (1800, 6000)) * env(n, 0.0, 0.01) + osc(1200, n, shape="tri") * env(n, 0.0, 0.015) * 0.4


def ui_pick(rng):
    """Card taken: a heavy toggle and a short warm two-note."""
    n = int(0.35 * SR)
    out = hit_heavy(rng)
    out = np.pad(out, (0, n - len(out)))
    for k, m in enumerate((67, 74)):
        at = int((0.04 + k * 0.07) * SR)
        l = n - at
        out[at:] += osc(midi(m), l, shape="tri") * env(l, 0.003, 0.2) * 0.35
    return out


def ui_reroll(rng):
    n = int(0.4 * SR)
    out = np.zeros(n)
    for i in range(6):
        at = int(i * 0.045 * SR)
        m = int(0.05 * SR)
        out[at:at + m] += filt(noise(m, rng), "band", (800 + i * 300, 4000)) * env(m, 0.0, 0.012)
    return out


def ui_buy(rng):
    return cash(rng) * 0.8 + np.pad(jam(rng)[: int(0.3 * SR)], (0, int(0.3 * SR)))[: int(0.6 * SR)] * 0.3


def ui_deny(rng):
    n = int(0.25 * SR)
    return filt(osc(midi(40), n, shape="square") + osc(midi(41), n, shape="square"), "low", 1400) * adsr(n, 0.005, 0.05, 0.7, 0.05) * 0.4


def ui_ready(rng):
    """Ready: the engine turns over and catches."""
    n = int(0.8 * SR)
    f = np.concatenate([glide(30, 38, int(0.35 * SR)), glide(38, 70, n - int(0.35 * SR), 0.4)])
    eng = osc(f, n, shape="saw") * (0.6 + 0.4 * osc(f * 0.5, n, shape="square"))
    return drive(filt(eng, "low", 900) * adsr(n, 0.02, 0.1, 0.8, 0.25), 2.2)


def round_start(rng):
    """Roll out: engines rev and a short horn blast."""
    n = int(1.3 * SR)
    out = np.pad(nitro(rng), (0, n))[:n] * 0.6
    h = _horn(0.7, [50, 57, 62], rng, "saw", 2000)
    out[int(0.35 * SR):int(0.35 * SR) + len(h)] += h * 0.8
    return reverb(drive(out, 1.5), size=1.0, mix=0.2)


def round_end(rng):
    """Aliens retreat into the sand: a falling glassy sigh."""
    n = int(1.4 * SR)
    f = glide(880, 330, n, 0.6)
    v = (osc(f, n, shape="tri") + 0.4 * osc(f * 1.5, n)) * adsr(n, 0.05, 0.3, 0.6, 0.6) * 0.4
    sand = filt(pink(n, rng), "band", (800, 4000)) * adsr(n, 0.2, 0.3, 0.5, 0.6) * 0.3
    return reverb(v + sand, size=1.4, mix=0.35)


def win(rng):
    n = int(3.0 * SR)
    out = np.zeros(n)
    for k, ch in enumerate(([50, 57, 62], [53, 60, 65], [55, 62, 67], [57, 64, 69, 74])):
        at = int(k * 0.32 * SR)
        d = 0.3 if k < 3 else 2.0
        h = _horn(d, ch, rng, "saw", 2600, 5.5)
        out[at:at + len(h)] += h
    for k, m in enumerate((62, 65, 69, 74, 81)):
        at = int((0.96 + k * 0.08) * SR)
        p = pluck(midi(m), 1.4, rng)
        out[at:at + len(p)] += p * 0.35
    return reverb(drive(out, 1.4), size=1.3, mix=0.3)


def lose(rng):
    n = int(3.0 * SR)
    out = np.zeros(n)
    for k, ch in enumerate(([50, 53, 57], [49, 52, 56], [46, 50, 53])):
        at = int(k * 0.55 * SR)
        d = 0.5 if k < 2 else 1.6
        h = _horn(d, ch, rng, "saw", 1400, 4.0)
        out[at:at + len(h)] += h
    out += np.pad(filt(pink(int(2.2 * SR), rng), "low", 600) * adsr(int(2.2 * SR), 0.6, 0.4, 0.6, 1.0) * 0.4,
                  (int(0.8 * SR), 0))[:n]
    return reverb(out, size=1.5, mix=0.35)


# name -> (function, peak level). The director picks names; levels balance the set against each other.
SOUNDS = {
    "mg": (mg, 0.55), "shotgun": (shotgun, 0.75), "cannon": (cannon, 0.9), "flamer": (flamer, 0.5),
    "ram": (ram, 0.85),
    "hit": (hit, 0.3), "hit_heavy": (hit_heavy, 0.55), "acid_hit": (acid_hit, 0.5),
    "kill_mite": (kill_mite, 0.5), "kill_spitter": (kill_spitter, 0.6), "kill_boulder": (kill_boulder, 0.75),
    "kill_glass": (kill_glass, 0.55), "kill_big": (kill_big, 0.75),
    "spit": (spit, 0.45), "brood": (brood, 0.6), "shriek": (shriek, 0.6),
    "explosion": (explosion, 0.95), "explosion_small": (explosion_small, 0.8), "shock": (shock, 0.85),
    "emp": (emp, 0.6), "zap": (zap, 0.5), "nitro": (nitro, 0.6), "boom": (boom_turbine, 0.8),
    "jam": (jam, 0.5), "steam": (steam, 0.4), "saw": (saw_blade, 0.45), "sparks": (sparks, 0.45),
    "shrapnel": (shrapnel, 0.45), "execute": (execute, 0.7), "cash": (cash, 0.6), "dodge": (dodge, 0.45),
    "shed": (shed, 0.55), "respawn": (respawn, 0.7), "drain": (drain, 0.55),
    "surge": (surge, 0.7), "klaxon": (klaxon, 0.7), "bounty": (bounty, 0.6),
    "boss_warn": (boss_warn, 0.9), "boss_roar": (boss_roar, 0.85), "boss_kill": (boss_kill, 0.95),
    "boss_charge": (boss_charge, 0.8),
    "ui_click": (ui_click, 0.4), "ui_pick": (ui_pick, 0.6), "ui_reroll": (ui_reroll, 0.5), "ui_buy": (ui_buy, 0.6),
    "ui_deny": (ui_deny, 0.45), "ui_ready": (ui_ready, 0.65), "round_start": (round_start, 0.8),
    "round_end": (round_end, 0.6), "win": (win, 0.85), "lose": (lose, 0.8),
}
