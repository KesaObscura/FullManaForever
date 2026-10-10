# Original "potion ready" sounds for Full Mana Forever (made here, no samples, MIT like the addon).
# Usage: python3 tools/sound.py <out dir>   -> writes a.wav b.wav c.wav (+ .ogg with ffmpeg)
import math, os, struct, subprocess, sys, wave

RATE = 44100

def note(freq):
    return 440.0 * 2 ** ((freq - 69) / 12.0)  # MIDI number -> Hz

def bell(f, t, decay):
    # bell: a few inharmonic partials, each fading at its own speed
    parts = ((1.0, 1.0), (2.76, 0.45), (5.40, 0.22), (8.93, 0.10))
    return sum(a * math.sin(2 * math.pi * f * r * t) * math.exp(-t * decay * (1 + r / 3))
               for r, a in parts)

def render(events, length):
    n = int(RATE * length)
    out = [0.0] * n
    for start, fn in events:
        s0 = int(start * RATE)
        for i in range(s0, n):
            t = (i - s0) / RATE
            v = fn(t)
            if v is None:
                break
            out[i] += v
    peak = max(abs(x) for x in out) or 1
    fade = int(0.03 * RATE)
    for i in range(fade):  # soft end
        out[n - 1 - i] *= i / fade
    return [x / peak * 0.8 for x in out]

def b_tone(f, decay=7.0, dur=0.9):
    return lambda t: bell(f, t, decay) * min(1, t / 0.004) if t < dur else None

def drop(t):
    # a liquid "bloop": a short sine whose pitch rises fast, like a drop into a bottle
    if t > 0.12:
        return None
    f = 500 + 1400 * (t / 0.12) ** 0.6
    return math.sin(2 * math.pi * f * t) * math.exp(-t * 22) * 0.9

def glass(f):
    # glassy FM tone
    def fn(t):
        if t > 0.8:
            return None
        mod = math.sin(2 * math.pi * f * 3.5 * t) * 1.2 * math.exp(-t * 9)
        return math.sin(2 * math.pi * f * t + mod) * math.exp(-t * 6) * min(1, t / 0.003)
    return fn

SOUNDS = {
    # A: three quick rising bells (a major arpeggio up to the octave), "full"
    "a": ([(0.00, b_tone(note(76))), (0.09, b_tone(note(83))), (0.18, b_tone(note(88), 5.0, 1.0))], 1.15),
    # B: a liquid drop, then one clear bell: "potion"
    "b": ([(0.00, drop), (0.11, b_tone(note(86), 5.5, 1.0))], 1.1),
    # C: two glass notes a fourth apart, the second answered softly
    "c": ([(0.00, glass(note(81))), (0.13, glass(note(86))), (0.36, lambda t: (glass(note(86))(t) or 0) * 0.35 if t < 0.8 else None)], 1.15),
}

def write(path, data):
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x)) * 32767)) for x in data))

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    for key, (events, length) in SOUNDS.items():
        wav = os.path.join(out, key + ".wav")
        write(wav, render(events, length))
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5",
                        os.path.join(out, key + ".ogg")], check=False)
