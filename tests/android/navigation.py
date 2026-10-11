import os
import re
import subprocess
import sys
import time

sys.dont_write_bytecode = True
import counter
import list as scroll_list
from counter import adb, LaneError, EmulatorError, EMULATOR

PACKAGE = "dev.neon.NeonNavigation"


def nodes():
    adb("shell", "uiautomator", "dump", "/sdcard/neon-lane.xml")
    xml = adb("shell", "cat", "/sdcard/neon-lane.xml")
    found = []
    for attrs in re.findall(r"<node ([^>]*?)/?>", xml):
        fields = dict(re.findall(r'([\w-]+)="([^"]*)"', attrs))
        if fields.get("package") != PACKAGE:
            continue
        x1, y1, x2, y2 = counter.bounds(fields.get("bounds", "[0,0][0,0]"))
        if x2 <= x1 or y2 <= y1:
            continue
        found.append((fields.get("text", ""), fields.get("content-desc", ""), (x1, y1, x2, y2)))
    return found


def labels(found):
    return sorted(set(t for t, d, b in found if t) | set(d for t, d, b in found if d))


def wait_for(label, seconds=15):
    deadline = time.time() + seconds
    found = []
    while time.time() < deadline:
        try:
            found = nodes()
        except LaneError:
            time.sleep(0.5)
            continue
        for text, desc, frame in found:
            if text == label or desc == label:
                return frame
        time.sleep(0.4)
    window = counter.focus()
    if not window.startswith(PACKAGE + "/"):
        raise EmulatorError("%r never appeared; the focused window is %r" % (label, window))
    raise LaneError("%r never appeared; labels %s" % (label, labels(found)))


def tap(label, seconds=15):
    x1, y1, x2, y2 = wait_for(label, seconds)
    adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
    time.sleep(0.6)


def back():
    adb("shell", "input", "keyevent", "KEYCODE_BACK")
    time.sleep(0.8)


def shot(name, launched):
    with open(os.path.join(counter.results, "screenshots", "navigation-" + name + ".png"), "wb") as out:
        out.write(subprocess.run(["adb", "exec-out", "screencap", "-p"], capture_output=True).stdout)
    current = counter.pid()
    print("NEON_ANDROID navigation-%s pid=%s %s" % (name, current, " | ".join(labels(nodes()))[:300]))
    if current != launched:
        raise LaneError("navigation-%s: pid changed %s -> %s" % (name, launched, current))


def ours():
    return counter.focus().startswith(PACKAGE + "/")


def lane():
    counter.PACKAGE = PACKAGE
    scroll_list.PACKAGE = PACKAGE
    os.makedirs(os.path.join(counter.results, "screenshots"), exist_ok=True)
    scroll_list.launch(PACKAGE)
    counter.rotate(0)
    wait_for("Home taps 0", 40)
    launched = counter.pid()
    shot("list", launched)

    tap("Increment home")
    wait_for("Home taps 1")
    tap("Open Void shader")
    wait_for("Item number 2")
    wait_for("Back")
    shot("detail", launched)

    tap("Edit item")
    tap("Item name")
    adb("shell", "input", "keyevent", "KEYCODE_MOVE_END")
    for _ in range(14):
        adb("shell", "input", "keyevent", "KEYCODE_DEL")
    adb("shell", "input", "text", "Void%srenderer")
    shot("edit", launched)
    tap("Save")
    wait_for("Void renderer")
    wait_for("Item number 2")
    shot("saved", launched)

    back()
    if not ours():
        raise LaneError("hardware back on a pushed screen left the app: %r" % counter.focus())
    wait_for("Home taps 1")
    wait_for("Open Void renderer")
    shot("back-pops-stack", launched)

    tap("Search")
    wait_for("Searches 0")
    tap("Increment search")
    wait_for("Searches 1")
    tap("Add badge")
    shot("search-badge", launched)
    tap("Profile")
    wait_for("Profile taps 0")
    tap("Increment profile")
    wait_for("Profile taps 1")
    tap("Search")
    wait_for("Searches 1")
    back()
    wait_for("Home taps 1")
    shot("back-to-first-tab", launched)

    tap("Show navigation menu")
    wait_for("Close navigation menu")
    shot("drawer-open", launched)
    back()
    wait_for("Home taps 1")
    tap("Show navigation menu")
    tap("Settings")
    wait_for("Settings taps 0")
    shot("settings", launched)
    tap("Toggle dark theme")
    wait_for("Theme: dark")
    shot("dark-theme", launched)
    tap("Toggle dark theme")
    wait_for("Theme: light")
    back()
    wait_for("Home taps 1")
    shot("back-from-settings", launched)

    counter.rotate(1)
    time.sleep(1.5)
    wait_for("Home taps 1")
    shot("landscape", launched)
    counter.rotate(0)
    time.sleep(1.5)

    back()
    deadline = time.time() + 10
    while ours() and time.time() < deadline:
        time.sleep(0.4)
    if ours():
        raise LaneError("hardware back at the root stayed in the app")
    print("NEON_ANDROID navigation-root-back left to %r" % counter.focus())


def main():
    mode = adb("shell", "cmd", "window", "user-rotation").strip()
    try:
        lane()
    except EmulatorError as covered:
        print("FAIL: android navigation " + str(covered), file=sys.stderr)
        return EMULATOR
    except LaneError as failure:
        print("FAIL: android navigation " + str(failure), file=sys.stderr)
        return 1
    finally:
        if mode.startswith("lock"):
            adb("shell", "cmd", "window", "user-rotation", *mode.split())
        else:
            adb("shell", "cmd", "window", "user-rotation", "free")
    return 0


if __name__ == "__main__":
    counter.results = sys.argv[1]
    sys.exit(main())
