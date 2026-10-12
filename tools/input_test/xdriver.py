"""Minimal real-input driver for an X display: XTEST mouse and keyboard, screen grabs, PNG writer.

Only needs python-xlib (pip install python-xlib / apt install python3-xlib). Everything
else is the standard library, so CI does not need ImageMagick or Pillow.
"""
import struct
import time
import zlib

from Xlib import X, XK, display
from Xlib.ext import xtest


class Screen:
    def __init__(self, display_name: str):
        self.d = display.Display(display_name)
        self.root = self.d.screen().root
        geo = self.root.get_geometry()
        self.width, self.height = geo.width, geo.height

    # ------------------------------------------------------------ input (XTEST = real X11 events)

    def move(self, x: int, y: int) -> None:
        xtest.fake_input(self.d, X.MotionNotify, x=int(x), y=int(y))
        self.d.sync()

    def click(self, x: int, y: int, hold: float = 0.06) -> None:
        self.move(x, y)
        time.sleep(0.08)  # let the game see the hover before the press
        xtest.fake_input(self.d, X.ButtonPress, 1)
        self.d.sync()
        time.sleep(hold)
        xtest.fake_input(self.d, X.ButtonRelease, 1)
        self.d.sync()

    def key(self, name: str, hold: float = 0.06) -> None:
        kc = self.d.keysym_to_keycode(XK.string_to_keysym(name))
        if kc == 0:
            raise RuntimeError("no keycode for key %r" % name)
        xtest.fake_input(self.d, X.KeyPress, kc)
        self.d.sync()
        time.sleep(hold)
        xtest.fake_input(self.d, X.KeyRelease, kc)
        self.d.sync()

    # ------------------------------------------------------------ screen grabs

    def grab(self, x: int = 0, y: int = 0, w: int = 0, h: int = 0) -> "Image":
        w = w or self.width - x
        h = h or self.height - y
        raw = self.root.get_image(x, y, w, h, X.ZPixmap, 0xFFFFFFFF)
        return Image(w, h, bytes(raw.data))


class Image:
    """32bpp BGRX pixels as returned by an Xvfb 24-bit screen."""

    def __init__(self, w: int, h: int, data: bytes):
        self.w, self.h, self.data = w, h, data

    def mean_luma(self) -> float:
        d = self.data
        n = len(d) // 4
        # sample every 7th pixel; plenty for a region average
        step = 7
        total = 0
        cnt = 0
        for i in range(0, n, step):
            o = i * 4
            total += d[o] * 29 + d[o + 1] * 150 + d[o + 2] * 77
            cnt += 1
        return total / (cnt * 256.0) if cnt else 0.0

    def diff(self, other: "Image") -> float:
        """Fraction (0..1) of sampled pixels whose colour differs noticeably."""
        a, b = self.data, other.data
        if len(a) != len(b):
            return 1.0
        n = len(a) // 4
        step = 5
        bad = 0
        cnt = 0
        for i in range(0, n, step):
            o = i * 4
            if abs(a[o] - b[o]) + abs(a[o + 1] - b[o + 1]) + abs(a[o + 2] - b[o + 2]) > 24:
                bad += 1
            cnt += 1
        return bad / cnt if cnt else 0.0

    def save_png(self, path: str) -> None:
        rows = []
        for y in range(self.h):
            seg = self.data[y * self.w * 4:(y + 1) * self.w * 4]
            row = bytearray(1 + self.w * 3)
            row[1::3] = seg[2::4]
            row[2::3] = seg[1::4]
            row[3::3] = seg[0::4]
            rows.append(bytes(row))
        raw = zlib.compress(b"".join(rows), 6)

        def chunk(tag: bytes, body: bytes) -> bytes:
            c = struct.pack(">I", len(body)) + tag + body
            return c + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 2, 0, 0, 0))
        png += chunk(b"IDAT", raw) + chunk(b"IEND", b"")
        with open(path, "wb") as f:
            f.write(png)
