import html
import os
import re
import subprocess
import sys
import time

sys.dont_write_bytecode = True
import counter
import list as scroll_list
from counter import adb, LaneError, EmulatorError, EMULATOR

PACKAGE = "dev.neon.NeonControls"


def nodes():
    for attempt in range(3):
        try:
            adb("shell", "uiautomator", "dump", "/sdcard/neon-lane.xml")
            break
        except LaneError:
            if attempt == 2:
                raise
            time.sleep(1)
    xml = adb("shell", "cat", "/sdcard/neon-lane.xml")
    found = []
    for node in re.findall(r"<node [^>]*>", xml):
        attrs = {k: html.unescape(d or q) for k, d, q in re.findall(r"""([a-z-]+)=(?:"([^"]*)"|'([^']*)')""", node)}
        found.append(attrs)
    return found


def find(name, seconds=10, cls=None):
    deadline = time.time() + seconds
    while time.time() < deadline:
        for n in nodes():
            if (n.get("text") == name or n.get("content-desc") == name) and (cls is None or n.get("class") == cls):
                return n
        time.sleep(0.4)
    raise LaneError("no node %r on screen" % name)


def center(n):
    x1, y1, x2, y2 = counter.bounds(n["bounds"])
    return (x1 + x2) // 2, (y1 + y2) // 2


def tap(name, seconds=10, cls=None):
    x, y = center(find(name, seconds, cls))
    adb("shell", "input", "tap", str(x), str(y))


def texts():
    return [n.get("text", "") for n in nodes() if n.get("package") == PACKAGE]


def label(prefix):
    for t in texts():
        if t.startswith(prefix):
            return t
    return ""


def wait_label(prefix, part, seconds=10):
    deadline = time.time() + seconds
    current = ""
    while time.time() < deadline:
        current = label(prefix)
        if part in current:
            return current
        time.sleep(0.4)
    raise LaneError("expected %s... to contain %r; it reads %r" % (prefix, part, current))


def reveal(name, swipes=6):
    size = adb("shell", "wm", "size").split()[-1].split("x")
    w, h = int(size[0]), int(size[1])
    for _ in range(swipes):
        for n in nodes():
            if (n.get("text") == name or n.get("content-desc") == name) and counter.bounds(n["bounds"])[3] < h * 3 // 4:
                return n
        adb("shell", "input", "swipe", str(w // 2), str(h * 3 // 4), str(w // 2), str(h // 3), "500")
        time.sleep(0.8)
    return find(name, 2)


def shot(name):
    with open(os.path.join(counter.results, "screenshots", "controls-" + name + ".png"), "wb") as out:
        out.write(subprocess.run(["adb", "exec-out", "screencap", "-p"], capture_output=True).stdout)
    print("NEON_ANDROID controls-%s %s" % (name, " | ".join(t for t in texts() if " " in t)[:600]))


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
    find("Neon booking", 30)
    wait_label("status ", "status idle")
    shot("start")

    date = find("Check-in date")
    x, y = center(date)
    adb("shell", "input", "tap", str(x), str(y))
    tap("24", 10)
    tap("OK", 5)
    wait_label("check-in ", "2026-10-24")
    shot("date")

    reveal("Guests")
    slider = find("Guests", cls="android.widget.SeekBar")
    x1, y1, x2, y2 = counter.bounds(slider["bounds"])
    mid = (y1 + y2) // 2
    thumb_at_two_of_one_to_eight = x1 + (x2 - x1) // 7
    adb("shell", "input", "swipe", str(thumb_at_two_of_one_to_eight), str(mid), str(x1 + (x2 - x1) * 6 // 10), str(mid), "600")
    wait_label("guests ", "guests ")
    print("NEON_ANDROID controls-slider %s" % label("guests "))
    if label("guests ") == "guests 2":
        raise LaneError("the slider drag did not change the guests")

    room = reveal("Room type")
    x, y = center(room)
    adb("shell", "input", "tap", str(x), str(y))
    tap("Suite", 5)
    wait_label("room ", "room Suite")

    tap_target = reveal("Business")
    x, y = center(tap_target)
    adb("shell", "input", "tap", str(x), str(y))
    wait_label("trip ", "trip Business")

    x, y = center(reveal("Breakfast"))
    adb("shell", "input", "tap", str(x), str(y))
    wait_label("extras ", "extras breakfast")
    box = find("Breakfast")
    print("NEON_ANDROID controls-checkbox checkable=%s checked=%s" % (box.get("checkable"), box.get("checked")))

    x, y = center(reveal("Cash"))
    adb("shell", "input", "tap", str(x), str(y))
    wait_label("payment ", "payment cash")

    x, y = center(reveal("Sea view"))
    adb("shell", "input", "tap", str(x), str(y))
    wait_label("prefs ", "prefs Sea view")
    shot("filled")

    x, y = center(reveal("Details"))
    adb("shell", "input", "tap", str(x), str(y))
    wait_label("details ", "details Suite")
    shot("bottom-sheet")
    tap("Close")
    time.sleep(1)

    x, y = center(reveal("Book"))
    adb("shell", "input", "tap", str(x), str(y))
    find("Confirm booking", 5)
    shot("dialog")
    tap("Confirm")
    with open(os.path.join(counter.results, "screenshots", "controls-booking.png"), "wb") as out:
        out.write(subprocess.run(["adb", "exec-out", "screencap", "-p"], capture_output=True).stdout)
    started = time.time()
    wait_label("status ", "status booked", 10)
    print("NEON_ANDROID controls-booking the first dump after Confirm took %.1f s: uiautomator waits for idle while the spinner animates, so 'status booking' is a screenshot here, not a dump" % (time.time() - started))
    shot("snackbar")
    tap("Undo")
    wait_label("status ", "status cancelled")
    find("Booking cancelled", 5)
    shot("toast")


def main():
    mode = adb("shell", "cmd", "window", "user-rotation").strip()
    try:
        lane()
    except EmulatorError as covered:
        print("FAIL: android controls " + str(covered), file=sys.stderr)
        return EMULATOR
    except LaneError as failure:
        print("FAIL: android controls " + str(failure), file=sys.stderr)
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
