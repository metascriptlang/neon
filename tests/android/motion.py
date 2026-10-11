import os
import re
import struct
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
        state = counter.dump()
        if state is None:
            time.sleep(0.5)
            continue
        window, texts = state[0], dict(state[1])
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


# uiautomator dump waits for a second without accessibility events, so it only ever sees
# an animation's end. The screen is read on the device instead: tap, wait, capture, and
# count the rows of the panel's #45475a in one column.
PANEL = (0x45, 0x47, 0x5A)


def panel_mid(texts, button, x, y, scale):
    bx1, by1, bx2, by2 = texts[button]
    adb("shell", "input tap %d %d; sleep 0.5; screencap /sdcard/neon-motion.raw" % ((bx1 + bx2) // 2, (by1 + by2) // 2))
    data = subprocess.run(["adb", "exec-out", "cat", "/sdcard/neon-motion.raw"], capture_output=True).stdout
    width, height = struct.unpack("<II", data[:8])
    pixels = data[len(data) - width * height * 4:]
    rows = 0
    for at in range(max(0, y - int(20 * scale)), min(height, y + int(200 * scale))):
        offset = (at * width + x) * 4
        if all(abs(pixels[offset + i] - PANEL[i]) < 8 for i in range(3)):
            rows += 1
    return rows


def card_left(button, y, colour, saved=None):
    if saved is None:
        bx1, by1, bx2, by2 = button
        adb("shell", "screencap /sdcard/neon-motion-rest.raw; input tap %d %d; sleep 0.25; screencap /sdcard/neon-motion.raw" % ((bx1 + bx2) // 2, (by1 + by2) // 2))
        saved = "/sdcard/neon-motion.raw"
    data = subprocess.run(["adb", "exec-out", "cat", saved], capture_output=True).stdout
    width, height = struct.unpack("<II", data[:8])
    pixels = data[len(data) - width * height * 4:]
    for x in range(width):
        offset = (y * width + x) * 4
        if all(abs(pixels[offset + i] - colour[i]) < 8 for i in range(3)):
            return x
    raise LaneError("no %s pixel on row %d" % (colour, y))


def spinner_frames(label, button):
    x1, y1, x2, y2 = label
    cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
    tap = "" if button is None else "input tap %d %d; sleep 0.6; " % ((button[0] + button[2]) // 2, (button[1] + button[3]) // 2)
    adb("shell", tap + "screencap /sdcard/neon-spin-a.raw; sleep 0.2; screencap /sdcard/neon-spin-b.raw")
    frames = []
    for name in ("a", "b"):
        data = subprocess.run(["adb", "exec-out", "cat", "/sdcard/neon-spin-%s.raw" % name], capture_output=True).stdout
        width, height = struct.unpack("<II", data[:8])
        pixels = data[len(data) - width * height * 4:]
        crop = b"".join(pixels[(y * width + cx - 150) * 4:(y * width + cx + 150) * 4] for y in range(cy - 150, cy + 150))
        frames.append(crop)
    return frames


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
    cy1, cy2 = texts["spring card"][1], texts["spring card"][3]
    card = card_left(texts["spring"], (cy1 + cy2) // 2, (0xA6, 0xE3, 0xA1))
    mid = card - (card_left(None, (cy1 + cy2) // 2, (0xA6, 0xE3, 0xA1), "/sdcard/neon-motion-rest.raw"))
    report("spring-mid", texts, launched, "moved=%d px" % mid)
    # friction 4 overshoots by about a fifth near 0.25 s, so "on its way" is off both ends.
    if mid <= 5 or abs(mid - 160 * scale) <= 3:
        raise LaneError("the spring card should be on its way 0.25 s after the press: moved %d px of %d" % (mid, 160 * scale))
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
    opened = panel_mid(texts, "expand", left(texts, "after panel") + 20, before, scale)
    report("panel-mid", texts, launched, "panel=%d px" % opened)
    if not (5 < opened < 150 * scale):
        raise LaneError("the panel should be part open 0.5 s into its 1.5 s animation: %d px of %d" % (opened, 160 * scale))
    time.sleep(2.0)
    window, texts = raw()
    end = top(texts, "after panel")
    report("panel-end", texts, launched, "y=%d before=%d" % (end, before))
    if abs((end - before) - 160 * scale) > 3:
        raise LaneError("the text below should move by the panel's 160 dp: %d px" % (end - before))

    # A looping animation keeps accessibility events coming, so uiautomator never gets its
    # idle state ("could not get idle state") while it runs: the spin is read from pixels.
    toggle = texts["start spin"]
    centre = texts["spin"]
    still = spinner_frames(centre, None)
    if still[0] != still[1]:
        raise LaneError("the spinner moved before the spin started")
    moving = spinner_frames(centre, toggle)
    report("spin-a", texts, launched)
    if moving[0] == moving[1] or moving[0] == still[0]:
        raise LaneError("the spinner did not turn after start spin")
    stopped = spinner_frames(centre, toggle)
    if stopped[0] != stopped[1]:
        raise LaneError("the spinner kept turning after stop spin")
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
