import re
import sys
import time

sys.dont_write_bytecode = True
import counter
import apps
from apps import find, texts, wait_for, tap
from counter import adb, LaneError, EmulatorError, EMULATOR

PACKAGE = "dev.neon.NeonSettings"


def starting(ns, prefix):
    for n in ns:
        if n.text.startswith(prefix):
            return n.text
    return ""


def wait_text(prefix, contains, what):
    return wait_for(PACKAGE, lambda ns: contains in starting(ns, prefix), what)


def accessibility_tree(ns):
    rows = []
    for n in ns:
        if n.desc or n.cls.endswith(("Switch", "Button", "EditText")):
            rows.append("%s desc=%r text=%r checked=%s" % (n.cls.split(".")[-1], n.desc, n.text, n.checked))
    return rows


def lane():
    counter.PACKAGE = PACKAGE
    apps.launch(PACKAGE)
    counter.rotate(0)
    ns = wait_for(PACKAGE, lambda ns: find(ns, text="Settings") is not None and find(ns, desc="Name") is not None, "the settings screen")
    launched = counter.pid()
    print("NEON_ANDROID settings-start %s" % (starting(ns, "Compact") or starting(ns, "Wide")))
    for row in accessibility_tree(ns):
        print("NEON_ANDROID settings-a11y %s" % row)
    if find(ns, desc="Use system theme", cls="Switch") is None:
        raise LaneError("the theme switch is not exposed as a labelled Switch")
    if find(ns, desc="Save profile", cls="Button") is None:
        raise LaneError("the save button is not exposed as a labelled Button")
    apps.shot("settings-start")

    tap(find(ns, desc="Name"))
    ns = wait_text("Focus:", "Focus: name", "focus on the name field")
    time.sleep(1)
    ns = apps.nodes(PACKAGE)
    print("NEON_ANDROID settings-focus %s" % starting(ns, "Focus:"))
    apps.shot("settings-name-focused")
    adb("shell", "input", "keyevent", "KEYCODE_MOVE_END")
    apps.type_text(" King")
    adb("shell", "input", "keyevent", "KEYCODE_ENTER")
    ns = wait_text("Focus:", "Focus: email", "return key moving focus to email")
    print("NEON_ANDROID settings-next %s" % starting(ns, "Focus:"))
    adb("shell", "input", "keyevent", "KEYCODE_ENTER")
    ns = wait_for(PACKAGE, lambda ns: find(ns, text="Saved Ada Lovelace King <ada@example.com>") is not None, "the saved profile")
    ns = wait_text("Focus:", "Focus: none", "focus cleared after submit")
    time.sleep(1)
    ns = apps.nodes(PACKAGE)
    print("NEON_ANDROID settings-saved %s" % starting(ns, "Focus:"))
    apps.shot("settings-saved")

    tap(find(ns, desc="Use system theme"))
    ns = wait_for(PACKAGE, lambda ns: find(ns, desc="Dark mode") is not None, "the manual dark-mode row")
    tap(find(ns, desc="Dark mode"))
    ns = wait_text("Compact", "dark theme", "the dark theme")
    if not find(ns, desc="Dark mode").checked:
        raise LaneError("dark mode switch is not checked")
    apps.shot("settings-dark")
    print("NEON_ANDROID settings-dark %s" % starting(ns, "Compact"))
    tap(find(ns, desc="Large text"))
    time.sleep(1)
    apps.shot("settings-large-text")
    ns = apps.nodes(PACKAGE)
    tap(find(ns, desc="Large text"))
    tap(find(apps.nodes(PACKAGE), desc="Use system theme"))
    ns = wait_for(PACKAGE, lambda ns: find(ns, desc="Dark mode") is None, "following the system again")

    night = adb("shell", "cmd", "uimode", "night").strip()
    flip = "no" if "yes" in night else "yes"
    try:
        adb("shell", "cmd", "uimode", "night", flip)
        want = "system dark" if flip == "yes" else "system light"
        ns = wait_text("Compact", want, "the system theme change")
        time.sleep(1)
        apps.shot("settings-system-" + flip)
        print("NEON_ANDROID settings-system %s" % starting(ns, "Compact"))
    finally:
        adb("shell", "cmd", "uimode", "night", "yes" if "yes" in night else "no")

    counter.rotate(1)
    ns = wait_for(PACKAGE, lambda ns: starting(ns, "Wide") != "", "the wide layout in landscape")
    name = find(ns, desc="Name")
    theme = find(ns, desc="Use system theme")
    if name is None or theme is None or not (theme.bounds[0] > name.bounds[2]):
        raise LaneError("landscape did not place the sections side by side: %s %s" % (name, theme))
    time.sleep(1)
    apps.shot("settings-landscape")
    print("NEON_ANDROID settings-landscape %s" % starting(ns, "Wide"))
    counter.rotate(0)
    wait_for(PACKAGE, lambda ns: starting(ns, "Compact") != "", "the compact layout again")
    if counter.pid() != launched:
        raise LaneError("the app restarted during the lane")


def main():
    mode = adb("shell", "cmd", "window", "user-rotation").strip()
    try:
        lane()
    except EmulatorError as covered:
        print("FAIL: android settings " + str(covered), file=sys.stderr)
        return EMULATOR
    except LaneError as failure:
        print("FAIL: android settings " + str(failure), file=sys.stderr)
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
