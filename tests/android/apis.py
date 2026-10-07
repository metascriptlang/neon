import os
import re
import subprocess
import sys
import time

sys.dont_write_bytecode = True
import counter
import list as scroll_list
from counter import adb, LaneError, EmulatorError, EMULATOR

PACKAGE = "dev.neon.NeonApis"


def wait_for(text, seconds=10):
    deadline = time.time() + seconds
    texts = {}
    while time.time() < deadline:
        try:
            window, texts = scroll_list.state(False)
        except LaneError:
            time.sleep(0.5)
            continue
        if any(t == text or t.startswith(text) for t in texts):
            return window, texts
        time.sleep(0.4)
    raise LaneError("%r never appeared; texts %s" % (text, sorted(texts)))


def raw_nodes():
    adb("shell", "uiautomator", "dump", "/sdcard/neon-lane.xml")
    xml = adb("shell", "cat", "/sdcard/neon-lane.xml")
    return re.findall(r'<node [^>]*?text="([^"]*)"[^>]*?class="([^"]*)"[^>]*?package="([^"]*)"[^>]*?bounds="([^"]*)"', xml)


def tap_node(text, seconds=10):
    deadline = time.time() + seconds
    while time.time() < deadline:
        for found, cls, package, b in raw_nodes():
            if found.lower() == text.lower():
                x1, y1, x2, y2 = counter.bounds(b)
                adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
                return package
        time.sleep(0.5)
    raise LaneError("no node %r on screen" % text)


def foreground():
    return counter.focus()


def wait_foreground(predicate, what, seconds=10):
    deadline = time.time() + seconds
    current = ""
    while time.time() < deadline:
        current = foreground()
        if predicate(current):
            return current
        time.sleep(0.4)
    raise LaneError("%s never took focus; focus is %r" % (what, current))


def back_out_of_other_app(what, presses=4):
    for _ in range(presses):
        adb("shell", "input", "keyevent", "KEYCODE_BACK")
        try:
            return wait_foreground(ours, what, 4)
        except LaneError:
            pass
    return wait_foreground(ours, what, 4)


def screencap(name):
    with open(os.path.join(counter.results, "screenshots", "apis-" + name + ".png"), "wb") as out:
        out.write(subprocess.run(["adb", "exec-out", "screencap", "-p"], capture_output=True).stdout)


def ours(window):
    return window.startswith(PACKAGE + "/")


def shot(name, launched):
    window, texts = scroll_list.state(False)
    scroll_list.report("apis-" + name, window, texts, launched)
    print("NEON_ANDROID apis-%s %s" % (name, " | ".join(sorted(t for t in texts if " " in t))))
    return window, texts


def lane():
    counter.PACKAGE = PACKAGE
    scroll_list.PACKAGE = PACKAGE
    os.makedirs(os.path.join(counter.results, "screenshots"), exist_ok=True)
    scroll_list.launch(PACKAGE)
    counter.rotate(0)
    window, texts = wait_for("Neon APIs", 30)
    launched = counter.pid()
    sdk = adb("shell", "getprop", "ro.build.version.sdk").strip()
    if "os android v" + sdk + " pad no" not in texts:
        raise LaneError("Platform readout: %s" % scroll_list.label(texts, "os "))
    density = int(adb("shell", "wm", "density").split()[-1]) / 160.0
    ratio = scroll_list.label(texts, "ratio ")
    if not ratio.startswith("ratio " + str(round(density, 2)).rstrip("0").rstrip(".") + " "):
        raise LaneError("PixelRatio %r against wm density %s" % (ratio, density))
    if not scroll_list.label(texts, "window ").startswith("window ") or "screen 0x0" in texts:
        raise LaneError("Dimensions readout: %s" % sorted(texts))
    window, texts = wait_for("url none can https yes")
    if "state active" not in texts or "reader off keyboard hidden" not in texts:
        raise LaneError("initial AppState/AccessibilityInfo: %s" % sorted(texts))
    shot("initial", launched)

    scroll_list.tap(texts, "show alert")
    time.sleep(1)
    screencap("alert-dialog")
    tap_node("Confirm")
    window, texts = wait_for("alert confirm")
    scroll_list.tap(texts, "show alert")
    time.sleep(1)
    tap_node("Cancel")
    window, texts = wait_for("alert cancel")
    shot("alert", launched)

    scroll_list.tap(texts, "copy")
    time.sleep(1)
    window, texts = scroll_list.state(False)
    scroll_list.tap(texts, "paste")
    window, texts = wait_for("pasted neon-1")
    clip = adb("shell", "dumpsys", "clipboard", check=False)
    print("NEON_ANDROID apis-clipboard dumpsys has %s" % ("neon-1" in clip))
    shot("clipboard", launched)

    scroll_list.tap(texts, "vibrate")
    window, texts = wait_for("vibrated 1")
    vibrations = [line.strip()[:200] for line in adb("shell", "dumpsys", "vibrator_manager", check=False).splitlines() if PACKAGE in line]
    print("NEON_ANDROID apis-vibrate %d vibrator records for the package: %s" % (len(vibrations), vibrations[:2]))
    if not vibrations:
        raise LaneError("the vibrator service has no record of %s" % PACKAGE)

    tap_node("type here")
    window, texts = wait_for("reader off keyboard shown")
    scroll_list.tap(texts, "dismiss")
    window, texts = wait_for("reader off keyboard hidden")
    scroll_list.tap(texts, "announce")
    shot("keyboard", launched)

    window, texts = scroll_list.state(False)
    scroll_list.tap(texts, "share")
    chooser = wait_foreground(lambda w: not ours(w) and w != "", "the share chooser")
    activities = adb("shell", "dumpsys", "activity", "activities")
    resolver = [line.strip()[:160] for line in activities.splitlines() if "Chooser" in line or "Resolver" in line][:3]
    print("NEON_ANDROID apis-share focus=%r resolver=%s" % (chooser, resolver))
    screencap("share-chooser")
    adb("shell", "input", "keyevent", "KEYCODE_BACK")
    wait_foreground(ours, "the app after the chooser")
    window, texts = wait_for("share sharedAction")

    scroll_list.tap(texts, "open url")
    opened = wait_foreground(lambda w: not ours(w) and w != "", "the tel: handler")
    print("NEON_ANDROID apis-url focus=%r" % opened)
    screencap("url-handler")
    back_out_of_other_app("the app after the tel: handler")
    window, texts = wait_for("url opened")
    shot("intents", launched)

    history = scroll_list.label(texts, "state ")
    adb("shell", "input", "keyevent", "KEYCODE_HOME")
    wait_foreground(lambda w: not ours(w), "the launcher")
    time.sleep(1)
    adb("shell", "monkey", "-p", PACKAGE, "-c", "android.intent.category.LAUNCHER", "1")
    wait_foreground(ours, "the resumed app")
    window, texts = wait_for(history + ">background>active")
    if counter.pid() != launched:
        raise LaneError("Home + resume restarted the process")
    shot("appstate-home", launched)

    adb("shell", "input", "keyevent", "KEYCODE_BACK")
    window, texts = wait_for("back presses 1")
    if not ours(foreground()):
        raise LaneError("the consumed back press left the app: %r" % foreground())
    shot("back-consumed", launched)
    history = scroll_list.label(texts, "state ")
    adb("logcat", "-c", "-b", "events")
    adb("shell", "input", "keyevent", "KEYCODE_BACK")
    wait_foreground(lambda w: not ours(w), "the default back")
    time.sleep(1)
    finished = any("wm_finish_activity" in line and PACKAGE in line for line in adb("logcat", "-d", "-b", "events").splitlines())
    adb("shell", "monkey", "-p", PACKAGE, "-c", "android.intent.category.LAUNCHER", "1")
    wait_foreground(ours, "the app after the default back")
    window, texts = wait_for("back presses ")
    after = scroll_list.label(texts, "state ")
    presses = scroll_list.label(texts, "back presses ")
    print("NEON_ANDROID apis-back-default pid=%s launched=%s activity %s %r state=%r" % (counter.pid(), launched, "finished" if finished else "moved back", presses, after))
    if counter.pid() != launched:
        raise LaneError("the default back killed the process: %s -> %s" % (launched, counter.pid()))
    if finished and presses != "back presses 0":
        raise LaneError("the platform finished the activity, so the relaunch must mount the app afresh: %r %r" % (presses, after))
    if not finished and (presses != "back presses 2" or not after.startswith(history + ">background>active")):
        raise LaneError("the task moved back, so the app must keep its state: %r %r after %r" % (presses, after, history))
    shot("back-default", launched)


def main():
    mode = adb("shell", "cmd", "window", "user-rotation").strip()
    try:
        lane()
    except EmulatorError as covered:
        print("FAIL: android apis " + str(covered), file=sys.stderr)
        return EMULATOR
    except LaneError as failure:
        print("FAIL: android apis " + str(failure), file=sys.stderr)
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
