import os
import subprocess
import sys
import time

sys.dont_write_bytecode = True
import counter
from counter import adb, LaneError, EmulatorError, EMULATOR

PACKAGE = "dev.neon.NeonList"


def state(landscape):
    for attempt in range(3):
        try:
            window, texts = counter.settle(landscape)
            return window, dict(texts)
        except LaneError as failure:
            if "neon-lane.xml" not in str(failure) or attempt == 2:
                raise
            time.sleep(1)


def launch(package):
    adb("shell", "am", "force-stop", package)
    adb("shell", "monkey", "-p", package, "-c", "android.intent.category.LAUNCHER", "1")


def label(texts, prefix):
    for text in texts:
        if text.startswith(prefix):
            return text
    return ""


def on_screen(texts, frame, text):
    if text not in texts:
        return False
    x1, y1, x2, y2 = texts[text]
    return x2 > x1 and y2 > y1 and y1 >= frame[1] and y2 <= frame[3]


def report(name, window, texts, expected_pid):
    shot = subprocess.run(["adb", "exec-out", "screencap", "-p"], capture_output=True)
    with open(os.path.join(counter.results, "screenshots", "list-" + name + ".png"), "wb") as out:
        out.write(shot.stdout)
    current = counter.pid()
    print("NEON_ANDROID list-%s pid=%s window=%s %s %s" % (name, current, window, label(texts, "offset "), label(texts, "pressed ")))
    if current != expected_pid:
        raise LaneError("list-%s: pid changed %s -> %s" % (name, expected_pid, current))


def swipe_up(window):
    x = (window[0] + window[2]) // 2
    height = window[3] - window[1]
    adb("shell", "input", "swipe", str(x), str(window[1] + height * 3 // 4), str(x), str(window[1] + height // 3), "400")


def tap(texts, text):
    x1, y1, x2, y2 = texts[text]
    adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))


def lane():
    counter.PACKAGE = PACKAGE
    os.makedirs(os.path.join(counter.results, "screenshots"), exist_ok=True)
    launch(PACKAGE)
    counter.rotate(0)
    window, texts = state(False)
    launched = counter.pid()
    if not launched:
        raise LaneError("the list did not start")
    frame = counter.visible_frame(window)
    if label(texts, "offset ") != "offset 0":
        raise LaneError("initial offset is %r" % label(texts, "offset "))
    if not on_screen(texts, frame, "row 1") or on_screen(texts, frame, "row 30"):
        raise LaneError("row 1 must start on screen and row 30 below the fold; texts %s" % sorted(texts))
    report("initial", window, texts, launched)

    swipes = 0
    while not on_screen(texts, frame, "row 30") and swipes < 8:
        swipe_up(window)
        swipes += 1
        window, texts = state(False)
    if not on_screen(texts, frame, "row 30"):
        raise LaneError("row 30 not on screen after %d swipes; texts %s" % (swipes, sorted(texts)))
    if label(texts, "offset ") == "offset 0":
        raise LaneError("onScroll did not move the offset")
    if label(texts, "pressed ") != "pressed none":
        raise LaneError("a swipe that starts on a row pressed it: %r" % label(texts, "pressed "))
    report("scrolled", window, texts, launched)

    tap(texts, "row 30")
    window, texts = state(False)
    if "pressed row 30" not in texts:
        raise LaneError("the tap after scrolling did not hit row 30: %r" % label(texts, "pressed "))
    report("pressed", window, texts, launched)

    counter.rotate(1)
    window, texts = state(True)
    if "pressed row 30" not in texts:
        raise LaneError("state lost on rotation: %r" % label(texts, "pressed "))
    report("landscape", window, texts, launched)
    counter.rotate(0)
    state(False)

    adb("shell", "input", "keyevent", "KEYCODE_HOME")
    time.sleep(2)
    adb("shell", "monkey", "-p", PACKAGE, "-c", "android.intent.category.LAUNCHER", "1")
    window, texts = state(False)
    if "pressed row 30" not in texts:
        raise LaneError("state lost on Home and resume: %r" % label(texts, "pressed "))
    report("resumed", window, texts, launched)


def main():
    mode = adb("shell", "cmd", "window", "user-rotation").strip()
    try:
        lane()
    except EmulatorError as covered:
        print("FAIL: android list " + str(covered), file=sys.stderr)
        return EMULATOR
    except LaneError as failure:
        print("FAIL: android list " + str(failure), file=sys.stderr)
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
