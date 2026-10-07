import os
import re
import sys
import time

sys.dont_write_bytecode = True
import counter
import list as scroll_list
from counter import adb, LaneError, EmulatorError, EMULATOR

PACKAGE = "dev.neon.NeonMedia"


def status(texts):
    return scroll_list.label(texts, "status ")


def wait_status(prefix, why, seconds=15):
    deadline = time.time() + seconds
    texts = {}
    while time.time() < deadline:
        window, texts = scroll_list.state(False)
        if status(texts).startswith(prefix):
            return window, texts
        time.sleep(0.3)
    raise LaneError("%s: expected %r, app says %r" % (why, prefix, status(texts)))


# counter.dump keeps TextView nodes only; the WebView exposes the page's <button> as an
# android.widget.Button, so page content is read from every node with a text.
def page_texts():
    window, texts = scroll_list.state(False)
    xml = adb("shell", "cat", "/sdcard/neon-lane.xml")
    for attrs in re.findall(r"<node ([^>]*?)/?>", xml):
        fields = dict(re.findall(r'([\w-]+)="([^"]*)"', attrs))
        if fields.get("package") == PACKAGE and fields.get("text"):
            texts.setdefault(fields["text"], counter.bounds(fields["bounds"]))
    return window, texts


def centre_of(texts, text):
    x1, y1, x2, y2 = texts[text]
    return ((x1 + x2) // 2, (y1 + y2) // 2)


def wait_for(text, seconds=15):
    deadline = time.time() + seconds
    texts = {}
    while time.time() < deadline:
        window, texts = page_texts()
        if text in texts:
            return window, texts
        time.sleep(0.3)
    raise LaneError("%r never appeared; texts %s" % (text, sorted(texts)))


def report(name, window, texts, launched):
    scroll_list.report("media-" + name, window, texts, launched)
    print("NEON_ANDROID media-%s %s" % (name, status(texts)))


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
    window, texts = wait_status("status page ready", "the local html page posts to the app on load", 30)
    launched = counter.pid()
    window, texts = wait_for("Send to app", 15)
    scroll_list.tap(texts, "Send to app")
    window, texts = wait_status("status hello from the page", "a tap in the page reaches onMessage")
    scroll_list.tap(texts, "send to page")
    window, texts = wait_status("status page got hello from the app", "postMessage reaches the page, which answers")
    wait_for("got hello from the app", 5)
    scroll_list.tap(texts, "inject")
    window, texts = wait_status("status title Neon bridge", "injectJavaScript runs in the page")
    report("bridge", window, texts, launched)

    scroll_list.tap(texts, "browser")
    window, texts = wait_status("status loaded https://example.com/", "an https page loads", 40)
    if "first page" not in texts:
        raise LaneError("canGoBack before any navigation")
    report("browser-first", window, texts, launched)
    scroll_list.tap(texts, "next site")
    window, texts = wait_status("status loaded https://example.org/", "a page navigation loads the next site", 40)
    window, texts = wait_for("can go back", 5)
    scroll_list.tap(texts, "back")
    window, texts = wait_status("status loaded https://example.com/", "goBack returns to the first site", 40)
    scroll_list.tap(texts, "forward")
    window, texts = wait_status("status loaded https://example.org/", "goForward goes to the next site again", 40)
    report("browser-forward", window, texts, launched)

    scroll_list.tap(texts, "video")
    window, texts = wait_status("status video 3s 160x90", "the bundled clip loads with its duration and natural size")
    # Progress events keep the accessibility tree busy, so a dump during playback waits for
    # the clip's end. Play and pause run on the device a second apart, and the paused
    # screen is read.
    button = centre_of(texts, "play")
    adb("shell", "input tap %d %d; sleep 1; input tap %d %d" % (button + button))
    window, texts = wait_status("status paused", "play, then pause a second later")
    played = float(scroll_list.label(texts, "time ")[5:] or "0")
    if not (0.2 < played < 2.5):
        raise LaneError("progress should stop about a second in: time %s" % played)
    report("video-playing", window, texts, launched)
    seek = centre_of(texts, "seek 2")
    adb("shell", "input tap %d %d; input tap %d %d" % (seek + button))
    window, texts = wait_status("status video ended", "after a seek to 2 s the clip plays to its end")
    ended = float(scroll_list.label(texts, "time ")[5:] or "0")
    if ended < 2.5:
        raise LaneError("the clip ended at time %s, before its 3 s" % ended)
    if counter.pid() != launched:
        raise LaneError("the process restarted")
    report("video-ended", window, texts, launched)


def main():
    mode = adb("shell", "cmd", "window", "user-rotation").strip()
    try:
        lane()
    except EmulatorError as covered:
        print("FAIL: android media " + str(covered), file=sys.stderr)
        return EMULATOR
    except LaneError as failure:
        print("FAIL: android media " + str(failure), file=sys.stderr)
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
