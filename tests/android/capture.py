import os
import re
import subprocess
import sys
import time

sys.dont_write_bytecode = True
import counter
import controls
from counter import adb, LaneError, EmulatorError, EMULATOR

PACKAGE = "dev.neon.NeonCapture"
ALLOW = ["While using the app", "Only this time", "Allow only while using the app", "Allow"]
DENY = ["Don’t allow", "Don't allow", "Deny"]
SHUTTER = ["Shutter", "Take photo", "Capture", "Take picture", "Shutter button"]
CONFIRM = ["Done", "OK", "Save", "Confirm", "Use photo", "Accept"]


def shot(name):
    with open(os.path.join(counter.results, "screenshots", "capture-" + name + ".png"), "wb") as out:
        out.write(subprocess.run(["adb", "exec-out", "screencap", "-p"], capture_output=True).stdout)
    print("NEON_ANDROID capture-%s %s" % (name, controls.label("status ")))


def press(name):
    x, y = controls.center(controls.reveal(name))
    adb("shell", "input", "tap", str(x), str(y))


def tap_node(node):
    x, y = controls.center(node)
    adb("shell", "input", "tap", str(x), str(y))


def foreign(match, seconds, what):
    deadline = time.time() + seconds
    while time.time() < deadline:
        for n in controls.nodes():
            if n.get("package") != PACKAGE and match(n):
                return n
        time.sleep(0.5)
    raise LaneError("no %s outside the app" % what)


def answer(choices, what):
    node = foreign(lambda n: n.get("text") in choices, 15, "system dialog offering %s for %s" % (choices, what))
    shot("dialog-" + what)
    tap_node(node)


def status(prefix, seconds=15):
    return controls.wait_label("status ", "status " + prefix, seconds)


def launch():
    adb("shell", "monkey", "-p", PACKAGE, "-c", "android.intent.category.LAUNCHER", "1")
    controls.find("Neon capture", 30)


def lane():
    controls.require_awake()
    counter.PACKAGE = PACKAGE
    controls.PACKAGE = PACKAGE
    os.makedirs(os.path.join(counter.results, "screenshots"), exist_ok=True)
    adb("shell", "pm", "clear", PACKAGE)
    counter.rotate(0)
    launch()
    status("ready")

    press("pick photo")
    photo = foreign(lambda n: (n.get("content-desc") or "").startswith("Photo"), 30, "photo in the system picker")
    shot("photo-picker")
    tap_node(photo)
    status("picked image ", 30)
    shot("picked")

    press("camera")
    press("open camera")
    answer(DENY, "camera-deny")
    status("camera permission denied")
    shot("camera-denied")
    adb("shell", "pm", "grant", PACKAGE, "android.permission.CAMERA")
    press("open camera")
    status("camera ready back", 20)
    time.sleep(1)
    shot("camera-back")
    press("take picture")
    picture = controls.wait_label("status ", "status picture ", 20)
    if not re.match(r"^status picture \d+x\d+$", picture):
        raise LaneError("takePictureAsync answered %r" % picture)
    shot("picture")
    press("flip")
    status("camera ready front", 20)
    shot("camera-front")
    press("close")

    press("photos")
    press("system camera")
    shutter = foreign(lambda n: (n.get("content-desc") or n.get("text") or "") in SHUTTER, 30, "camera app shutter")
    shot("system-camera")
    tap_node(shutter)
    confirm = foreign(lambda n: (n.get("content-desc") or n.get("text") or "") in CONFIRM, 20, "camera app confirm button")
    tap_node(confirm)
    status("shot image ", 30)
    shot("system-camera-shot")

    press("audio")
    press("play clip")
    status("clip finished", 20)
    press("record")
    answer(ALLOW, "microphone")
    status("recording", 15)
    time.sleep(1.5)
    shot("recording")
    press("stop")
    status("recorded 500+ms", 15)
    press("play recording")
    status("recording finished", 20)
    shot("recording-finished")


def main():
    mode = adb("shell", "cmd", "window", "user-rotation").strip()
    try:
        lane()
    except EmulatorError as covered:
        print("FAIL: android capture " + str(covered), file=sys.stderr)
        return EMULATOR
    except LaneError as failure:
        print("FAIL: android capture " + str(failure), file=sys.stderr)
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
