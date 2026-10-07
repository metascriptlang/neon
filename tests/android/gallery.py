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
    window, texts = scroll_list.state(False)
    for _ in range(8):
        if "BUTTON" in texts:
            return window, texts
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
    parity(launched)


def described_bounds(description):
    adb("shell", "uiautomator", "dump", "/sdcard/neon-lane.xml")
    xml = adb("shell", "cat", "/sdcard/neon-lane.xml")
    for node in re.findall(r"<node [^>]*>", xml):
        if 'package="%s"' % PACKAGE in node and 'content-desc="%s"' % description in node:
            return counter.bounds(re.search(r'bounds="([^"]*)"', node).group(1))
    raise LaneError("no view described %r" % description)


def leading_number(text, prefix):
    digits = ""
    for c in text[len(prefix):]:
        if not c.isdigit():
            break
        digits += c
    return int(digits) if digits else -1


# The React Native parity screen (examples/components/gallery.ms ParityScreen).
def parity(launched):
    window, texts = scroll_list.state(False)
    window, texts = scroll_to("OPEN PARITY SCREEN", window)
    scroll_list.tap(texts, "OPEN PARITY SCREEN")
    window, texts = wait_for("status: parity screen")

    window, texts, line = wait_prefix("insets ")
    if leading_number(line, "insets ") != 0:
        raise LaneError("the root starts inside the safe area: %r" % line)
    window, texts = press(texts, "EDGE TO EDGE", "edge to edge")
    window, texts, line = wait_prefix("insets ")
    top = leading_number(line, "insets ")
    if top <= 0:
        raise LaneError("a translucent StatusBar publishes no top inset: %r" % line)
    header = texts["Neon gallery"]
    print("NEON_ANDROID gallery-parity-edge %s header %s" % (line, header))
    scroll_list.report("gallery-parity-edge", window, texts, launched)
    window, texts = press(texts, "INSIDE SAFE AREA", "inside safe area")

    window, texts = wait_for("Terms apply to this gallery.")
    x1, y1, x2, y2 = texts["Terms apply to this gallery."]
    adb("shell", "input", "tap", str(x1 + 20), str((y1 + y2) // 2))
    window, texts = wait_for("status: terms pressed")
    adb("shell", "input", "tap", str(x2 - 20), str((y1 + y2) // 2))
    window, texts = wait_for("status: text pressed")
    cx1, _, cx2, _ = texts["centred"]
    if cx2 - cx1 < (window[2] - window[0]) // 2:
        raise LaneError("a centred Text does not span its parent: %s" % (texts["centred"],))
    print("NEON_ANDROID gallery-parity-text spans press apart, centred width %d" % (cx2 - cx1))

    window, texts, line = wait_prefix("grow ")
    resting = leading_number(line, "grow ")
    x, y = editable_centre("Grows with its text")
    adb("shell", "input", "tap", str(x), str(y))
    time.sleep(1)
    for word in ["one", "two", "three"]:
        adb("shell", "input", "text", word)
        adb("shell", "input", "keyevent", "KEYCODE_ENTER")
    deadline = time.time() + 8
    grown = resting
    while time.time() < deadline and grown <= resting + 20:
        window, texts, line = wait_prefix("grow ")
        grown = leading_number(line, "grow ")
        time.sleep(0.4)
    if grown <= resting + 20:
        raise LaneError("the multiline TextInput did not grow: %d -> %d" % (resting, grown))
    print("NEON_ANDROID gallery-parity-grow %d -> %d" % (resting, grown))
    adb("shell", "input", "keyevent", "KEYCODE_BACK")

    window, texts = scroll_to("size 600x240", window)
    window, texts, line = wait_prefix("hairline ")
    print("NEON_ANDROID gallery-parity-image size 600x240 %s" % line)

    window, texts = scroll_to("OPEN DIALOG", window)
    sx1, sy1, sx2, sy2 = described_bounds("Slop target")
    adb("shell", "input", "tap", str(sx1 - (sx2 - sx1) // 2), str((sy1 + sy2) // 2))
    window, texts = wait_for("status: slop pressed")
    window, texts = press(texts, "OPEN DIALOG", "dialog open")
    window, texts = wait_for("Parity dialog")
    adb("shell", "input", "keyevent", "KEYCODE_BACK")
    window, texts = wait_for("status: dialog dismissed")
    window, texts = gone("Parity dialog")
    if counter.pid() != launched:
        raise LaneError("back closed the activity instead of the dialog")
    print("NEON_ANDROID gallery-parity-dialog back dismisses it")
    scroll_list.report("gallery-parity", window, texts, launched)


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
