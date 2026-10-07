import os
import re
import sys
import time

sys.dont_write_bytecode = True
import counter
import list as scroll_list
from counter import adb, LaneError, EmulatorError, EMULATOR

PACKAGE = "dev.neon.NeonGallery"
LONG_PREFIX = "Neon clamps this paragraph"


def wait_for(text, seconds=10):
    deadline = time.time() + seconds
    texts = {}
    while time.time() < deadline:
        window, texts = scroll_list.state(False)
        if text in texts:
            return window, texts
        time.sleep(0.3)
    raise LaneError("%r never appeared; texts %s" % (text, sorted(texts)))


def wait_prefix(prefix, seconds=10):
    deadline = time.time() + seconds
    texts = {}
    while time.time() < deadline:
        window, texts = scroll_list.state(False)
        found = scroll_list.label(texts, prefix)
        if found:
            return window, texts, found
        time.sleep(0.3)
    raise LaneError("no text starting %r; texts %s" % (prefix, sorted(texts)))


def gone(text, seconds=10):
    deadline = time.time() + seconds
    texts = {}
    while time.time() < deadline:
        window, texts = scroll_list.state(False)
        if text not in texts:
            return window, texts
        time.sleep(0.3)
    raise LaneError("%r is still on screen" % text)


def status(texts):
    return scroll_list.label(texts, "status: ")


def drag(x1, y1, x2, y2, ms=500):
    adb("shell", "input", "swipe", str(x1), str(y1), str(x2), str(y2), str(ms))


def scroll_to(text, window):
    cx = (window[0] + window[2]) // 2
    height = window[3] - window[1]
    for _ in range(8):
        window, texts = scroll_list.state(False)
        if text in texts and texts[text][3] < window[3] - height // 6:
            return window, texts
        drag(cx, window[1] + height * 3 // 4, cx, window[1] + height * 2 // 5, 400)
    raise LaneError("could not scroll %r into view" % text)


def scroll_top(window):
    cx = (window[0] + window[2]) // 2
    height = window[3] - window[1]
    for _ in range(8):
        drag(cx, window[1] + height // 2, cx, window[1] + height * 5 // 6, 300)
        window, texts = scroll_list.state(False)
        if "BUTTON" in texts:
            return window, texts
    raise LaneError("could not return to the top")


def editable_centre(hint):
    adb("shell", "uiautomator", "dump", "/sdcard/neon-lane.xml")
    xml = adb("shell", "cat", "/sdcard/neon-lane.xml")
    for node in re.findall(r"<node [^>]*>", xml):
        if 'package="%s"' % PACKAGE not in node or "EditText" not in node:
            continue
        if hint not in node:
            continue
        x1, y1, x2, y2 = counter.bounds(re.search(r'bounds="([^"]*)"', node).group(1))
        return (x1 + x2) // 2, (y1 + y2) // 2
    raise LaneError("no text input %r" % hint)


def ime_shown():
    return "mInputShown=true" in adb("shell", "dumpsys", "input_method")


def status_bar_visible():
    for line in adb("shell", "dumpsys", "window").splitlines():
        match = re.search(r"InsetsSource id=\S+ type=statusBars frame=\S+ visible=(true|false)", line)
        if match and "mSource=" not in line:
            return match.group(1) == "true"
    raise LaneError("no status bar inset source in dumpsys window")


def press(texts, label, expect):
    scroll_list.tap(texts, label)
    return wait_for("status: " + expect)


def lane():
    counter.PACKAGE = PACKAGE
    scroll_list.PACKAGE = PACKAGE
    os.makedirs(os.path.join(counter.results, "screenshots"), exist_ok=True)
    scroll_list.launch(PACKAGE)
    counter.rotate(0)
    window, texts = wait_for("status: ready", 30)
    launched = counter.pid()
    scroll_list.report("gallery-initial", window, texts, launched)

    window, texts = press(texts, "PRESS ME", "button 1")
    window, texts = press(texts, "DISABLED", "button 1")
    window, texts = press(texts, "Touchable opacity", "opacity 2")
    window, texts = press(texts, "Touchable highlight", "highlight 3")
    window, texts = press(texts, "Touchable without feedback", "plain 4")
    print("NEON_ANDROID gallery-presses %s" % status(texts))

    window, texts = scroll_to("OPEN MODAL", window)
    scroll_list.tap(texts, "OPEN MODAL")
    window, texts = wait_for("Modal content")
    window, texts = wait_for("status: modal shown")
    scroll_list.report("gallery-modal", window, texts, launched)
    adb("shell", "input", "keyevent", "KEYCODE_BACK")
    window, texts = wait_for("status: modal closed by request")
    window, texts = gone("Modal content")
    if counter.pid() != launched:
        raise LaneError("back closed the activity instead of the modal")
    scroll_list.tap(texts, "OPEN MODAL")
    window, texts = wait_for("Modal content")
    scroll_list.tap(texts, "CLOSE MODAL")
    window, texts = wait_for("status: modal closed")
    print("NEON_ANDROID gallery-modal back and button both close it")

    window, texts = scroll_to("HIDE STATUS BAR", window)
    if not status_bar_visible():
        raise LaneError("the status bar starts hidden")
    scroll_list.tap(texts, "HIDE STATUS BAR")
    window, texts = wait_for("status: status bar hidden")
    time.sleep(1)
    if status_bar_visible():
        raise LaneError("StatusBar hidden did not hide the status bar")
    scroll_list.report("gallery-statusbar-hidden", window, texts, launched)
    window, texts = wait_for("SHOW STATUS BAR")
    scroll_list.tap(texts, "SHOW STATUS BAR")
    window, texts = wait_for("status: status bar shown")
    time.sleep(1)
    if not status_bar_visible():
        raise LaneError("StatusBar did not show the status bar again")
    print("NEON_ANDROID gallery-statusbar hidden and shown")

    window, texts = scroll_to("OPEN KEYBOARD SCREEN", window)
    scroll_list.tap(texts, "OPEN KEYBOARD SCREEN")
    window, texts = wait_for("keyboard hidden")
    window, texts, before = wait_prefix("message at ")
    resting = int(before.split()[-1])
    x, y = editable_centre("Message")
    adb("shell", "input", "tap", str(x), str(y))
    deadline = time.time() + 8
    lifted = resting
    while time.time() < deadline:
        window, texts = scroll_list.state(False)
        line = scroll_list.label(texts, "message at ")
        if line and ime_shown():
            lifted = int(line.split()[-1])
            if lifted < resting:
                break
        time.sleep(0.4)
    if lifted >= resting:
        raise LaneError("KeyboardAvoidingView did not lift the input: %d -> %d, keyboard %r" % (resting, lifted, scroll_list.label(texts, "keyboard ")))
    print("NEON_ANDROID gallery-keyboard input %d -> %d %s" % (resting, lifted, scroll_list.label(texts, "keyboard ")))
    scroll_list.report("gallery-keyboard", window, texts, launched)
    adb("shell", "input", "keyevent", "KEYCODE_BACK")
    time.sleep(1)
    window, texts = wait_for("BACK TO GALLERY")
    scroll_list.tap(texts, "BACK TO GALLERY")
    window, texts = wait_for("status: back")

    window, texts = scroll_top(window)
    top = texts["BUTTON"][1]
    cx = (window[0] + window[2]) // 2
    drag(cx, top + 10, cx, top + (window[3] - window[1]) // 2, 900)
    window, texts = wait_for("status: refreshed 1", 15)
    print("NEON_ANDROID gallery-refreshed")
    scroll_list.report("gallery-refreshed", window, texts, launched)

    long_text = None
    window, texts = scroll_to("TEXT", window)
    for _ in range(3):
        long_text = scroll_list.label(texts, LONG_PREFIX)
        if long_text:
            break
        window, texts = scroll_to("Over the image", window)
    if not long_text:
        raise LaneError("the clamped paragraph is not on screen: %s" % sorted(texts))
    one_line = texts["TEXT"][3] - texts["TEXT"][1]
    clamped = texts[long_text][3] - texts[long_text][1]
    if clamped > one_line * 3:
        raise LaneError("numberOfLines=2 still shows %dpx against a %dpx line" % (clamped, one_line))
    print("NEON_ANDROID gallery-text clamped %dpx (header line %dpx)" % (clamped, one_line))
    x, y = editable_centre("Notes")
    adb("shell", "input", "tap", str(x), str(y))
    time.sleep(1)
    adb("shell", "input", "text", "ab")
    adb("shell", "input", "keyevent", "KEYCODE_ENTER")
    adb("shell", "input", "text", "c")
    window, texts = wait_for("status: notes 4")
    scroll_list.report("gallery-notes", window, texts, launched)
    adb("shell", "input", "keyevent", "KEYCODE_BACK")
    if counter.pid() != launched:
        raise LaneError("the process restarted during the gallery")


def main():
    mode = adb("shell", "cmd", "window", "user-rotation").strip()
    try:
        lane()
    except EmulatorError as covered:
        print("FAIL: android gallery " + str(covered), file=sys.stderr)
        return EMULATOR
    except LaneError as failure:
        print("FAIL: android gallery " + str(failure), file=sys.stderr)
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
