"""
The farmhouse's bigger floor plan - the Python twin of
src/shared/HouseLayout.luau (keep the two in step).

The house code places everything with the original plan's house-local
numbers; the rooms are built SCALE times as wide and deep. Per axis the
plan's wall lines move out by SCALE, anything within NEAR studs of a wall
line keeps its distance to it, and the middle of each room stretches. Doors
and windows keep their width: map their centre, not their edges.
"""

SCALE = 1.5
NEAR = 3.0
LINES_X = (-68.0, -32.0, -5.0, 5.0, 32.0, 68.0)
LINES_Z = (-24.0, 0.0, 24.0)


def _map(v, lines):
    k = SCALE
    if v <= lines[0]:
        return lines[0] * k + (v - lines[0])
    if v >= lines[-1]:
        return lines[-1] * k + (v - lines[-1])
    for a, b in zip(lines, lines[1:]):
        if v <= b:
            d = min(NEAR, (b - a) / 2)
            if v <= a + d:
                return a * k + (v - a)
            if v >= b - d:
                return b * k + (v - b)
            t = (v - (a + d)) / ((b - d) - (a + d))
            return (a * k + d) + t * ((b * k - d) - (a * k + d))
    return v


def fx(v):
    return _map(v, LINES_X)


def fz(v):
    return _map(v, LINES_Z)


def at(x, y, z):
    return (fx(x), y, fz(z))


def offset_for(lo, hi):
    """How far a piece of furniture spanning lo..hi (x, z) moves, as
    HouseLayout.offsetFor: by its edge against a wall, else by its centre."""
    def along(a, b, lines):
        for line in lines:
            if abs(a - line) < NEAR:
                return _map(a, lines) - a
        for line in lines:
            if abs(b - line) < NEAR:
                return _map(b, lines) - b
        c = (a + b) / 2
        return _map(c, lines) - c
    return along(lo[0], hi[0], LINES_X), along(lo[1], hi[1], LINES_Z)


# the main stairs (House.luau), already in the bigger house: free-standing in
# the middle of the hall, rising toward the back to a landing
STAIR_X0, STAIR_X1 = -3.0, 3.0
STAIR_BACK = fz(24) - 8
STAIR_FRONT = STAIR_BACK - 13 * 1.7
