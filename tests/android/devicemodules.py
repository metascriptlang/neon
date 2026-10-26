import os
import re
import subprocess
import sys
import time

sys.dont_write_bytecode = True
import counter
import controls
from counter import adb, LaneError, EmulatorError, EMULATOR

PACKAGE = "dev.neon.NeonDevice"
ALLOW_LOCATION = ["While using the app", "Only this time", "Allow only while using the app", "Allow"]
ALLOW_NOTIFICATIONS = ["Allow"]


def shot(name):
    with open(os.path.join(counter.results, "screenshots", "devicemodules-" + name + ".png"), "wb") as out:
        out.write(subprocess.run(["adb", "exec-out", "screencap", "-p"], capture_output=True).stdout)
    print("NEON_ANDROID devicemodules-%s %s" % (name, " | ".join(t for t in controls.texts() if " " in t)[:600]))


def launch():
    adb("shell", "monkey", "-p", PACKAGE, "-c", "android.intent.category.LAUNCHER", "1")
    controls.find("Neon Device", 30)
    return counter.pid()


def allow(choices, what):
    deadline = time.time() + 15
    while time.time() < deadline:
        for n in controls.nodes():
            if n.get("package") != PACKAGE and n.get("text") in choices:
                shot("dialog-" + what)
                x, y = controls.center(n)
                adb("shell", "input", "tap", str(x), str(y))
                return
        time.sleep(0.5)
    raise LaneError("no system dialog offering %s for %s" % (choices, what))


def press(name):
    x, y = controls.center(controls.reveal(name))
    adb("shell", "input", "tap", str(x), str(y))


def wait_match(prefix, pattern, seconds):
    deadline = time.time() + seconds
    current = ""
    while time.time() < deadline:
        current = controls.label(prefix)
        if re.search(pattern, current):
            return current
        time.sleep(0.5)
    raise LaneError("expected %s... to match %r; it reads %r" % (prefix, pattern, current))


def device_locale():
    tag = adb("shell", "getprop", "persist.sys.locale").strip() or adb("shell", "getprop", "ro.product.locale").strip()
    zone = adb("shell", "getprop", "persist.sys.timezone").strip()
    hours = adb("shell", "settings", "get", "system", "time_12_24").strip()
    return tag, zone, hours


def read_locale():
    shown = controls.wait_label("locale ", "tz ")
    match = re.match(r"^locale (\S+) tz (\S+) 24h (\S+) rtl (yes|no)$", shown)
    if not match:
        raise LaneError("locale line is malformed: %r" % shown)
    print("NEON_ANDROID devicemodules-locale %s" % shown)
    return match.groups()


def subtags(tag):
    parts = tag.replace("_", "-").lower().split("-")
    return parts[0], parts[-1] if len(parts) > 1 else ""


def check_locale():
    shown_tag, shown_zone, shown_hours, _ = read_locale()
    device_tag, device_zone, device_hours = device_locale()
    if subtags(shown_tag) != subtags(device_tag):
        raise LaneError("locale tag %r differs from the device %r" % (shown_tag, device_tag))
    if device_zone and shown_zone != device_zone:
        raise LaneError("timezone %r differs from the device %r" % (shown_zone, device_zone))
    if device_hours in ("12", "24") and shown_hours != ("yes" if device_hours == "24" else "no"):
        raise LaneError("24h %r differs from time_12_24 %r" % (shown_hours, device_hours))
    if not device_zone or device_hours not in ("12", "24"):
        print("NEON_ANDROID devicemodules-locale SKIP partial compare: persist.sys.timezone=%r time_12_24=%r" % (device_zone, device_hours))


def check_app_rtl():
    sdk = int(adb("shell", "getprop", "ro.build.version.sdk").strip())
    if sdk < 33:
        print("NEON_ANDROID devicemodules-rtl SKIP sdk %d has no per-app locale (needs 33)" % sdk)
        return
    try:
        adb("shell", "cmd", "locale", "set-app-locales", PACKAGE, "--user", "0", "--locales", "ar-EG")
        adb("shell", "am", "force-stop", PACKAGE)
        launch()
        tag, _, _, rtl = read_locale()
        if rtl != "yes" or subtags(tag)[0] != "ar":
            raise LaneError("per-app ar-EG gave tag %r rtl %r, expected an ar tag and rtl yes" % (tag, rtl))
    finally:
        adb("shell", "cmd", "locale", "set-app-locales", PACKAGE, "--user", "0", "--locales", "", check=False)
        adb("shell", "am", "force-stop", PACKAGE)
        launch()
    tag, _, _, rtl = read_locale()
    if subtags(tag)[0] == "ar" and subtags(device_locale()[0])[0] != "ar":
        raise LaneError("per-app locale not restored: tag %r rtl %r" % (tag, rtl))


def lane():
    controls.require_awake()
    counter.PACKAGE = PACKAGE
    controls.PACKAGE = PACKAGE
    os.makedirs(os.path.join(counter.results, "screenshots"), exist_ok=True)
    adb("shell", "pm", "clear", PACKAGE)
    counter.rotate(0)
    first = launch()
    controls.wait_label("stored ", "stored none")
    controls.wait_label("network ", "connected yes")
    controls.wait_label("permission ", "permission undetermined")
    model = adb("shell", "getprop", "ro.product.model").strip()
    release = adb("shell", "getprop", "ro.build.version.release").strip()
    emulated = "yes" if adb("shell", "getprop", "ro.kernel.qemu").strip() == "1" else "no"
    controls.wait_label("device ", "device %s Android %s emulator %s" % (model, release, emulated))
    controls.wait_label("app ", "app " + PACKAGE + " ")
    shot("initial")
    check_locale()
    check_app_rtl()

    press("save note")
    controls.wait_label("stored ", "stored note-1")
    press("save note")
    controls.wait_label("stored ", "stored note-2")
    press("merge note")
    controls.wait_label("merged ", '"tags":{"a":1,"b":2}')
    adb("shell", "am", "force-stop", PACKAGE)
    second = launch()
    if second == first:
        raise LaneError("the relaunch kept pid %s" % first)
    controls.wait_label("stored ", "stored note-2")
    controls.wait_label("merged ", '"b":2')
    shot("relaunched")

    press("request location")
    allow(ALLOW_LOCATION, "location")
    controls.wait_label("permission ", "permission granted")
    press("locate")
    position = wait_match("position ", r"^position (-?\d+(\.\d+)?,-?\d+(\.\d+)?|error \d)", 45)
    print("NEON_ANDROID devicemodules-position %s" % position)
    if "error" in position:
        raise LaneError("getCurrentPosition failed: " + position)
    press("watch location")
    if emulated == "yes":
        for latitude in ("37.425", "37.428"):
            time.sleep(2)
            adb("emu", "geo", "fix", "-122.084", latitude)
    wait_match("watched ", r"^watched [1-9]", 90)
    shot("located")

    press("haptic")
    controls.wait_label("haptics ", "haptics 1")
    press("battery")
    print("NEON_ANDROID devicemodules-battery %s" % wait_match("battery ", r"^battery (0|1)(\.\d+)?$", 10))

    press("allow notifications")
    if int(adb("shell", "getprop", "ro.build.version.sdk").strip()) >= 33:
        allow(ALLOW_NOTIFICATIONS, "notifications")
    controls.wait_label("notifications ", "notifications granted")
    press("notify")
    controls.wait_label("notified ", "notified received Neon reminder", 15)
    shot("notification-foreground")

    press("dismiss notifications")
    press("notify later")
    controls.wait_label("notified ", "notified scheduled")
    adb("shell", "input", "keyevent", "KEYCODE_HOME")
    deadline = time.time() + 10
    while counter.pid() and time.time() < deadline:
        adb("shell", "am", "kill", PACKAGE)
        time.sleep(1)
    if counter.pid():
        raise LaneError("am kill left the backgrounded app alive for 10 s")
    adb("shell", "cmd", "statusbar", "expand-notifications")
    deadline = time.time() + 120
    shade = None
    while time.time() < deadline and shade is None:
        shade = next((n for n in controls.nodes() if n.get("text") == "Neon later"), None)
        time.sleep(1)
    if shade is None:
        raise LaneError("the alarm never posted 'Neon later' for the killed app")
    shot("notification-shade")
    x, y = controls.center(shade)
    adb("shell", "input", "tap", str(x), str(y))
    controls.find("Neon Device", 30)
    controls.wait_label("notified ", "notified launched by Neon later", 15)
    shot("notification-launched")

    press("dismiss notifications")
    press("notify later")
    controls.wait_label("notified ", "notified scheduled")
    adb("shell", "input", "keyevent", "KEYCODE_HOME")
    alive = counter.pid()
    adb("shell", "cmd", "statusbar", "expand-notifications")
    deadline = time.time() + 60
    shade = None
    while time.time() < deadline and shade is None:
        shade = next((n for n in controls.nodes() if n.get("text") == "Neon later"), None)
        time.sleep(1)
    if shade is None:
        raise LaneError("the alarm never posted 'Neon later' for the backgrounded app")
    x, y = controls.center(shade)
    adb("shell", "input", "tap", str(x), str(y))
    controls.find("Neon Device", 30)
    controls.wait_label("notified ", "notified response Neon later", 15)
    if counter.pid() != alive:
        raise LaneError("a tap on the notification of a live app started a new process")
    shot("notification-live-response")

    adb("shell", "am", "start", "-n", PACKAGE + "/dev.metascript.app.MainActivity", "-d", "neondevice://live")
    controls.wait_label("url ", "url neondevice://live", 15)
    if counter.pid() != alive:
        raise LaneError("a url intent to the live app started a new process")
    shot("url-live")
    press("clear notes")
    controls.wait_label("stored ", "stored none")


def main():
    mode = adb("shell", "cmd", "window", "user-rotation").strip()
    try:
        lane()
    except EmulatorError as covered:
        print("FAIL: android devicemodules " + str(covered), file=sys.stderr)
        return EMULATOR
    except LaneError as failure:
        print("FAIL: android devicemodules " + str(failure), file=sys.stderr)
        return 1
    finally:
        adb("shell", "cmd", "statusbar", "collapse", check=False)
        if mode.startswith("lock"):
            adb("shell", "cmd", "window", "user-rotation", *mode.split())
        else:
            adb("shell", "cmd", "window", "user-rotation", "free")
    return 0


if __name__ == "__main__":
    counter.results = sys.argv[1]
    sys.exit(main())
