import json
import math
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
import counter
from counter import adb, bounds, LaneError, EmulatorError, EMULATOR

PACKAGE = "dev.neon.NeonMeasurement"
ACTIVITY = PACKAGE + "/dev.metascript.app.MainActivity"


def require(condition, message):
    if not condition:
        raise LaneError(message)


def density(output):
    values = re.findall(r"(?:Physical|Override) density:\s*(\d+)", output)
    require(bool(values), "wm density has no physical/override density: " + output)
    return int(values[-1]) / 160.0


def window_frame(output):
    sections = re.split(r"(?=^\s*Window #\d+ Window\{)", output, flags=re.MULTILINE)
    for section in sections:
        lines = section.lstrip().splitlines()
        header = lines[0] if lines else ""
        if PACKAGE + "/" not in header:
            continue
        match = re.search(r"\bmFrame=(\[[^\n]+?\]\[[^\n]+?\])", section)
        if not match:
            match = re.search(r"\bframe=(\[[^\n]+?\]\[[^\n]+?\])", section)
        require(match is not None, "app window has no frame in dumpsys window windows")
        return bounds(match.group(1))
    raise LaneError("app window absent from dumpsys window windows")


def rect(text, prefix):
    require(text.startswith(prefix + " "), "missing result " + prefix + ": " + text)
    try:
        result = tuple(float(v) for v in text[len(prefix) + 1:].split(","))
    except ValueError as error:
        raise LaneError("invalid rectangle: " + text) from error
    require(len(result) == 4 and all(math.isfinite(v) for v in result), "invalid rectangle: " + text)
    return result


def close(actual, expected, tolerance, name):
    require(len(actual) == len(expected) and all(abs(a - b) <= tolerance for a, b in zip(actual, expected)),
            "%s: %r != %r (tolerance %s)" % (name, actual, expected, tolerance))


def screen_rect(measured, scale, origin):
    x, y, width, height = measured
    return (x * scale + origin[0], y * scale + origin[1],
            (x + width) * scale + origin[0], (y + height) * scale + origin[1])


def oracle(measured, native, root, scale, origin, name):
    require(native[0] > root[0] + 2 and native[1] > root[1] + 2
            and native[2] < root[2] - 2 and native[3] < root[3] - 2,
            name + ": native control is clipped or touches root edge")
    require(native[2] > native[0] and native[3] > native[1], name + ": empty AX control")
    close(screen_rect(measured, scale, origin), native, 2.0, name + " window dp -> AX screen px")


def self_test():
    scale = density("Physical density: 420\nOverride density: 320\n")
    require(scale == 2, "density override not applied")
    origin = window_frame("WINDOW MANAGER WINDOWS\n\n  Window #0 Window{abc u0 " + ACTIVITY + "}:\n    mFrame=[11,23][811,1423]\n")
    require(origin == (11, 23, 811, 1423), "window frame parser")
    modern = ("  Window #0 Window{system u0 StatusBar}:\n    mFrame=[0,0][900,30]\n\n"
              "  Window #1 Window{app u0 " + ACTIVITY + "}:\n"
              "    mWindowFrames: parent=[0,0][900,1500] display=[0,0][900,1500] frame=[11,23][811,1423]\n")
    require(window_frame(modern) == origin, "modern window frame selected wrong window/coordinate space")
    require(named([{"content-desc": "run"}, {"text": "run"}], "run") == {"content-desc": "run"},
            "action must prefer accessible control over child text")
    measured = (40, 70, 60, 30)
    native = (91, 163, 211, 223)
    root = (11, 63, 811, 1423)
    oracle(measured, native, root, scale, origin, "control")
    rejected = 0
    for wrong, ax, clip, d, o in [
        ((40, 70, 40, 20), native, root, scale, origin),  # logical, not transformed
        (measured, native, root, 1, origin),
        (measured, native, root, scale, (0, 0)),
        ((40, 110, 60, 30), native, root, scale, origin),  # omitted scroll
        (measured, native, (91, 63, 811, 1423), scale, origin),
    ]:
        try:
            oracle(wrong, ax, clip, d, o, "negative control")
        except LaneError:
            rejected += 1
    require(rejected == 5, "oracle accepted a corrupted geometry/density/origin/clipping control")
    print("NEON_ANDROID measurement self-test PASS 1 positive, 5 rejected controls")


def nodes(results, name):
    adb("shell", "uiautomator", "dump", "/sdcard/neon-measurement.xml")
    xml = adb("shell", "cat", "/sdcard/neon-measurement.xml")
    with open(os.path.join(results, name + ".xml"), "w") as out:
        out.write(xml)
    counter.cover(PACKAGE, xml)
    return [n.attrib for n in ET.fromstring(xml).iter("node") if n.get("package") == PACKAGE]


def named(items, name):
    found = [n for n in items if n.get("content-desc") == name]
    if not found:
        found = [n for n in items if n.get("text") == name]
    require(len(found) == 1, "expected one %r node, got %s" % (name, len(found)))
    return found[0]


def label(items, prefix):
    found = [n.get("text", "") for n in items if n.get("text", "").startswith(prefix + " ")]
    require(len(found) == 1, "expected one %r result, got %r" % (prefix, found))
    return found[0]


def wait(results, prefix, expected, name):
    deadline = time.monotonic() + 20
    last = []
    while time.monotonic() < deadline:
        last = nodes(results, name)
        texts = [n.get("text", "") for n in last]
        require(not any("FAIL" in text for text in texts), "fixture failure: " + repr(texts))
        if expected in texts:
            return last
        time.sleep(0.4)
    raise LaneError("timed out waiting for %s %r; texts %r" % (prefix, expected, [n.get("text", "") for n in last]))


def tap(items, name):
    require(counter.focus().startswith(PACKAGE + "/"), "measurement lost focus; no synthetic input sent")
    x1, y1, x2, y2 = bounds(named(items, name)["bounds"])
    require(x2 > x1 and y2 > y1, "empty action " + name)
    adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))


def snapshot(results, name):
    shot = subprocess.run(["adb", "exec-out", "screencap", "-p"], capture_output=True, check=True)
    with open(os.path.join(results, name + ".png"), "wb") as out:
        out.write(shot.stdout)


def lane(results):
    require(bool(os.environ.get("ANDROID_SERIAL")), "ANDROID_SERIAL required: the device the run is granted")
    serial = os.environ["ANDROID_SERIAL"]
    os.makedirs(results, exist_ok=True)
    power = adb("shell", "dumpsys", "power")
    if "mWakefulness=Awake" not in power:
        raise EmulatorError("device not awake; unlock it and keep the screen on")
    keyguard = adb("shell", "dumpsys", "window", "policy")
    if re.search(r"(?:isKeyguardShowing|isKeyguardShowingAndNotOccluded|isKeyguardShowingAndNotOccludedAndNotGoingAway)=true", keyguard):
        raise EmulatorError("device locked; unlock it and keep the screen on")
    adb("shell", "am", "force-stop", PACKAGE)
    launched = adb("shell", "am", "start", "-W", "-n", ACTIVITY)
    with open(os.path.join(results, "launch.txt"), "w") as out:
        out.write(launched)
    counter.PACKAGE = PACKAGE
    items = wait(results, "geometry", "geometry ready", "initial")
    process = counter.pid()
    require(bool(process), "measurement process absent")
    density_text = adb("shell", "wm", "density")
    windows = adb("shell", "dumpsys", "window", "windows")
    with open(os.path.join(results, "density.txt"), "w") as out:
        out.write(density_text)
    with open(os.path.join(results, "windows.txt"), "w") as out:
        out.write(windows)
    scale = density(density_text)
    origin = window_frame(windows)
    root = bounds(named(items, "measurement-root")["bounds"])
    require((root[2] - root[0]) / scale >= 330 and (root[3] - root[1]) / scale >= 700,
            "fixture requires visible portrait content >=330x700dp; got %r density %s" % (root, scale))
    tap(items, "Run measurement")
    items = wait(results, "geometry", "geometry PASS", "geometry")
    scaled = rect(label(items, "scaled"), "scaled")
    before = rect(label(items, "scroll"), "scroll")
    local = rect(label(items, "local"), "local")
    oracle(scaled, bounds(named(items, "measurement-scaled")["bounds"]), root, scale, origin, "scaled+rotated")
    oracle(before, bounds(named(items, "measurement-scroll")["bounds"]), root, scale, origin, "before scroll")
    close(local, (40, 35, 40, 20), 0.05, "logical ancestor excludes scale+rotation")
    close(scaled[2:], (30, 60), 2 / scale, "90deg rotation + 1.5 scale")
    require(label(items, "zero") == "zero PASS", "zero rectangle was not successful")
    snapshot(results, "geometry")
    tap(items, "Scroll measurement")
    items = wait(results, "geometry", "geometry SCROLLED", "scrolled")
    after = rect(label(items, "scroll"), "scroll")
    oracle(after, bounds(named(items, "measurement-scroll")["bounds"]), root, scale, origin, "after scroll")
    close((before[1] - after[1],), (40,), 1 / scale, "native scroll delta")
    close((before[0], before[2], before[3]), (after[0], after[2], after[3]), 1 / scale, "scroll preserves x/size")
    close(rect(label(items, "local"), "local"), (12, 60, 40, 20), 0.05, "logical scroll ancestor excludes scroll offset")
    snapshot(results, "scrolled")
    tap(items, "Dispose measurement")
    items = wait(results, "lifetime", "lifetime disposed after 2 answers", "disposed")
    require(not any(n.get("content-desc") == "measurement-temporary" for n in items), "temporary node survived disposal")
    tap(items, "Check disposed")
    items = wait(results, "lifetime", "lifetime PASS window-zeros layout-onFail", "lifetime")
    snapshot(results, "lifetime")
    require(counter.pid() == process, "measurement pid changed")
    require(density(adb("shell", "wm", "density")) == scale, "density drift during measurement")
    require(window_frame(adb("shell", "dumpsys", "window", "windows")) == origin, "window origin drift during measurement")
    require(bounds(named(items, "measurement-root")["bounds"]) == root, "content origin drift during measurement")
    evidence = {"serial": serial, "pid": process, "density": scale, "window_frame_screen_px": origin,
                "root_screen_px": root, "scaled_window_dp": scaled, "scroll_before_dp": before,
                "scroll_after_dp": after, "logical_scaled_dp": local,
                "status_controls": ["zero success", "hidden zeros", "nonancestor onFail",
                                    "two answers before disposal", "post-unmount zeros and onFail"]}
    with open(os.path.join(results, "geometry.json"), "w") as out:
        json.dump(evidence, out, indent=2)
    print("NEON_ANDROID measurement PASS " + json.dumps(evidence, sort_keys=True))


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        return 0
    try:
        require(len(sys.argv) == 2, "usage: measurement.py <existing-results-directory> | --self-test")
        lane(sys.argv[1])
    except EmulatorError as error:
        print("FAIL: android measurement " + str(error), file=sys.stderr)
        return EMULATOR
    except (LaneError, ET.ParseError, subprocess.CalledProcessError) as error:
        print("FAIL: android measurement " + str(error), file=sys.stderr)
        return 1
    finally:
        if os.environ.get("ANDROID_SERIAL"):
            adb("shell", "am", "force-stop", PACKAGE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
