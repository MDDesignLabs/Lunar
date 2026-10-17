"""RESEARCH_10: where can a side room lamp stand without reflecting in the CU34G4Z?

Model (all cm, origin at the eye; x = right, y = up, z = towards the screen):
- Screen: AOC CU34G4Z, 34" 21:9, active area ~79.7 x 33.4 cm, 1500R (cylinder, vertical axis).
- Eye-to-screen-centre distance D, screen centre DY below the eye, screen tilted back TILT deg
  (top further away).
- For a lamp part at point P we search the screen surface for the point S where the mirror
  reflection of the eye ray lands closest to P, and report the smallest angle between the
  reflected ray and the direction S->P. ~0 deg = a mirror image on the glass. The panel has an
  anti-glare (matte) surface, which spreads a reflection over a lobe; treating anything within
  ~10 deg as "a visible glow on the screen" is a judgement, not a measured value.
Run: python3 lamp_geom.py
"""
import math

W, H, R = 79.7, 33.4, 150.0


def norm(v):
    l = math.sqrt(sum(c * c for c in v))
    return tuple(c / l for c in v)


def sub(a, b): return tuple(x - y for x, y in zip(a, b))
def dot(a, b): return sum(x * y for x, y in zip(a, b))


def screen_points(D=65.0, DY=12.0, TILT=5.0, nu=61, nv=21):
    phimax = (W / 2) / R
    t = math.radians(TILT)
    pts = []
    for i in range(nu):
        phi = -phimax + 2 * phimax * i / (nu - 1)
        for j in range(nv):
            v = -H / 2 + H * j / (nv - 1)
            # untilted, relative to screen centre: curve bows towards the viewer at the edges
            x = R * math.sin(phi)
            z = R * math.cos(phi) - R          # 0 at centre, negative (closer) at edges
            y = v
            n = (-math.sin(phi), 0.0, -math.cos(phi))   # towards the centre of curvature
            # tilt back about the horizontal axis through the screen centre
            # same rotation for points and normals: (y, z) -> (y cos t - z sin t, y sin t + z cos t)
            y2 = y * math.cos(t) - z * math.sin(t)
            z2 = y * math.sin(t) + z * math.cos(t)
            ny = n[1] * math.cos(t) - n[2] * math.sin(t)
            nz = n[1] * math.sin(t) + n[2] * math.cos(t)
            n2 = norm((n[0], ny, nz))
            pts.append(((x, y2 - DY, z2 + D), n2))
    return pts


def reflect(d, n):
    k = 2 * dot(d, n)
    return tuple(di - k * ni for di, ni in zip(d, n))


def margin(P, **kw):
    best = (180.0, None)
    for S, n in screen_points(**kw):
        d = norm(S)                      # eye at origin
        r = norm(reflect(d, n))
        a = math.degrees(math.acos(max(-1, min(1, dot(r, norm(sub(P, S)))))))
        if a < best[0]:
            best = (a, S)
    return best


def field(**kw):
    """Azimuth/elevation range of the reflected rays (what the screen 'looks at')."""
    az, el = [], []
    for S, n in screen_points(**kw):
        r = norm(reflect(norm(S), n))
        az.append(math.degrees(math.atan2(r[0], -r[2])))   # 0 = straight back past the head
        el.append(math.degrees(math.asin(r[1])))
    return min(az), max(az), min(el), max(el)


if __name__ == "__main__":
    for tilt in (0.0, 5.0, 10.0):
        a0, a1, e0, e1 = field(TILT=tilt)
        print(f"tilt {tilt:>4.1f} deg: reflected field azimuth {a0:+.0f}..{a1:+.0f} deg, "
              f"elevation {e0:+.0f}..{e1:+.0f} deg (0/0 = straight back at your face)")
    print()
    print("Lamp part position (x right, y above eye, z towards screen; cm) -> min angle, deg")
    cases = [
        ("uplighter head 180 cm tall, 80 cm to the side, level with you", (80, 60, 0)),
        ("uplighter head, 80 cm to the side, 40 cm behind you", (80, 60, -40)),
        ("uplighter head, 120 cm to the side, 40 cm behind you", (120, 60, -40)),
        ("lit ceiling patch above that lamp (ceiling 260 cm)", (120, 140, -40)),
        ("shaded floor lamp, shade at 150 cm, 70 cm side, level", (70, 30, 0)),
        ("shaded floor lamp, shade at 150 cm, 70 cm side, 50 cm behind", (70, 30, -50)),
        ("table lamp shade on the desk, 60 cm side, 20 cm in front", (60, -15, 20)),
        ("lamp straight behind you at 150 cm (for contrast)", (0, 30, -100)),
        ("shade at 150 cm, 45 cm side, 100 cm behind", (45, 30, -100)),
        ("shade at 150 cm, 60 cm side, 100 cm behind", (60, 30, -100)),
        ("shade at 150 cm, 60 cm side, 200 cm behind", (60, 30, -200)),
        ("shade at 150 cm, 90 cm side, 200 cm behind", (90, 30, -200)),
        ("lamp aimed at side wall: wall patch 150 cm side, level", (150, 30, 0)),
    ]
    for tilt in (5.0, 10.0):
        print(f"-- screen tilt {tilt} deg")
        for name, P in cases:
            a, S = margin(P, TILT=tilt)
            where = "" if S is None else f" (nearest at screen x={S[0]:+.0f}, y={S[1]:+.0f})"
            print(f"  {a:5.1f}  {name}{where}")
    print()
    # Rough desk illuminance from an uplighter (derived; ceiling patch as a Lambertian disc).
    # Phi = lamp lumens, eta = share leaving the bowl upwards, rho_c = ceiling reflectance,
    # A = lit ceiling area, h = ceiling height above the desk, plus one room inter-reflection
    # term with average reflectance rho_r over the room surface area S_room.
    def desk_lux(Phi, eta=0.8, rho_c=0.8, A=3.0, h=1.85, off=1.0, rho_r=0.45, S_room=75.0):
        M = Phi * eta * rho_c / A                 # exitance of the patch, lm/m2
        L = M / math.pi                           # cd/m2
        d2 = h * h + off * off
        cos = h / math.sqrt(d2)
        direct = L * A * cos * cos / d2           # small-source approximation
        inter = Phi * eta * rho_c * rho_r / (S_room * (1 - rho_r))
        return direct, inter
    for Phi in (806, 1055, 1100, 1521):
        d, i = desk_lux(Phi)
        print(f"uplighter {Phi:>4} lm at 100 %: desk ~{d + i:4.0f} lx "
              f"(ceiling patch {d:.0f} + room bounce {i:.0f}); "
              f"at 10 % ~{0.1 * (d + i):.1f} lx; at 1 % ~{0.01 * (d + i):.2f} lx")
