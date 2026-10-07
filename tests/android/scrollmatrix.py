import os
import sys
import time

sys.dont_write_bytecode = True
import counter
import list as scroll_list
from counter import adb, LaneError, EmulatorError, EMULATOR

PACKAGE = "dev.neon.NeonScrollMatrix"


def drag(x1, y1, x2, y2, ms=500):
    adb("shell", "input", "swipe", str(x1), str(y1), str(x2), str(y2), str(ms))


def centre(texts, text):
    x1, y1, x2, y2 = texts[text]
    return (x1 + x2) // 2, (y1 + y2) // 2


def offsets(texts):
    words = scroll_list.label(texts, "x ").split()
    return int(words[1]), int(words[3])


def wait_for(text, seconds):
    deadline = time.time() + seconds
    while time.time() < deadline:
        window, texts = scroll_list.state(False)
        if text in texts:
            return window, texts
        time.sleep(0.3)
    raise LaneError("%r never appeared; texts %s" % (text, sorted(texts)))


def lane():
    counter.PACKAGE = PACKAGE
    scroll_list.PACKAGE = PACKAGE
    os.makedirs(os.path.join(counter.results, "screenshots"), exist_ok=True)
    scroll_list.launch(PACKAGE)
    counter.rotate(0)
    window, texts = wait_for("axis horizontal", 30)
    launched = counter.pid()
    frame = counter.visible_frame(window)
    if not scroll_list.on_screen(texts, frame, "card 1") or "card 2" not in texts:
        raise LaneError("card 1 and card 2 must start on screen; texts %s" % sorted(texts))
    if texts["card 2"][1] != texts["card 1"][1] or texts["card 2"][0] <= texts["card 1"][0]:
        raise LaneError("horizontal cards must share a row: %s %s" % (texts["card 1"], texts["card 2"]))
    if offsets(texts) != (0, 0):
        raise LaneError("initial offsets %r" % scroll_list.label(texts, "x "))
    scroll_list.report("matrix-initial", window, texts, launched)

    cx, cy = centre(texts, "card 2")
    width = window[2] - window[0]
    drag(window[0] + width * 4 // 5, cy, window[0] + width // 5, cy)
    window, texts = scroll_list.state(False)
    x, y = offsets(texts)
    if x <= 0 or y != 0:
        raise LaneError("a horizontal drag must move x only: %r" % scroll_list.label(texts, "x "))
    if scroll_list.on_screen(texts, frame, "card 1") and texts["card 1"][2] > window[0] + 8:
        raise LaneError("card 1 is still in view after a horizontal drag: %s" % (texts["card 1"],))
    if scroll_list.label(texts, "pressed ") != "pressed none":
        raise LaneError("a drag pressed a card: %r" % scroll_list.label(texts, "pressed "))
    visible = sorted((t for t in texts if t.startswith("card ") and texts[t][0] >= window[0] and texts[t][2] <= window[2]), key=lambda t: texts[t][0])
    if not visible:
        raise LaneError("no card fully in view after the drag; texts %s" % sorted(texts))
    target = visible[0]
    scroll_list.tap(texts, target)
    window, texts = scroll_list.state(False)
    if "pressed " + target not in texts:
        raise LaneError("tap on %r after a horizontal drag hit %r" % (target, scroll_list.label(texts, "pressed ")))
    print("NEON_ANDROID matrix-horizontal %s %s" % (scroll_list.label(texts, "x "), scroll_list.label(texts, "pressed ")))
    scroll_list.report("matrix-horizontal", window, texts, launched)

    scroll_list.tap(texts, "toggle axis")
    window, texts = wait_for("axis vertical", 10)
    if "pressed " + target not in texts:
        raise LaneError("the axis change lost app state: %r" % scroll_list.label(texts, "pressed "))
    if "card 1" not in texts or "card 2" not in texts or texts["card 2"][1] <= texts["card 1"][1] or texts["card 2"][0] != texts["card 1"][0]:
        raise LaneError("vertical cards must stack: %s %s" % (texts.get("card 1"), texts.get("card 2")))
    scroll_list.report("matrix-vertical", window, texts, launched)

    height = window[3] - window[1]
    cx = (window[0] + window[2]) // 2
    drag(cx, window[1] + height * 4 // 5, cx, window[1] + height // 3)
    window, texts = scroll_list.state(False)
    x, y = offsets(texts)
    if y <= 0:
        raise LaneError("a vertical drag after the axis change did not move y: %r" % scroll_list.label(texts, "x "))
    for _ in range(6):
        drag(cx, window[1] + height // 2, cx, window[1] + height * 5 // 6, 300)
        window, texts = scroll_list.state(False)
        if offsets(texts)[1] == 0:
            break
    if offsets(texts)[1] != 0:
        raise LaneError("could not return to the top: %r" % scroll_list.label(texts, "x "))
    top = texts["card 1"][1]
    drag(cx, top + 20, cx, top + height // 2, 900)
    window, texts = wait_for("refreshed 1", 10)
    print("NEON_ANDROID matrix-refreshed %s" % scroll_list.label(texts, "refreshed "))
    scroll_list.report("matrix-refreshed", window, texts, launched)

    scroll_list.tap(texts, "toggle axis")
    window, texts = wait_for("axis horizontal", 10)
    if "refreshed 1" not in texts or "pressed " + target not in texts:
        raise LaneError("switching back lost state: %s" % sorted(texts))
    if texts["card 2"][1] != texts["card 1"][1]:
        raise LaneError("cards did not return to one row: %s %s" % (texts["card 1"], texts["card 2"]))
    if counter.pid() != launched:
        raise LaneError("the process restarted during the matrix")
    scroll_list.report("matrix-horizontal-again", window, texts, launched)


def main():
    mode = adb("shell", "cmd", "window", "user-rotation").strip()
    try:
        lane()
    except EmulatorError as covered:
        print("FAIL: android scrollmatrix " + str(covered), file=sys.stderr)
        return EMULATOR
    except LaneError as failure:
        print("FAIL: android scrollmatrix " + str(failure), file=sys.stderr)
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
