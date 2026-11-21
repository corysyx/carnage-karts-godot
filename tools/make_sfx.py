"""Synthesises the game's sound effects into assets/sfx/*.wav (run: python3 tools/make_sfx.py)."""
import numpy as np, wave, os
SR = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sfx')
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)

def t(d): return np.arange(int(SR * d)) / SR
def env(n, a=0.005, curve=4.0):
    e = np.exp(-curve * np.linspace(0, 1, n)); k = max(1, int(SR * a)); e[:k] *= np.linspace(0, 1, k); return e
def sweep(f0, f1, d, kind='sine'):
    tt = t(d); f = f0 * (f1 / f0) ** (tt / d); ph = 2 * np.pi * np.cumsum(f) / SR
    if kind == 'sine': return np.sin(ph)
    if kind == 'tri': return 2 * np.abs(2 * (ph / (2 * np.pi) % 1) - 1) - 1
    if kind == 'saw': return 2 * (ph / (2 * np.pi) % 1) - 1
    return np.sign(np.sin(ph))
def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR); y = np.zeros_like(x); s = 0.0
    for i, v in enumerate(x): s = (1 - a) * v + a * s; y[i] = s
    return y
def noise(d): return rng.uniform(-1, 1, int(SR * d))
def save(name, x, vol=0.8):
    x = x / (np.max(np.abs(x)) + 1e-9) * vol
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype(np.int16).tobytes())

def cat(*xs): return np.concatenate(xs)
save('pick', cat(sweep(880, 880, .08, 'tri') * env(int(SR*.08)), sweep(1320, 1320, .12, 'tri') * env(int(SR*.12))), .5)
save('get', cat(sweep(660, 660, .1, 'sq') * env(int(SR*.1)), sweep(990, 990, .15, 'sq') * env(int(SR*.15))), .35)
n = int(SR*.3); save('fire', lowpass(noise(.3), 2500) * env(n, curve=5) + .5 * sweep(320, 100, .3, 'saw') * env(n), .6)
n = int(SR*.5); save('splat', lowpass(noise(.5), 650) * env(n, curve=6) + sweep(190, 50, .5) * env(n, curve=5), .9)
n = int(SR*.7); save('boom', lowpass(noise(.7), 900) * env(n, curve=4), .9)
n = int(SR*.3); save('boing', sweep(220, 740, .3) * env(n, curve=3), .6)
n = int(SR*.18); save('beep', sweep(440, 440, .18, 'sq') * env(n, curve=2), .35)
n = int(SR*.45); save('beep_hi', sweep(880, 880, .45, 'sq') * env(n, curve=2), .35)
n = int(SR*.3); save('shield', sweep(600, 1000, .3) * env(n, curve=3), .45)
n = int(SR*.45); save('boost', sweep(300, 1000, .45, 'saw') * env(n, curve=2.5), .35)
n = int(SR*.12); save('bump', lowpass(noise(.12), 400) * env(n, curve=6), .6)
n = int(SR*.55); save('splash', lowpass(noise(.55), 1200) * env(n, curve=4), .7)
# engine loop: whole number of cycles so it loops cleanly
f = 55.0; d = 1.0; x = sweep(f, f, d, 'saw') + .5 * sweep(f * 2, f * 2, d, 'saw'); save('engine', lowpass(x, 520), .5)
print('ok')
