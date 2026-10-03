import os
import re
import sys
import time

import counter
import list as scroll_list
from counter import adb, LaneError, EmulatorError, EMULATOR

PACKAGE = "dev.neon.NeonFlatList"
ACTIVITY = PACKAGE + "/dev.metascript.app.MainActivity"


def rows_in(texts):
    return len([t for t in texts if t.startswith("row ")])


def memory():
    out = adb("shell", "dumpsys", "meminfo", PACKAGE, check=False)
    pss = re.search(r"TOTAL PSS:\s+(\d+)", out) or re.search(r"^\s*TOTAL\s+(\d+)", out, re.M)
    rss = re.search(r"TOTAL RSS:\s+(\d+)", out)
    return (pss.group(1) if pss else "?"), (rss.group(1) if rss else "?")


def janky():
    out = adb("shell", "dumpsys", "gfxinfo", PACKAGE, check=False)
    total = re.search(r"Total frames rendered:\s+(\d+)", out)
    jank = re.search(r"Janky frames:\s+(\d+) \(([\d.]+)%\)", out)
    return (total.group(1) if total else "?"), (jank.group(1) + " (" + jank.group(2) + "%)" if jank else "?")


def lane():
    counter.PACKAGE = PACKAGE
    scroll_list.PACKAGE = PACKAGE
    os.makedirs(os.path.join(counter.results, "screenshots"), exist_ok=True)
    adb("shell", "am", "force-stop", PACKAGE)
    adb("shell", "am", "start", "-W", "-n", ACTIVITY)
    counter.rotate(0)
    deadline = time.time() + 30
    window, texts = scroll_list.state(False)
    while not scroll_list.label(texts, "mounted ") and time.time() < deadline:
        time.sleep(1)
        window, texts = scroll_list.state(False)
    launched = counter.pid()
    if not launched or not scroll_list.label(texts, "mounted "):
        raise LaneError("the FlatList did not report its mount; texts %s" % sorted(texts)[:20])
    frame = counter.visible_frame(window)
    if not scroll_list.on_screen(texts, frame, "row 0") or "row 9999" in texts:
        raise LaneError("row 0 must be on screen and row 9999 not mounted; texts %s" % sorted(texts)[:20])
    pss, rss = memory()
    print("NEON_ANDROID flatlist-mount %s rows-in-tree=%d pss_kb=%s rss_kb=%s" % (scroll_list.label(texts, "mounted "), rows_in(texts), pss, rss))
    scroll_list.report("flatlist-initial", window, texts, launched)

    adb("shell", "dumpsys", "gfxinfo", PACKAGE, "reset")
    for _ in range(3):
        scroll_list.swipe_up(window)
    window, texts = scroll_list.state(False)
    if scroll_list.label(texts, "offset ") == "offset 0":
        raise LaneError("onScroll did not move the offset")
    if scroll_list.label(texts, "pressed ") != "pressed none":
        raise LaneError("a swipe that starts on a row pressed it: %r" % scroll_list.label(texts, "pressed "))
    frames, jank = janky()
    print("NEON_ANDROID flatlist-swipes frames=%s janky=%s" % (frames, jank))
    scroll_list.report("flatlist-swiped", window, texts, launched)

    scroll_list.tap(texts, "jump 5000")
    window, texts = scroll_list.state(False)
    if not scroll_list.on_screen(texts, frame, "row 5000") or "row 0" in texts:
        raise LaneError("scrollToIndex 5000 did not move the window; texts %s" % sorted(texts)[:20])
    scroll_list.report("flatlist-jumped", window, texts, launched)

    scroll_list.tap(texts, "row 5000")
    window, texts = scroll_list.state(False)
    if "pressed row 5000" not in texts:
        raise LaneError("the tap did not hit row 5000: %r" % scroll_list.label(texts, "pressed "))
    scroll_list.report("flatlist-pressed", window, texts, launched)

    counter.rotate(1)
    window, texts = scroll_list.state(True)
    if "pressed row 5000" not in texts:
        raise LaneError("state lost on rotation")
    scroll_list.report("flatlist-landscape", window, texts, launched)
    counter.rotate(0)
    scroll_list.state(False)

    adb("shell", "input", "keyevent", "KEYCODE_HOME")
    time.sleep(2)
    adb("shell", "monkey", "-p", PACKAGE, "-c", "android.intent.category.LAUNCHER", "1")
    window, texts = scroll_list.state(False)
    if "pressed row 5000" not in texts:
        raise LaneError("state lost on Home and resume")
    pss, rss = memory()
    print("NEON_ANDROID flatlist-after pss_kb=%s rss_kb=%s rows-in-tree=%d" % (pss, rss, rows_in(texts)))
    scroll_list.report("flatlist-resumed", window, texts, launched)


def main():
    mode = adb("shell", "cmd", "window", "user-rotation").strip()
    try:
        lane()
    except EmulatorError as covered:
        print("FAIL: android flatlist " + str(covered), file=sys.stderr)
        return EMULATOR
    except LaneError as failure:
        print("FAIL: android flatlist " + str(failure), file=sys.stderr)
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
