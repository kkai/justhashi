#!/usr/bin/env python3
"""Captures the App Store screenshot set by driving the simulator.

    python3 AppStore/capture_screenshots.py

Writes AppStore/screenshots/{iphone-65,ipad}/{appearance}-{nn}-{scene}.png.

Three scenes, each in light and dark, on the two sizes App Store Connect
displays: iPhone 11 Pro Max (1242x2688, APP_IPHONE_65) and iPad Pro 12.9"
6th gen (2048x2732, APP_IPAD_PRO_3GEN_129). Not the 6.9" iPhone: uploads of
APP_IPHONE_67 are accepted by the API and then never display in ASC.

Files are uploaded in alphabetical order, so the names control the order the
store shows them in.

Three traps this works around, all learned the hard way on this app:
  * the segmented pickers expose no accessibility elements, so anything
    involving them has to be a coordinate tap
  * a saved game adds a Continue card to Home and shifts everything below it,
    so each run starts from a clean install
  * simctl has no touch injection; drags go through fb-idb, driven from one
    process because chained shell invocations drop taps
"""

import json
import os
import plistlib
import subprocess
import sys
import time

IDB = "/Users/kai/work/areas/ios/kakuro/venv/bin/idb"
BUNDLE = "de.kaikunze.hashi"
APP = "/tmp/hashi-shots/Build/Products/Debug-iphonesimulator/Hashi.app"
ROOT = os.path.dirname(os.path.abspath(__file__))

DEVICES = [
    ("iphone-65", "BCB6EC16-DCF7-4985-839A-A36B45E890F7", (1242, 2688)),
    ("ipad", "6BAA0686-A30B-45E5-9335-0B45466D8F7C", (2048, 2732)),
]


def sh(*args, **kw):
    return subprocess.run(args, capture_output=True, text=True, **kw)


class Sim:
    def __init__(self, udid):
        self.udid = udid
        sh(IDB, "connect", udid)

    def idb(self, *args):
        return sh(IDB, *args, "--udid", self.udid)

    def tree(self):
        out = self.idb("ui", "describe-all").stdout
        try:
            return json.loads(out)
        except json.JSONDecodeError:
            return []

    def find(self, prefix):
        for e in self.tree():
            if (e.get("AXLabel") or "").startswith(prefix):
                f = e["frame"]
                return (f["x"] + f["width"] / 2, f["y"] + f["height"] / 2)
        return None

    def islands(self):
        """Screen centre of every island, keyed by (row, col)."""
        out = {}
        for e in self.tree():
            label = e.get("AXLabel") or ""
            if label.startswith("Island "):
                f = e["frame"]
                p = label.replace(",", "").split()
                out[(int(p[3]) - 1, int(p[5]) - 1)] = (
                    f["x"] + f["width"] / 2, f["y"] + f["height"] / 2)
        return out

    def tap(self, point, wait=1.2):
        self.idb("ui", "tap", str(int(point[0])), str(int(point[1])))
        time.sleep(wait)

    def swipe(self, a, b, wait=0.45):
        self.idb("ui", "swipe", str(int(a[0])), str(int(a[1])),
                 str(int(b[0])), str(int(b[1])), "--duration", "0.22")
        time.sleep(wait)

    def appearance(self, mode):
        sh("xcrun", "simctl", "ui", self.udid, "appearance", mode)

    def status_bar(self):
        sh("xcrun", "simctl", "status_bar", self.udid, "override",
           "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100",
           "--cellularMode", "active", "--cellularBars", "4")

    def fresh_install(self):
        """Clean install so no saved game adds a Continue card to Home."""
        sh("xcrun", "simctl", "terminate", self.udid, BUNDLE)
        sh("xcrun", "simctl", "uninstall", self.udid, BUNDLE)
        sh("xcrun", "simctl", "install", self.udid, APP)
        self.status_bar()

    def launch(self, wait=3.0):
        sh("xcrun", "simctl", "terminate", self.udid, BUNDLE)
        # The paid surfaces are unreachable otherwise: a simulator cannot buy.
        sh("xcrun", "simctl", "launch", self.udid, BUNDLE, "-HashiScreenshotUnlock")
        time.sleep(wait)

    def shot(self, path):
        sh("xcrun", "simctl", "io", self.udid, "screenshot", path)

    def save_game(self):
        """The app's own save, which carries the puzzle and its solution."""
        container = sh("xcrun", "simctl", "get_app_container",
                       self.udid, BUNDLE, "data").stdout.strip()
        plist = os.path.join(container, f"Library/Preferences/{BUNDLE}.plist")
        for _ in range(24):
            try:
                with open(plist, "rb") as fh:
                    data = plistlib.load(fh)
                if "hashi.saveGame.v1" in data:
                    return json.loads(data["hashi.saveGame.v1"])
            except (FileNotFoundError, KeyError):
                pass
            time.sleep(0.5)
        return None


def flatten(path):
    """ASC rejects screenshots with an alpha channel."""
    from PIL import Image
    image = Image.open(path)
    if image.mode != "RGB":
        image.convert("RGB").save(path)


def scene_home(sim, out):
    sim.shot(out)


def scene_game(sim, out):
    """A board part way through, so the bridges and a closed ring are visible.

    Enters through the Daily card rather than Play. The size picker exposes no
    accessibility elements, so choosing a bigger board any other way would mean
    per-device coordinate taps; the Daily is one labelled button on both
    devices, and on a weekend it serves a large board, which fills the frame
    instead of leaving a small grid marooned in it.
    """
    entry = sim.find("Daily puzzle") or sim.find("Play")
    if not entry:
        return False
    sim.tap(entry, wait=4.0)

    islands = sim.islands()
    if not islands:
        return False

    # One move first, so the app writes a save we can read the solution from.
    keys = sorted(islands)
    a = keys[0]
    mates = [k for k in keys if k != a and (k[0] == a[0] or k[1] == a[1])]
    if not mates:
        return False
    b = min(mates, key=lambda k: abs(k[0] - a[0]) + abs(k[1] - a[1]))
    sim.swipe(islands[a], islands[b], wait=1.2)

    save = sim.save_game()
    if save is None:
        return False
    puzzle = save["generated"]["puzzle"]
    solution, current = puzzle["solution"], save["board"]["bridges"]
    position = {i["id"]: i["position"] for i in puzzle["islands"]}

    # About two thirds of the way in: enough structure to read as a real game,
    # with obvious work left so it does not look finished.
    edges = puzzle["edges"]
    target = max(1, int(len(edges) * 0.68))
    for edge in edges[:target]:
        taps = (solution[edge["id"]] - current[edge["id"]]) % 3
        if taps == 0:
            continue
        pa, pb = position[edge["a"]], position[edge["b"]]
        sa = islands.get((pa["row"], pa["col"]))
        sb = islands.get((pb["row"], pb["col"]))
        if not sa or not sb:
            continue
        for _ in range(taps):
            sim.swipe(sa, sb)

    time.sleep(0.8)
    sim.shot(out)
    back = sim.find("Back")
    if back:
        sim.tap(back, wait=1.5)
    return True


def scene_lesson(sim, out):
    """A lesson mid-step, with the instruction card showing."""
    learn = sim.find("Learn")
    if not learn:
        return False
    sim.tap(learn, wait=1.8)
    rules = sim.find("How Hashi Works")
    if not rules:
        return False
    sim.tap(rules, wait=2.0)

    # Next twice reaches the first "draw a bridge" step; drawing it advances to
    # the double-bridge step, which shows a board with a bridge on it AND an
    # instruction, rather than an empty board.
    for _ in range(2):
        nxt = sim.find("Next")
        if nxt:
            sim.tap(nxt, wait=1.0)
    islands = sim.islands()
    if len(islands) >= 2:
        keys = sorted(islands)
        a, b = keys[0], keys[1]
        if a[0] == b[0] or a[1] == b[1]:
            sim.swipe(islands[a], islands[b], wait=1.4)

    time.sleep(0.6)
    sim.shot(out)
    back = sim.find("Back")
    if back:
        sim.tap(back, wait=1.5)
    return True


def main():
    for folder, udid, expected in DEVICES:
        out_dir = os.path.join(ROOT, "screenshots", folder)
        os.makedirs(out_dir, exist_ok=True)
        sim = Sim(udid)

        for appearance in ("light", "dark"):
            sim.appearance(appearance)
            # A clean install per appearance: it also clears the saved game, so
            # Home has no Continue card and the layout is identical every run.
            sim.fresh_install()
            sim.launch()

            scenes = [
                ("01-home", lambda s, p: s.shot(p)),
                ("02-game", scene_game),
                ("03-lesson", scene_lesson),
            ]
            for name, fn in scenes:
                path = os.path.join(out_dir, f"{appearance}-{name}.png")
                if os.path.exists(path):
                    os.remove(path)
                # A scene can miss if a tap lands during a transition. Relaunch
                # to a known state and try again rather than shipping a gap.
                for attempt in range(3):
                    if attempt:
                        sim.launch(wait=3.0)
                    fn(sim, path)
                    if os.path.exists(path):
                        break
                if not os.path.exists(path):
                    print(f"  MISSING {folder}/{appearance}-{name}", file=sys.stderr)
                    continue
                flatten(path)
                from PIL import Image
                size = Image.open(path).size
                flag = "OK " if size == expected else f"WRONG SIZE {size}"
                print(f"  {flag} {folder}/{appearance}-{name}.png")
            # Each scene returns to Home, but relaunch anyway so the next
            # appearance starts from the same place.
            sim.launch(wait=2.5)


if __name__ == "__main__":
    main()
