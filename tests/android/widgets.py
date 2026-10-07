import os
import re
import sys
import time

sys.dont_write_bytecode = True
import counter
import list as scroll_list
from counter import adb, LaneError, EmulatorError, EMULATOR

PACKAGE = "dev.neon.NeonWidgets"


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


def middle_x(texts, text):
    return (texts[text][0] + texts[text][2]) // 2


def middle_y(texts, text):
    return (texts[text][1] + texts[text][3]) // 2


def swipe(x1, y1, x2, y2, ms):
    adb("shell", "input", "swipe", str(x1), str(y1), str(x2), str(y2), str(ms))


def report(name, window, texts, launched):
    scroll_list.report("widgets-" + name, window, texts, launched)
    print("NEON_ANDROID widgets-%s %s" % (name, status(texts)))


def require_awake():
    power = adb("shell", "dumpsys", "power", check=False)
    awake = re.search(r"mWakefulness=(\w+)", power)
    locked = re.search(r"isKeyguardShowing=(\w+)", adb("shell", "dumpsys", "window", check=False))
    state = "%s keyguard=%s" % (awake.group(1) if awake else "?", locked.group(1) if locked else "?")
    if (awake and awake.group(1) != "Awake") or (locked and locked.group(1) == "true"):
        raise EmulatorError("the device is %s; not a Neon failure, unlock it and rerun" % state)


def lane():
    require_awake()
    counter.PACKAGE = PACKAGE
    scroll_list.PACKAGE = PACKAGE
    os.makedirs(os.path.join(counter.results, "screenshots"), exist_ok=True)
    scroll_list.launch(PACKAGE)
    counter.rotate(0)
    window, texts = wait_for("Welcome", 30)
    launched = counter.pid()
    width = window[2] - window[0]
    centre = window[0] + width // 2
    report("onboarding", window, texts, launched)

    y = middle_y(texts, "Welcome")
    swipe(window[0] + width * 8 // 10, y, window[0] + width * 15 // 100, y, 250)
    window, texts = wait_status("status page 2", "a left swipe turns the onboarding page")
    time.sleep(1)
    window, texts = wait_for("Sync", 5)
    if abs(middle_x(texts, "Sync") - centre) > 8:
        raise LaneError("the second page did not settle centred: %s vs %s" % (middle_x(texts, "Sync"), centre))
    report("page-2", window, texts, launched)
    scroll_list.tap(texts, "next")
    window, texts = wait_status("status page 3", "next turns to the last page")

    scroll_list.tap(texts, "tabs")
    window, texts = wait_for("Chats 3", 10)
    y = middle_y(texts, "Chats 3")
    swipe(window[0] + width * 85 // 100, y, window[0] + width // 10, y, 250)
    window, texts = wait_status("status tab Status", "a swipe changes to the Status tab")
    window, texts = wait_for("Status 1", 5)
    report("tab-status", window, texts, launched)
    scroll_list.tap(texts, "Calls")
    window, texts = wait_status("status tab Calls", "a tab press selects Calls")
    time.sleep(1)
    window, texts = wait_for("Calls 6", 5)
    top = texts["Calls 1"][1]
    y = middle_y(texts, "Calls 6")
    swipe(centre, y, centre, y - 300, 500)
    time.sleep(1.5)
    window, texts = scroll_list.state(False)
    if "Calls 1" in texts and texts["Calls 1"][1] > top - 20:
        raise LaneError("a vertical drag did not scroll the scene inside the pager: %s -> %s" % (top, texts["Calls 1"]))
    if status(texts) != "status tab Calls":
        raise LaneError("the vertical drag changed the tab: %r" % status(texts))
    report("tab-calls", window, texts, launched)

    scroll_list.tap(texts, "carousel")
    window, texts = wait_for("Slide A", 10)
    window, texts = wait_status("status slide Slide B", "auto-play moves to Slide B", 8)
    scroll_list.tap(texts, "pause")
    window, texts = wait_status("status autoplay off", "pause stops auto-play")
    y = middle_y(texts, "Slide B")
    swipe(window[0] + width * 8 // 10, y, window[0] + width * 2 // 10, y, 250)
    window, texts = wait_status("status slide Slide C", "a swipe moves to Slide C")
    report("carousel", window, texts, launched)

    scroll_list.tap(texts, "faq")
    window, texts = wait_for("Which platforms?", 10)
    scroll_list.tap(texts, "Which platforms?")
    window, texts = wait_status("status faq open 1", "a question opens")
    window, texts = wait_for("iOS, Android, the browser and the terminal.", 5)
    report("faq", window, texts, launched)

    scroll_list.tap(texts, "table")
    window, texts = wait_for("Calories", 10)
    scroll_list.tap(texts, "Calories")
    window, texts = wait_status("status sorted calories up", "a header press sorts by calories")
    time.sleep(0.5)
    window, texts = scroll_list.state(False)
    if texts["Frozen yogurt"][1] >= texts["Gingerbread"][1]:
        raise LaneError("ascending calories puts Frozen yogurt first")
    if abs(middle_y(texts, "Eclair") - middle_y(texts, "262")) > 3:
        raise LaneError("the Eclair row does not line up across columns")
    scroll_list.tap(texts, "Eclair")
    window, texts = wait_status("status selected Eclair", "a row press selects it")
    report("table", window, texts, launched)

    scroll_list.tap(texts, "chips")
    window, texts = wait_for("Flexbox", 10)
    if texts["Flexbox"][1] <= texts["Neon"][1] + 20:
        raise LaneError("the chips did not wrap onto more rows")
    scroll_list.tap(texts, "Yoga")
    window, texts = wait_status("status chips Neon|Yoga", "a chip press selects it")
    if counter.pid() != launched:
        raise LaneError("the process restarted")
    report("chips", window, texts, launched)


def main():
    mode = adb("shell", "cmd", "window", "user-rotation").strip()
    try:
        lane()
    except EmulatorError as covered:
        print("FAIL: android widgets " + str(covered), file=sys.stderr)
        return EMULATOR
    except LaneError as failure:
        print("FAIL: android widgets " + str(failure), file=sys.stderr)
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
