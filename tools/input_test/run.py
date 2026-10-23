#!/usr/bin/env python3
"""Real-input end-to-end test driver. Started by scripts/input-test.sh against a running game.

Every input is a real X11 event (XTEST), so a click only works if a UI Control is really under the
pointer with a non-zero size (the bug this test exists for). Screen layout: the game window is
1920x1080 and the viewport is 640x360 scaled x3 (project.godot, integer stretch), so a viewport
point (vx, vy) is at screen (3*vx, 3*vy). Viewport coordinates below come from render/menu_ui.gd
and render/workshop_ui.gd.

Checks are either stdout based (lines printed by main.gd) or pixel based (brightness and diff of
screen regions); each step says which. Exit code 0 only if every step passed.
"""
import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from xdriver import Screen  # noqa: E402

SCALE = 3


def vp(x: float, y: float):
    """Viewport (640x360) point to screen pixels."""
    return int(x * SCALE), int(y * SCALE)


# Viewport positions (design: render/menu_ui.gd `_draw_main` / `_draw_pause`, render/workshop_ui.gd)
SOLO_BUTTON = vp(40 + 176 / 2, 110 + 24 / 2)  # first main menu button
RESUME_BUTTON = vp(320, 62 + 52 + 24 / 2)  # pause overlay, RESUME (plate y 62, button at +52)
CARD0 = vp(320 - 156 + 50, 160 + 61)  # workshop PARTS view: first of three 100x122 cards (x0 = 320 - 312 / 2)
# Screen regions (x, y, w, h)
DARK_PROBE = (0, 180 * SCALE, 100 * SCALE, 100 * SCALE)  # left plates: dark in workshop, sand in combat
CARDS_REGION = (162 * SCALE, 150 * SCALE, 316 * SCALE, 140 * SCALE)
FROZEN_PROBE = (0, 200 * SCALE, 100 * SCALE, 100 * SCALE)
PRESET_1 = vp(6 + 126 / 2, 48 + 26)  # deploy screen: first starting doctrine card (WorkshopUi.DEPLOY_COL)
PRESET_REGION = (6 * SCALE, 48 * SCALE, 126 * SCALE, 52 * SCALE)


class Runner:
    def __init__(self, a):
        self.s = Screen(a.display)
        self.log_path = a.log
        self.out = a.out
        self.godot_pid = a.godot_pid
        self.failed = 0
        self.n = 0

    # ------------------------------------------------------------ helpers
    def log_text(self) -> str:
        try:
            with open(self.log_path, errors="replace") as f:
                return f.read()
        except OSError:
            return ""

    def shot(self, name: str) -> str:
        path = os.path.join(self.out, "%02d_%s.png" % (self.n, name))
        self.s.grab().save_png(path)
        print("   screenshot: " + path, flush=True)
        return path

    def result(self, name: str, ok: bool, detail: str) -> bool:
        self.n += 1
        print("%s  step %d: %s (%s)" % ("PASS" if ok else "FAIL", self.n, name, detail), flush=True)
        if not ok:
            self.failed += 1
        return ok

    def wait_until(self, fn, timeout: float, interval: float = 0.05):
        t0 = time.time()
        while time.time() - t0 < timeout:
            v = fn()
            if v:
                return v
            time.sleep(interval)
        return None

    def luma(self, region) -> float:
        return self.s.grab(*region).mean_luma()

    def in_workshop(self) -> bool:
        return self.luma(DARK_PROBE) < 90.0

    def game_alive(self) -> bool:
        try:
            os.kill(self.godot_pid, 0)
            return True
        except OSError:
            return False

    # ------------------------------------------------------------ steps
    def run(self) -> int:
        s = self.s
        # 0. the window is up and the main menu is drawn
        up = self.wait_until(lambda: self.luma((0, 0, 1920, 1080)) > 40.0, 60.0, 0.25)
        time.sleep(1.0)  # let the menu settle
        self.result("main menu is drawn [pixel]", bool(up), "mean luma %.0f" % self.luma((0, 0, 1920, 1080)))
        self.shot("menu")
        if not up:
            return 1

        # 1. real mouse click on SOLO RUN starts the match
        print("   clicking SOLO RUN at %s" % (SOLO_BUTTON,), flush=True)
        s.click(*SOLO_BUTTON)
        started = self.wait_until(lambda: "net: match started" in self.log_text(), 10.0)
        txt = self.log_text()
        self.result("mouse click on SOLO RUN starts the match [stdout]", bool(started) and "net: session started (peer 1)" in txt,
                    "'net: session started (peer 1)' and 'net: match started' in game stdout")
        if not started:
            self.shot("after_solo_click")
            return 1
        # 1b. the deploy screen comes first: a mouse click loads a starting doctrine, Space rolls out
        time.sleep(0.4)
        deploy_luma = self.luma(DARK_PROBE)
        self.result("deploy screen is showing [pixel]", deploy_luma < 90.0, "left probe luma %.0f (combat would be > 90)" % deploy_luma)
        self.shot("deploy")
        before = s.grab(*PRESET_REGION)
        s.click(*PRESET_1)
        time.sleep(0.4)
        changed = before.diff(s.grab(*PRESET_REGION))
        self.result("mouse click on a starting doctrine selects it [pixel]", changed > 0.05, "card area changed %.0f%%" % (changed * 100.0))
        s.key("space")
        rolled = self.wait_until(lambda: self.luma(DARK_PROBE) > 90.0, 3.0, 0.1)
        self.result("Space rolls out into round 1 [pixel]", bool(rolled), "left probe luma %.0f" % self.luma(DARK_PROBE))
        time.sleep(0.3)
        combat_luma = self.luma(DARK_PROBE)
        self.result("combat screen is showing [pixel]", combat_luma > 90.0, "left probe luma %.0f (workshop would be < 90)" % combat_luma)
        self.shot("combat")

        # 2. keyboard: Escape pauses (solo freezes the sim), Escape resumes
        s.key("Escape")
        time.sleep(0.5)
        paused_luma = self.luma(DARK_PROBE)
        self.result("Escape opens the pause overlay [pixel]", paused_luma < combat_luma * 0.7,
                    "probe luma %.0f -> %.0f (overlay dims the screen)" % (combat_luma, paused_luma))
        self.shot("paused")
        a = s.grab(*FROZEN_PROBE)
        time.sleep(0.7)
        d = a.diff(s.grab(*FROZEN_PROBE))
        self.result("solo pause freezes the world [pixel]", d < 0.03, "region changed %.1f%% in 0.7 s" % (d * 100))
        s.key("Escape")
        time.sleep(0.5)
        resumed_luma = self.luma(DARK_PROBE)
        self.result("Escape resumes [pixel]", resumed_luma > paused_luma * 1.3, "probe luma %.0f -> %.0f" % (paused_luma, resumed_luma))

        # 2b. the pause overlay buttons take real mouse clicks too
        s.key("Escape")
        time.sleep(0.5)
        was_paused = self.luma(DARK_PROBE) < combat_luma * 0.7
        s.click(*RESUME_BUTTON)
        time.sleep(0.5)
        luma2 = self.luma(DARK_PROBE)
        self.result("mouse click on RESUME resumes [pixel]", was_paused and luma2 > paused_luma * 1.3, "probe luma %.0f -> %.0f" % (paused_luma, luma2))

        # 3. wait for the first combat to end (--fast: about 4 s), then pick a card with the mouse
        t_end = self.wait_until(lambda: time.time() if self.in_workshop() else None, 30.0, 0.04)
        self.result("first combat ends and the workshop opens [pixel]", bool(t_end), "left probe turns dark")
        if not t_end:
            self.shot("no_workshop")
            return 1
        time.sleep(0.15)
        before = s.grab(*CARDS_REGION)
        s.click(*CARD0)
        time.sleep(0.35)
        after = s.grab(*CARDS_REGION)
        change = before.diff(after)
        still_workshop = self.in_workshop()
        self.result("mouse click on the first card picks it [pixel]", still_workshop and change > 0.08,
                    "card area changed %.0f%% (picked card fitted, others scrapped)" % (change * 100))
        self.shot("workshop_picked")

        # 4. Space = ready: solo ends the workshop at once and the next combat starts
        t_space = time.time()
        s.key("space")
        nxt = self.wait_until(lambda: not self.in_workshop(), 6.0, 0.04)
        dt = time.time() - t_space
        self.result("Space readies up and the next combat starts [pixel]", bool(nxt) and dt < 1.2,
                    "workshop closed %.2f s after Space (%.2f s after it opened; a timeout would take longer)" % (dt, t_space - t_end))
        time.sleep(0.5)
        self.shot("round2_combat")

        # 5. sanity: still running, no script errors
        txt = self.log_text()
        bad = [l for l in txt.splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
        self.result("game still running, no script errors in stdout [stdout]", self.game_alive() and not bad, bad[0] if bad else "clean")
        return 1 if self.failed else 0


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--display", required=True)
    p.add_argument("--log", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--godot-pid", type=int, required=True)
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    r = Runner(a)
    code = r.run()
    print("RESULT: %s (%d step(s) failed of %d)" % ("PASS" if code == 0 else "FAIL", r.failed, r.n), flush=True)
    return code


if __name__ == "__main__":
    sys.exit(main())
