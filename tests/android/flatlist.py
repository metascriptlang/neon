import os
import re
import sys
import time

sys.dont_write_bytecode = True
import counter
import list as scroll_list
from counter import adb, LaneError, EmulatorError, EMULATOR

PACKAGE = "dev.neon.NeonFlatList"


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
    scroll_list.launch(PACKAGE)
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
    narrow = width(texts, scroll_list.label(texts, "offset "))

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
    if not scroll_list.on_screen(texts, frame, "row 5000") or "row 1000" in texts:
        raise LaneError("scrollToIndex 5000 did not move the window; texts %s" % sorted(texts)[:20])
    if scroll_list.on_screen(texts, frame, "row 0"):
        raise LaneError("row 0 is still on screen after scrollToIndex 5000; texts %s" % sorted(texts)[:20])
    wide = scroll_list.label(texts, "offset ")
    if width(texts, wide) <= narrow:
        raise LaneError("%r kept the %dpx frame of \"offset 0\": the label was not remeasured" % (wide, narrow))
    scroll_list.report("flatlist-jumped", window, texts, launched)

    adb("shell", "dumpsys", "gfxinfo", PACKAGE, "reset")
    for _ in range(3):
        scroll_list.swipe_up(window)
    frames, jank = janky()
    print("NEON_ANDROID flatlist-swipes-after-jump frames=%s janky=%s" % (frames, jank))
    scroll_list.tap(texts, "jump 5000")
    window, texts = scroll_list.state(False)

    scroll_list.tap(texts, "row 5000")
    window, texts = scroll_list.state(False)
    if "pressed row 5000" not in texts:
        raise LaneError("the tap did not hit row 5000: %r" % scroll_list.label(texts, "pressed "))
    scroll_list.report("flatlist-pressed", window, texts, launched)

    x1, y1, x2, y2 = texts["row 5001"]
    x, y = str((x1 + x2) // 2), str((y1 + y2) // 2)
    adb("shell", "input", "swipe", x, y, x, y, "1200")
    window, texts = scroll_list.state(False)
    if "pressed long row 5001" not in texts:
        raise LaneError("a held row did not fire onLongPress on its std timer: %r" % scroll_list.label(texts, "pressed "))
    scroll_list.report("flatlist-long-pressed", window, texts, launched)
    scroll_list.tap(texts, "row 5000")
    window, texts = scroll_list.state(False)
    if "pressed row 5000" not in texts:
        raise LaneError("the tap did not hit row 5000 again: %r" % scroll_list.label(texts, "pressed "))

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


def dp():
    density = re.search(r"(\d+)\s*$", adb("shell", "wm", "density").strip().splitlines()[-1])
    return int(density.group(1)) / 160


def width(texts, text):
    return texts[text][2] - texts[text][0]


def top(texts, text):
    return texts[text][1]


def measured_lane():
    scale = dp()
    launched = counter.pid()
    scroll_list.tap(scroll_list.state(False)[1], "measured rows")
    window, texts = scroll_list.state(False)
    frame = counter.visible_frame(window)
    for want in ["header 0", "item 1", "item 2", "item 3"]:
        if want not in texts:
            raise LaneError("measured mode did not mount %r; texts %s" % (want, sorted(texts)[:20]))
    for upper, lower, height in [("item 1", "item 2", 80), ("item 2", "item 3", 112)]:
        gap = (top(texts, lower) - top(texts, upper)) / scale
        if abs(gap - height) > 2:
            raise LaneError("measured %s is %.1fdp tall, expected %d" % (upper, gap, height))
    pinned = top(texts, "header 0")
    scroll_list.report("flatlist-measured-initial", window, texts, launched)

    x1, y1, x2, y2 = texts["item 2"]
    x, y = (x1 + 4 * x2) // 5, (y1 + y2) // 2
    adb("shell", "input", "swipe", str(x), str(y), str(x), str(y - int(110 * scale)), "600")
    window, texts = scroll_list.state(False)
    if scroll_list.label(texts, "offset ") == "offset 0":
        raise LaneError("a drag did not scroll the measured list")
    if "header 0" not in texts or abs(top(texts, "header 0") - pinned) > 2 * scale:
        raise LaneError("header 0 left its pinned top %d after a drag: %s" % (pinned, texts.get("header 0")))
    if scroll_list.label(texts, "pressed ") != "pressed none":
        raise LaneError("scrolling pressed a row: %r" % scroll_list.label(texts, "pressed "))
    scroll_list.tap(texts, "header 0")
    window, texts = scroll_list.state(False)
    if "pressed header 0" not in texts:
        raise LaneError("the pinned header did not receive its press: %r" % scroll_list.label(texts, "pressed "))
    scroll_list.report("flatlist-measured-sticky-pressed", window, texts, launched)

    scroll_list.tap(texts, "inverted rows")
    time.sleep(1)
    window, texts = scroll_list.state(False)
    if "pressed header 0" not in texts:
        raise LaneError("inversion lost the mounted list state: %r" % scroll_list.label(texts, "pressed "))
    x1, y1, x2, y2 = texts["item 3"]
    x, y = (x1 + 4 * x2) // 5, (y1 + y2) // 2
    adb("shell", "input", "swipe", str(x), str(y - int(150 * scale)), str(x), str(y + int(150 * scale)), "600")
    time.sleep(1)
    window, texts = scroll_list.state(False)
    headers = [t for t in texts if t.startswith("header ") and scroll_list.on_screen(texts, frame, t)]
    if not headers:
        raise LaneError("no header is pinned after dragging the inverted list; texts %s" % sorted(texts)[:20])
    selected = min(headers, key=lambda t: top(texts, t))
    if abs(top(texts, selected) - pinned) > 2 * scale:
        raise LaneError("inverted %r sits at %d, not pinned at the list top %d" % (selected, top(texts, selected), pinned))
    scroll_list.tap(texts, selected)
    window, texts = scroll_list.state(False)
    if "pressed " + selected not in texts:
        raise LaneError("the inverted header %r did not receive its press: %r" % (selected, scroll_list.label(texts, "pressed ")))
    scroll_list.report("flatlist-inverted-sticky-pressed", window, texts, launched)

    scroll_list.tap(texts, "measured rows")
    window, texts = scroll_list.state(False)
    for _ in range(12):
        if scroll_list.on_screen(texts, frame, "List end"):
            break
        scroll_list.tap(texts, "measured end")
        time.sleep(0.4)
        window, texts = scroll_list.state(False)
    if not scroll_list.on_screen(texts, frame, "item 63"):
        raise LaneError("the measured list did not reach item 63; texts %s" % sorted(texts)[:20])
    if not scroll_list.on_screen(texts, frame, "List end"):
        raise LaneError("the footer is not on screen at the measured end; texts %s" % sorted(texts)[:20])
    print("NEON_ANDROID flatlist-measured-end %s %s" % (scroll_list.label(texts, "offset "), scroll_list.label(texts, "ends ")))
    scroll_list.report("flatlist-measured-end", window, texts, launched)


def left(texts, text):
    return texts[text][0]


def grid_lane():
    scale = dp()
    launched = counter.pid()
    scroll_list.tap(scroll_list.state(False)[1], "grid")
    window, texts = scroll_list.state(False)
    for want in ["cell 0", "cell 1", "cell 2", "cell 3", "cell 4", "cell 5"]:
        if want not in texts:
            raise LaneError("grid mode did not mount %r; texts %s" % (want, sorted(texts)[:20]))
    first = top(texts, "cell 0")
    column0 = left(texts, "cell 0")
    for cell in ["cell 1", "cell 2"]:
        if abs(top(texts, cell) - first) > 2:
            raise LaneError("%s is not in the first row: top %d vs %d" % (cell, top(texts, cell), first))
    if not left(texts, "cell 0") < left(texts, "cell 1") < left(texts, "cell 2"):
        raise LaneError("the first row is not laid out left to right: %s" % [texts["cell %d" % i] for i in range(3)])
    row_gap = (top(texts, "cell 3") - first) / scale
    if abs(row_gap - 68) > 2:
        raise LaneError("rows are %.1fdp apart, expected 64dp cells plus the 4dp columnWrapperStyle margin" % row_gap)
    if abs(left(texts, "cell 3") - left(texts, "cell 0")) > 2:
        raise LaneError("cell 3 does not open the second row under cell 0")
    scroll_list.report("flatlist-grid-initial", window, texts, launched)

    scroll_list.tap(texts, "cell 4")
    window, texts = scroll_list.state(False)
    if "pressed cell 4 at 4" not in texts:
        raise LaneError("the tap did not hit cell 4: %r" % scroll_list.label(texts, "pressed "))
    scroll_list.tap(texts, "prepend")
    window, texts = scroll_list.state(False)
    if "cell 60" not in texts or abs(top(texts, "cell 60") - first) > 2 or abs(left(texts, "cell 60") - column0) > 2:
        raise LaneError("the prepended cell 60 is not first in the first row; texts %s" % sorted(texts)[:20])
    if abs(top(texts, "cell 0") - first) > 2 or not left(texts, "cell 60") < left(texts, "cell 0"):
        raise LaneError("cell 0 did not move to the second column of the first row: %s" % texts.get("cell 0"))
    if "pressed cell 4 at 4" not in texts:
        raise LaneError("prepending lost the screen state: %r" % scroll_list.label(texts, "pressed "))
    scroll_list.tap(texts, "cell 4")
    window, texts = scroll_list.state(False)
    if "pressed cell 4 at 5" not in texts:
        raise LaneError("cell 4 does not read its new index 5 after the prepend: %r" % scroll_list.label(texts, "pressed "))
    scroll_list.report("flatlist-grid-prepended", window, texts, launched)

    for _ in range(2):
        scroll_list.swipe_up(window)
    window, texts = scroll_list.state(False)
    if scroll_list.label(texts, "pressed ") != "pressed cell 4 at 5":
        raise LaneError("a swipe that starts on a cell pressed it: %r" % scroll_list.label(texts, "pressed "))
    frame = counter.visible_frame(window)
    visible = [t for t in texts if t.startswith("cell ") and scroll_list.on_screen(texts, frame, t)]
    if "cell 0" in visible or not visible:
        raise LaneError("the grid did not scroll; visible %s" % sorted(visible))
    target = max(visible, key=lambda t: (top(texts, t), left(texts, t)))
    scroll_list.tap(texts, target)
    window, texts = scroll_list.state(False)
    if not scroll_list.label(texts, "pressed ").startswith("pressed " + target + " at "):
        raise LaneError("the tap after scrolling did not hit %r: %r" % (target, scroll_list.label(texts, "pressed ")))
    print("NEON_ANDROID flatlist-grid rows-apart-dp=%.1f %s" % (row_gap, scroll_list.label(texts, "pressed ")))
    scroll_list.report("flatlist-grid-scrolled-pressed", window, texts, launched)


def sections_lane():
    scale = dp()
    launched = counter.pid()
    scroll_list.tap(scroll_list.state(False)[1], "sections")
    window, texts = scroll_list.state(False)
    frame = counter.visible_frame(window)
    for want in ["Section 0", "item 0", "item 1", "Section 1", "item 100"]:
        if want not in texts:
            raise LaneError("sections mode did not mount %r; texts %s" % (want, sorted(texts)[:20]))
    pinned = top(texts, "Section 0")
    if not pinned < top(texts, "item 0") < top(texts, "item 1") < top(texts, "Section 1") < top(texts, "item 100"):
        raise LaneError("header, items, next header are out of order: %s" % {t: texts[t] for t in ["Section 0", "item 0", "item 1", "Section 1", "item 100"]})
    scroll_list.report("flatlist-sections-initial", window, texts, launched)

    x1, y1, x2, y2 = texts["item 1"]
    x, y = (x1 + 4 * x2) // 5, (y1 + y2) // 2
    adb("shell", "input", "swipe", str(x), str(y), str(x), str(y - int(60 * scale)), "600")
    window, texts = scroll_list.state(False)
    if "Section 0" not in texts or abs(top(texts, "Section 0") - pinned) > 2 * scale:
        raise LaneError("Section 0 left its pinned top %d after a short drag: %s" % (pinned, texts.get("Section 0")))
    if scroll_list.label(texts, "pressed ") != "pressed none":
        raise LaneError("scrolling pressed an item: %r" % scroll_list.label(texts, "pressed "))
    scroll_list.report("flatlist-sections-sticky", window, texts, launched)

    scroll_list.tap(texts, "section 1")
    time.sleep(1)
    window, texts = scroll_list.state(False)
    if "jump waits" in scroll_list.label(texts, "pressed "):
        raise LaneError("scrollToLocation reported an unmeasured target: %r" % scroll_list.label(texts, "pressed "))
    if "Section 1" not in texts or abs(top(texts, "Section 1") - pinned) > 2 * scale:
        raise LaneError("scrollToLocation(1, 0) did not bring Section 1 to the list top %d: %s" % (pinned, texts.get("Section 1")))
    if scroll_list.on_screen(texts, frame, "Section 0") and top(texts, "Section 0") >= pinned - 2:
        raise LaneError("Section 0 still sits at the top after Section 1 took over: %s" % texts.get("Section 0"))
    scroll_list.tap(texts, "item 101")
    window, texts = scroll_list.state(False)
    if "pressed Section 1 item 1" not in texts:
        raise LaneError("the tap did not hit item 101 as Section 1 item 1: %r" % scroll_list.label(texts, "pressed "))
    print("NEON_ANDROID flatlist-sections pinned-top=%d %s" % (pinned, scroll_list.label(texts, "pressed ")))
    scroll_list.report("flatlist-sections-located-pressed", window, texts, launched)


def main():
    mode = adb("shell", "cmd", "window", "user-rotation").strip()
    try:
        lane()
        measured_lane()
        grid_lane()
        sections_lane()
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
