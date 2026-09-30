import os
import re
import subprocess
import sys
import time

sys.dont_write_bytecode = True
import counter
from counter import EmulatorError, LaneError, adb, dump, focus, pid, snapshot

HUMAN = 300
ROTATION = ["accelerometer_rotation", "user_rotation"]


def prop(name):
    return adb("shell", "getprop", name).strip()


def touchscreen():
    device = None
    for line in adb("shell", "getevent", "-pl").splitlines():
        match = re.match(r"add device \d+: (\S+)", line)
        if match:
            device = match.group(1)
        elif device and "ABS_MT_POSITION_X" in line:
            return device
    raise LaneError("no input device reports ABS_MT_POSITION_X")


def touches(log):
    with open(log, errors="replace") as events:
        return [line.strip() for line in events if "BTN_TOUCH" in line or "ABS_MT_POSITION" in line]


def wait_for(what, ready):
    print("NEON_DEVICE waiting for the person to " + what, flush=True)
    deadline = time.time() + HUMAN
    while time.time() < deadline:
        state = ready()
        if state:
            return state
        time.sleep(1)
    raise LaneError("gave up after %ds waiting for the person to %s" % (HUMAN, what))


def showing(value):
    def ready():
        state = dump()
        return state if state and value in [t for t, _ in state[1]] else None
    return ready


def oriented(landscape):
    def ready():
        state = dump()
        return state if state and (state[0][2] > state[0][3]) == landscape else None
    return ready


def in_front():
    return focus().startswith(counter.PACKAGE + "/")


def press(name, value, parity, expected, log):
    before = len(touches(log))
    wait_for("tap + until the counter shows " + value, showing(value))
    snapshot(name, False, expected, value, parity)
    events = touches(log)[before:]
    downs = [e for e in events if "BTN_TOUCH" in e and "DOWN" in e]
    print("NEON_DEVICE %s touchscreen events=%d BTN_TOUCH DOWN=%d first=%s" % (name, len(events), len(downs), events[:4]))
    if not downs:
        raise LaneError("%s: the counter reached %s with no BTN_TOUCH DOWN on the touchscreen" % (name, value))


def procedure(log):
    adb("shell", "am", "force-stop", counter.PACKAGE)
    adb("shell", "am", "start", "-W", "-n", counter.ACTIVITY)
    wait_for("hold the phone upright", oriented(False))
    launched = pid()
    if not launched:
        raise LaneError("the counter did not start")
    snapshot("device-initial", False, launched, "0", "even")
    press("device-pressed-1", "1", "odd", launched, log)
    press("device-pressed-2", "2", "even", launched, log)
    wait_for("turn the phone to landscape", oriented(True))
    snapshot("device-landscape", True, launched, "2", "even")
    wait_for("press home", lambda: not in_front())
    wait_for("reopen Neon Counter from the launcher", in_front)
    window, _ = wait_for("leave the app on screen", dump)
    snapshot("device-foreground-returned", window[2] > window[3], launched, "2", "even")


def restore(saved):
    for key, value in saved.items():
        if value == "null":
            adb("shell", "settings", "delete", "system", key)
        else:
            adb("shell", "settings", "put", "system", key, value)
    now = {key: adb("shell", "settings", "get", "system", key).strip() for key in ROTATION}
    print("NEON_DEVICE rotation saved=%s restored=%s" % (saved, now))
    if now != saved:
        raise LaneError("rotation settings not restored: %s -> %s" % (saved, now))


def main():
    serial = os.environ.get("ANDROID_SERIAL", "")
    if len(sys.argv) != 2 or not serial or serial.startswith("emulator-"):
        print("usage: ANDROID_SERIAL=<physical device> python3 tests/android/device.py <results>; an emulator has no finger", file=sys.stderr)
        return 1
    counter.results = sys.argv[1]
    os.makedirs(os.path.join(counter.results, "screenshots"), exist_ok=True)
    print("NEON_DEVICE serial=%s model=%s android=%s api=%s abi=%s page=%s" % (
        serial, prop("ro.product.model"), prop("ro.build.version.release"), prop("ro.build.version.sdk"),
        prop("ro.product.cpu.abi"), adb("shell", "getconf", "PAGE_SIZE").strip()))
    saved = {key: adb("shell", "settings", "get", "system", key).strip() for key in ROTATION}
    log = os.path.join(counter.results, "getevent.log")
    status = 0
    with open(log, "w") as out:
        screen = touchscreen()
        print("NEON_DEVICE touchscreen=" + screen)
        reader = subprocess.Popen(["adb", "shell", "-tt", "getevent", "-lt", screen], stdout=out, stderr=subprocess.STDOUT)
        try:
            adb("shell", "settings", "put", "system", "accelerometer_rotation", "1")
            procedure(log)
        except (LaneError, EmulatorError) as failure:
            print("FAIL: device " + str(failure), file=sys.stderr)
            status = 1
        finally:
            reader.terminate()
            reader.wait()
            adb("shell", "rm", "-f", "/sdcard/neon-lane.xml", check=False)
            restore(saved)
    return status


if __name__ == "__main__":
    sys.exit(main())
