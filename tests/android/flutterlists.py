import os
import sys
import time

sys.dont_write_bytecode = True
import counter
import list as scroll_list
from counter import adb, LaneError, EmulatorError, EMULATOR

PACKAGE = "dev.neon.NeonFlutterLists"


def status(texts):
    return scroll_list.label(texts, "status ")


def wait_status(prefix, why, seconds=10):
    deadline = time.time() + seconds
    texts = {}
    while time.time() < deadline:
        window, texts = scroll_list.state(False)
        if status(texts).startswith(prefix):
            return window, texts
        time.sleep(0.3)
    raise LaneError("%s: expected %r, app says %r" % (why, prefix, status(texts)))


def wait_for(text, seconds=15):
    deadline = time.time() + seconds
    texts = {}
    while time.time() < deadline:
        window, texts = scroll_list.state(False)
        if text in texts:
            return window, texts
        time.sleep(0.3)
    raise LaneError("%r never appeared; texts %s" % (text, sorted(texts)))


def middle_y(texts, text):
    return (texts[text][1] + texts[text][3]) // 2


def swipe(x1, y1, x2, y2, ms):
    adb("shell", "input", "swipe", str(x1), str(y1), str(x2), str(y2), str(ms))


def long_drag(x1, y1, x2, y2, ms):
    adb("shell", "input", "draganddrop", str(x1), str(y1), str(x2), str(y2), str(ms))


def report(name, window, texts, launched):
    scroll_list.report("flutterlists-" + name, window, texts, launched)
    print("NEON_ANDROID flutterlists-%s %s" % (name, status(texts)))


def lane():
    counter.PACKAGE = PACKAGE
    scroll_list.PACKAGE = PACKAGE
    os.makedirs(os.path.join(counter.results, "screenshots"), exist_ok=True)
    scroll_list.launch(PACKAGE)
    counter.rotate(0)
    window, texts = wait_for("Mail 2", 30)
    launched = counter.pid()
    width = window[2] - window[0]
    report("mail", window, texts, launched)

    y = middle_y(texts, "Mail 2")
    swipe(window[0] + width * 3 // 10, y, window[0] + width * 9 // 10, y, 250)
    window, texts = wait_status("status archived Mail 2", "a right swipe archives the row")
    time.sleep(1)
    window, texts = scroll_list.state(False)
    if "Mail 2" in texts:
        raise LaneError("the archived row is still listed")
    report("archived", window, texts, launched)

    y = middle_y(texts, "Mail 3")
    swipe(window[0] + width * 7 // 10, y, window[0] + width // 10, y, 250)
    window, texts = wait_status("status deleted Mail 3", "a left swipe deletes the row")
    time.sleep(1)
    window, texts = scroll_list.state(False)

    scroll_list.tap(texts, "Mail 4")
    window, texts = wait_status("status opened Mail 4", "a tap on a swipeable row still presses it")

    y = middle_y(texts, "Mail 6")
    first = texts["Mail 1"][1]
    swipe(window[0] + width // 2, y, window[0] + width // 2, y - 300, 400)
    time.sleep(1.5)
    window, texts = scroll_list.state(False)
    if "Mail 1" in texts and texts["Mail 1"][1] > first - 100:
        raise LaneError("a vertical drag over the rows did not scroll: %s -> %s" % (first, texts["Mail 1"]))
    if status(texts) != "status opened Mail 4":
        raise LaneError("the vertical drag changed the status: %r" % status(texts))
    report("scrolled", window, texts, launched)

    scroll_list.tap(texts, "playlist")
    window, texts = wait_status("status order 1 2 3 4", "the playlist opens")
    x1, y1, x2, y2 = texts["drag 1"]
    hx, hy = (x1 + x2) // 2, (y1 + y2) // 2
    row = texts["drag 2"][1] - texts["drag 1"][1]
    long_drag(hx, hy, hx, hy + row * 23 // 10, 1500)
    window, texts = wait_status("status order 2 3 1 4 moved 0 to 2", "a long-press drag moves song 1 below song 3")
    report("reordered", window, texts, launched)

    scroll_list.tap(texts, "photos")
    window, texts = wait_status("status grid width", "the max-extent grid derives its item width")
    time.sleep(1)
    window, texts = scroll_list.state(False)
    if abs(middle_y(texts, "P1") - middle_y(texts, "P3")) > 2 or texts["P2"][0] <= texts["P1"][0]:
        raise LaneError("three photos must share the first row: %s %s %s" % (texts["P1"], texts["P2"], texts["P3"]))
    report("grid", window, texts, launched)
    scroll_list.tap(texts, "show masonry")
    window, texts = wait_for("P1 c0", 10)
    report("masonry", window, texts, launched)

    scroll_list.tap(texts, "header")
    window, texts = wait_status("status header 200", "the header starts expanded")
    y = middle_y(texts, "Row 3")
    swipe(window[0] + width // 2, y + 200, window[0] + width // 2, y - 400, 500)
    window, texts = wait_status("status header 64", "the pinned header collapses to its toolbar height")
    report("collapsed", window, texts, launched)

    scroll_list.tap(texts, "slivers")
    window, texts = wait_for("Albums", 10)
    top = texts["Albums"][1]
    y = middle_y(texts, "Album 4")
    swipe(window[0] + width // 2, y, window[0] + width // 2, y - 250, 500)
    time.sleep(1.5)
    window, texts = scroll_list.state(False)
    if "Albums" not in texts or texts["Albums"][1] >= top:
        raise LaneError("the banner did not scroll away under the pinned header: %s -> %s" % (top, texts.get("Albums")))
    report("slivers", window, texts, launched)

    scroll_list.tap(texts, "wheel")
    window, texts = wait_for("hour 2", 10)
    density = int(adb("shell", "wm", "density").split()[-1]) / 160.0
    x = (texts["hour 2"][0] + texts["hour 2"][2]) // 2
    y = middle_y(texts, "hour 2")
    swipe(x, y, x, y - int(132 * density), 2000)
    window, texts = wait_status("status picked hour 4", "dragging the wheel three items picks hour 4")
    if counter.pid() != launched:
        raise LaneError("the process restarted")
    report("wheel", window, texts, launched)


def main():
    mode = adb("shell", "cmd", "window", "user-rotation").strip()
    try:
        lane()
    except EmulatorError as covered:
        print("FAIL: android flutterlists " + str(covered), file=sys.stderr)
        return EMULATOR
    except LaneError as failure:
        print("FAIL: android flutterlists " + str(failure), file=sys.stderr)
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
