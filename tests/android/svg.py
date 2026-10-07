import os
import re
import struct
import subprocess
import sys
import time
import zlib

sys.dont_write_bytecode = True
import counter
import list as scroll_list
from counter import adb, LaneError, EmulatorError, EMULATOR

PACKAGE = "dev.neon.NeonSvg"

# The <Svg> views of examples/components/svgGallery.ms and their size in dp.
SIZES = {
    "icon heart": 40, "icon check": 40, "donut chart": 140, "progress ring": 140,
    "line chart": 380, "logo": 200,
}


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


def require_awake():
    power = adb("shell", "dumpsys", "power", check=False)
    awake = re.search(r"mWakefulness=(\w+)", power)
    locked = re.search(r"isKeyguardShowing=(\w+)", adb("shell", "dumpsys", "window", check=False))
    state = "%s keyguard=%s" % (awake.group(1) if awake else "?", locked.group(1) if locked else "?")
    if (awake and awake.group(1) != "Awake") or (locked and locked.group(1) == "true"):
        raise EmulatorError("the device is %s; not a Neon failure, unlock it and rerun" % state)


def labelled_bounds():
    adb("shell", "uiautomator", "dump", "/sdcard/neon-lane.xml")
    xml = adb("shell", "cat", "/sdcard/neon-lane.xml")
    found = {}
    for desc, b in re.findall(r"<node [^>]*?content-desc=\"([^\"]+)\"[^>]*?bounds=\"([^\"]*)\"", xml):
        x1, y1, x2, y2 = [int(v) for v in re.findall(r"\d+", b)]
        found[desc] = (x1, y1, x2, y2)
    return found


def png_pixels(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise LaneError("screencap did not return a PNG")
    at = 8
    width = height = 0
    channels = 4
    raw = b""
    while at < len(data):
        length, kind = struct.unpack(">I4s", data[at:at + 8])
        chunk = data[at + 8:at + 8 + length]
        if kind == b"IHDR":
            width, height, depth, color = struct.unpack(">IIBB", chunk[:10])
            if depth != 8 or color not in (2, 6):
                raise LaneError("unsupported PNG depth %d colour %d" % (depth, color))
            channels = 4 if color == 6 else 3
        elif kind == b"IDAT":
            raw += chunk
        at += 12 + length
    rows = zlib.decompress(raw)
    stride = width * channels
    out = bytearray(height * stride)
    prev = bytearray(stride)
    pos = 0
    for y in range(height):
        kind = rows[pos]
        line = bytearray(rows[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = prev[i]
            c = prev[i - channels] if i >= channels else 0
            if kind == 1:
                line[i] = (line[i] + a) & 255
            elif kind == 2:
                line[i] = (line[i] + b) & 255
            elif kind == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return width, channels, out


def screen():
    shot = subprocess.run(["adb", "exec-out", "screencap", "-p"], capture_output=True)
    return shot.stdout


def expect(pixels, bounds, label, x, y, want, why, tolerance=40):
    width, channels, data = pixels
    x1, y1, x2, y2 = bounds[label]
    scale = (x2 - x1) / SIZES[label]
    px, py = int(x1 + x * scale), int(y1 + y * scale)
    at = (py * width + px) * channels
    got = list(data[at:at + 3])
    print("NEON_ANDROID svg-pixel %s (%s, %s) = %s want %s: %s" % (label, x, y, got, want, why))
    if any(abs(g - w) > tolerance for g, w in zip(got, want)):
        raise LaneError("%s: %s at (%s, %s) is %s, want %s" % (why, label, x, y, got, want))


def report(name, shot):
    with open(os.path.join(counter.results, "screenshots", "svg-" + name + ".png"), "wb") as out:
        out.write(shot)


def lane():
    require_awake()
    counter.PACKAGE = PACKAGE
    scroll_list.PACKAGE = PACKAGE
    os.makedirs(os.path.join(counter.results, "screenshots"), exist_ok=True)
    scroll_list.launch(PACKAGE)
    counter.rotate(0)
    window, texts = wait_status("status progress 0%", "the gallery starts", 30)
    launched = counter.pid()
    bounds = labelled_bounds()
    for label in SIZES:
        if label not in bounds:
            raise LaneError("no view labelled %r among %s" % (label, sorted(bounds)))
    shot = screen()
    report("start", shot)
    pixels = png_pixels(shot)
    white = [255, 255, 255]
    expect(pixels, bounds, "icon heart", 20, 20, [229, 57, 53], "the heart icon is red in its middle")
    expect(pixels, bounds, "icon heart", 2, 38, white, "and empty in its corner", 10)
    expect(pixels, bounds, "icon check", 11, 25, [67, 160, 71], "the check mark is green")
    expect(pixels, bounds, "donut chart", 120, 70, [229, 57, 53], "the first slice (40%) covers three o'clock")
    expect(pixels, bounds, "donut chart", 70, 120, [30, 136, 229], "the second slice covers six o'clock")
    expect(pixels, bounds, "donut chart", 20, 70, [67, 160, 71], "the third slice covers nine o'clock")
    expect(pixels, bounds, "donut chart", 55, 23, [251, 192, 45], "the fourth slice sits before twelve o'clock")
    expect(pixels, bounds, "donut chart", 70, 70, white, "the hole is empty", 10)
    expect(pixels, bounds, "progress ring", 70, 120, [224, 224, 224], "the ring track shows before the animation")
    expect(pixels, bounds, "line chart", 375, 116, [229, 241, 252], "the gradient area fades to a light blue", 25)
    expect(pixels, bounds, "line chart", 300, 20, white, "the sky above the line is white", 10)
    expect(pixels, bounds, "logo", 15, 30, [243, 104, 12], "the logo starts orange", 50)
    expect(pixels, bounds, "logo", 190, 30, [113, 31, 146], "and ends purple", 50)
    expect(pixels, bounds, "logo", 100, 28, white, "with white text in the middle", 30)

    scroll_list.tap(texts, "animate")
    wait_status("status progress 75%", "the Animated ring finishes")
    time.sleep(0.5)
    shot = screen()
    report("animated", shot)
    pixels = png_pixels(shot)
    expect(pixels, bounds, "progress ring", 70, 120, [142, 36, 170], "the Animated ring reaches six o'clock")
    expect(pixels, bounds, "progress ring", 35, 35, [224, 224, 224], "and stops short of the last quarter")
    expect(pixels, bounds, "progress ring", 70, 100, white, "inside the ring, below the label, stays clear", 10)
    if counter.pid() != launched:
        raise LaneError("the process restarted")


def main():
    mode = adb("shell", "cmd", "window", "user-rotation").strip()
    try:
        lane()
    except EmulatorError as covered:
        print("FAIL: android svg " + str(covered), file=sys.stderr)
        return EMULATOR
    except LaneError as failure:
        print("FAIL: android svg " + str(failure), file=sys.stderr)
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
