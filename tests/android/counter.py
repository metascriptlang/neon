import os
import re
import subprocess
import sys
import time

PACKAGE = "dev.neon.NeonCounter"
ACTIVITY = PACKAGE + "/dev.metascript.app.MainActivity"
LABELS = ["-", "reset", "+"]
PRESS_CARD = "~/metascript/.inbox/compiler/2026-09-23-design-android-java-handoff.md"
results = sys.argv[1]


class LaneError(Exception):
    pass


def adb(*args, check=True):
    done = subprocess.run(["adb", *args], capture_output=True, text=True)
    if check and done.returncode != 0:
        raise LaneError("adb " + " ".join(args) + " failed: " + done.stderr.strip())
    return done.stdout


def pid():
    return adb("shell", "pidof", PACKAGE, check=False).strip()


def bounds(text):
    x1, y1, x2, y2 = map(int, re.findall(r"-?\d+", text))
    return (x1, y1, x2, y2)


def visible_frame(window):
    left, top, right, bottom = window
    for line in adb("shell", "dumpsys", "window").splitlines():
        match = re.search(r"InsetsSource id=\S+ type=(statusBars|navigationBars|displayCutout) frame=(\[[^ ]+\]) visible=true", line)
        if not match or "mSource=" in line:
            continue
        x1, y1, x2, y2 = bounds(match.group(2))
        if x2 <= x1 or y2 <= y1:
            continue
        if y1 == window[1] and x2 - x1 >= y2 - y1 and (x1, x2) == (window[0], window[2]):
            top = max(top, y2)
        elif y2 == window[3] and x2 - x1 >= y2 - y1 and (x1, x2) == (window[0], window[2]):
            bottom = min(bottom, y1)
        elif x1 == window[0] and (y1, y2) == (window[1], window[3]):
            left = max(left, x2)
        elif x2 == window[2] and (y1, y2) == (window[1], window[3]):
            right = min(right, x1)
    return (left, top, right, bottom)


def dump():
    adb("shell", "uiautomator", "dump", "/sdcard/neon-lane.xml")
    xml = adb("shell", "cat", "/sdcard/neon-lane.xml")
    nodes = re.findall(r"<node [^>]*?text=\"([^\"]*)\"[^>]*?class=\"([^\"]*)\"[^>]*?package=\"" + re.escape(PACKAGE) + r"\"[^>]*?bounds=\"([^\"]*)\"", xml)
    if not nodes:
        return None
    window = bounds(nodes[0][2])
    texts = [(text, bounds(b)) for text, cls, b in nodes if cls == "android.widget.TextView"]
    return window, texts


def settle(landscape):
    last = None
    deadline = time.time() + 30
    while time.time() < deadline:
        state = dump()
        if state and (state[0][2] > state[0][3]) == landscape and state == last:
            return state
        last = state
        time.sleep(1)
    raise LaneError("the counter did not settle " + ("landscape" if landscape else "portrait") + "; last dump " + repr(last))


def snapshot(name, landscape, expected_pid, value, parity):
    window, texts = settle(landscape)
    frame = visible_frame(window)
    adb_png = subprocess.run(["adb", "exec-out", "screencap", "-p"], capture_output=True)
    with open(os.path.join(results, "screenshots", name + ".png"), "wb") as out:
        out.write(adb_png.stdout)
    current = pid()
    listed = ", ".join(t + "@" + str(b) for t, b in texts)
    print("NEON_ANDROID %s pid=%s window=%s visible=%s texts=[%s]" % (name, current, window, frame, listed))
    if current != expected_pid:
        raise LaneError("%s: pid changed %s -> %s" % (name, expected_pid, current))
    found = [t for t, _ in texts]
    for want in ["Neon Counter", value, parity] + LABELS:
        if want not in found:
            raise LaneError("%s: no %r text among %s" % (name, want, found))
    for text, (x1, y1, x2, y2) in texts:
        if x2 <= x1 or y2 <= y1:
            raise LaneError("%s: %r has an empty frame %s" % (name, text, (x1, y1, x2, y2)))
        if x1 < frame[0] or y1 < frame[1] or x2 > frame[2] or y2 > frame[3]:
            raise LaneError("%s: %r at %s leaves the visible frame %s" % (name, text, (x1, y1, x2, y2), frame))
    return dict(texts)


def rotate(quarter):
    adb("shell", "cmd", "window", "user-rotation", "lock", str(quarter))


def press_plus(texts, name, value, parity, landscape, expected_pid):
    x1, y1, x2, y2 = texts["+"]
    adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
    try:
        return snapshot(name, landscape, expected_pid, value, parity)
    except LaneError as failure:
        raise LaneError("%s (touch routing is parked on %s)" % (failure, PRESS_CARD))


def lane():
    os.makedirs(os.path.join(results, "screenshots"), exist_ok=True)
    adb("shell", "am", "force-stop", PACKAGE)
    adb("shell", "am", "start", "-W", "-n", ACTIVITY)
    rotate(0)
    first = settle(False)
    launched = pid()
    if not launched or not first:
        raise LaneError("the counter did not start")
    snapshot("portrait-initial", False, launched, "0", "even")
    rotate(1)
    snapshot("landscape", True, launched, "0", "even")
    rotate(0)
    snapshot("portrait-returned", False, launched, "0", "even")
    adb("shell", "input", "keyevent", "KEYCODE_HOME")
    time.sleep(2)
    adb("shell", "monkey", "-p", PACKAGE, "-c", "android.intent.category.LAUNCHER", "1")
    texts = snapshot("foreground-returned", False, launched, "0", "even")
    texts = press_plus(texts, "portrait-pressed", "1", "odd", False, launched)
    rotate(1)
    texts = snapshot("landscape-after-press", True, launched, "1", "odd")
    press_plus(texts, "landscape-pressed", "2", "even", True, launched)


def main():
    mode = adb("shell", "cmd", "window", "user-rotation").strip()
    try:
        lane()
    except LaneError as failure:
        print("FAIL: android " + str(failure), file=sys.stderr)
        return 1
    finally:
        if mode.startswith("lock"):
            adb("shell", "cmd", "window", "user-rotation", *mode.split())
        else:
            adb("shell", "cmd", "window", "user-rotation", "free")
    return 0


sys.exit(main())
