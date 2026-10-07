import html
import os
import re
import subprocess
import time

import counter
from counter import adb, LaneError

NODE = re.compile(r"<node ([^>]*?)/?>")
ATTR = re.compile(r"""([\w-]+)=(?:"([^"]*)"|'([^']*)')""")


class Node:
    def __init__(self, attrs):
        self.text = html.unescape(attrs.get("text", ""))
        self.desc = html.unescape(attrs.get("content-desc", ""))
        self.cls = attrs.get("class", "")
        self.checked = attrs.get("checked") == "true"
        self.focused = attrs.get("focused") == "true"
        self.clickable = attrs.get("clickable") == "true"
        self.bounds = counter.bounds(attrs.get("bounds", "[0,0][0,0]"))

    def center(self):
        x1, y1, x2, y2 = self.bounds
        return (x1 + x2) // 2, (y1 + y2) // 2

    def height(self):
        return self.bounds[3] - self.bounds[1]

    def __repr__(self):
        return "%s(%r,%r)@%s" % (self.cls.split(".")[-1], self.text, self.desc, self.bounds)


def nodes(package):
    adb("shell", "uiautomator", "dump", "/sdcard/neon-apps.xml")
    xml = adb("shell", "cat", "/sdcard/neon-apps.xml")
    out = []
    for raw in NODE.findall(xml):
        attrs = {name: double or single for name, double, single in ATTR.findall(raw)}
        if attrs.get("package") != package:
            continue
        out.append(Node(attrs))
    return out


def find(all_nodes, text=None, desc=None, cls=None):
    for n in all_nodes:
        if text is not None and n.text != text:
            continue
        if desc is not None and n.desc != desc:
            continue
        if cls is not None and not n.cls.endswith(cls):
            continue
        return n
    return None


def texts(all_nodes):
    return [n.text for n in all_nodes if n.text]


def wait_for(package, predicate, what, timeout=20):
    deadline = time.time() + timeout
    last = []
    while time.time() < deadline:
        try:
            last = nodes(package)
        except LaneError:
            time.sleep(0.5)
            continue
        if predicate(last):
            return last
        time.sleep(0.5)
    raise LaneError("timed out waiting for %s; texts %s" % (what, texts(last)[:40]))


def tap(node):
    x, y = node.center()
    adb("shell", "input", "tap", str(x), str(y))


def type_text(value):
    adb("shell", "input", "text", value.replace(" ", "%s"))


def clear_field(node, length):
    tap(node)
    time.sleep(0.3)
    adb("shell", "input", "keyevent", "KEYCODE_MOVE_END")
    adb("shell", "input", "keyevent", *(["KEYCODE_DEL"] * length))


def keyboard_shown():
    out = adb("shell", "dumpsys", "input_method", check=False)
    return "mInputShown=true" in out or "isInputViewShown=true" in out


def hide_keyboard():
    if keyboard_shown():
        adb("shell", "input", "keyevent", "KEYCODE_BACK")
        time.sleep(0.5)


def shot(name):
    png = subprocess.run(["adb", "exec-out", "screencap", "-p"], capture_output=True)
    path = os.path.join(counter.results, "screenshots", name + ".png")
    with open(path, "wb") as out:
        out.write(png.stdout)
    print("NEON_ANDROID shot %s" % path)
    return path


def launch(package):
    adb("shell", "am", "force-stop", package)
    adb("shell", "monkey", "-p", package, "-c", "android.intent.category.LAUNCHER", "1")
