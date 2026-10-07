import os
import re
import subprocess
import sys
import time

sys.dont_write_bytecode = True
import counter
import list as scroll_list
from counter import adb, LaneError, EmulatorError, EMULATOR

PACKAGE = "dev.neon.NeonMotion"


def status(texts):
    return scroll_list.label(texts, "fade ")


def raw():
    state = counter.dump()
    if state is None:
        raise LaneError("no %s window in the dump" % PACKAGE)
    window, texts = state
    return window, dict(texts)


def wait_status(part, seconds):
    deadline = time.time() + seconds
    texts = {}
    while time.time() < deadline:
        window, texts = raw()
        if part in status(texts):
            return window, texts
        time.sleep(0.3)
    raise LaneError("status never contained %r; last %r" % (part, status(texts)))


def shot(name):
    png = subprocess.run(["adb", "exec-out", "screencap", "-p"], capture_output=True)
    path = os.path.join(counter.results, "screenshots", "motion-" + name + ".png")
    with open(path, "wb") as out:
        out.write(png.stdout)
    return path


def report(name, texts, launched, detail=""):
    shot(name)
    current = counter.pid()
    print("NEON_ANDROID motion-%s pid=%s %s status=%r" % (name, current, detail, status(texts)))
    if current != launched:
        raise LaneError("motion-%s: pid changed %s -> %s" % (name, launched, current))


def left(texts, text):
    return texts[text][0]


def top(texts, text):
    return texts[text][1]


def dp():
    density = adb("shell", "wm", "density").strip().split()[-1]
    return int(density) / 160.0


def janky():
    out = adb("shell", "dumpsys", "gfxinfo", PACKAGE, check=False)
    total = re.search(r"Total frames rendered:\s+(\d+)", out)
    jank = re.search(r"Janky frames:\s+(\d+) \(([\d.]+)%\)", out)
    return (total.group(1) if total else "?"), (jank.group(1) + " (" + jank.group(2) + "%)" if jank else "?")


def lane():
    counter.PACKAGE = PACKAGE
    scroll_list.PACKAGE = PACKAGE
    os.makedirs(os.path.join(counter.results, "screenshots"), exist_ok=True)
    scroll_list.launch(PACKAGE)
    counter.rotate(0)
    window, texts = wait_status("fade 1", 30)
    launched = counter.pid()
    scale = dp()
    adb("shell", "dumpsys", "gfxinfo", PACKAGE, "reset", check=False)
    report("initial", texts, launched)

    rest = left(texts, "spring card")
    scroll_list.tap(texts, "spring")
    time.sleep(0.25)
    window, texts = raw()
    mid = left(texts, "spring card")
    report("spring-mid", texts, launched, "x=%d rest=%d" % (mid, rest))
    if mid <= rest + 5:
        raise LaneError("the spring card had not moved 0.25 s after the press: %d -> %d" % (rest, mid))
    window, texts = wait_status("spring 160", 10)
    time.sleep(0.3)
    window, texts = raw()
    end = left(texts, "spring card")
    report("spring-end", texts, launched, "x=%d rest=%d" % (end, rest))
    if abs((end - rest) - 160 * scale) > 3:
        raise LaneError("the card should rest 160 dp right: moved %d px at %.2f px/dp" % (end - rest, scale))

    scroll_list.tap(texts, "fade")
    time.sleep(0.35)
    report("fade-mid", texts, launched)
    window, texts = wait_status("fade 0", 10)
    report("fade-end", texts, launched)

    before = top(texts, "after panel")
    scroll_list.tap(texts, "expand")
    time.sleep(0.2)
    window, texts = raw()
    mid = top(texts, "after panel")
    report("panel-mid", texts, launched, "y=%d before=%d" % (mid, before))
    if not (before + 5 < mid < before + 150 * scale):
        raise LaneError("the panel should be part open 0.2 s in: %d -> %d" % (before, mid))
    time.sleep(2.0)
    window, texts = raw()
    end = top(texts, "after panel")
    report("panel-end", texts, launched, "y=%d before=%d" % (end, before))
    if abs((end - before) - 160 * scale) > 3:
        raise LaneError("the text below should move by the panel's 160 dp: %d px" % (end - before))

    scroll_list.tap(texts, "start spin")
    window, texts = wait_status("spin on", 10)
    time.sleep(0.4)
    report("spin-a", texts, launched)
    time.sleep(0.3)
    report("spin-b", texts, launched)
    window, texts = raw()
    scroll_list.tap(texts, "stop spin")
    window, texts = wait_status("spin off", 10)

    title = top(texts, "Neon motion")
    x1, y1, x2, y2 = texts["row 3"]
    cx = (x1 + x2) // 2
    adb("shell", "input", "swipe", str(cx), str(y1), str(cx), str(y1 - int(260 * scale)), "500")
    time.sleep(1.0)
    window, texts = raw()
    shrunk = top(texts, "Neon motion")
    report("header-scrolled", texts, launched, "titleY=%d before=%d" % (shrunk, title))
    if shrunk >= title - 10:
        raise LaneError("the header should shrink with the scroll: title %d -> %d" % (title, shrunk))

    total, jank = janky()
    print("NEON_ANDROID motion-frames total=%s janky=%s" % (total, jank))


def main():
    mode = adb("shell", "cmd", "window", "user-rotation").strip()
    try:
        lane()
    except EmulatorError as covered:
        print("FAIL: android motion " + str(covered), file=sys.stderr)
        return EMULATOR
    except LaneError as failure:
        print("FAIL: android motion " + str(failure), file=sys.stderr)
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
