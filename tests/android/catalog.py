import sys
import time

sys.dont_write_bytecode = True
import counter
import apps
from apps import find, texts, wait_for, tap
from counter import adb, LaneError, EmulatorError, EMULATOR

PACKAGE = "dev.neon.NeonCatalog"


def count_label(n):
    return "%d product%s" % (n, "" if n == 1 else "s")


def lane():
    counter.PACKAGE = PACKAGE
    apps.launch(PACKAGE)
    counter.rotate(0)
    loading = wait_for(PACKAGE, lambda ns: find(ns, text="Catalog") is not None, "the catalog header")
    if find(loading, text="Loading products") is not None:
        apps.shot("catalog-loading")
        print("NEON_ANDROID catalog-loading seen")
    ns = wait_for(PACKAGE, lambda ns: find(ns, text=count_label(12)) is not None, "12 products")
    launched = counter.pid()
    time.sleep(2.5)
    ns = apps.nodes(PACKAGE)
    short = find(ns, text="Dot grid, 120 pages.")
    long = find(ns, text="Oiled walnut tray with a felt base that keeps pens, keys and a phone in one place on a crowded desk.")
    if short is None or long is None:
        raise LaneError("rows did not mount their descriptions; nodes %s" % [n for n in ns if n.text])
    if long.height() < 2 * short.height() - 4:
        raise LaneError("the long description did not wrap: %s vs %s" % (long, short))
    images = [n for n in ns if n.desc in ("Field notebook", "Walnut desk tray") and n.cls.endswith("ImageView")]
    print("NEON_ANDROID catalog-list rows ok short=%dpx long=%dpx images=%d" % (short.height(), long.height(), len(images)))
    apps.shot("catalog-list")

    search = find(ns, desc="Search products")
    if search is None:
        raise LaneError("no search field; nodes %s" % ns[:20])
    tap(search)
    time.sleep(0.5)
    if not apps.keyboard_shown():
        print("NEON_ANDROID catalog-search keyboard not reported shown")
    apps.type_text("mug")
    ns = wait_for(PACKAGE, lambda ns: find(ns, text=count_label(1)) is not None and find(ns, text="Ceramic mug") is not None, "the search result")
    if find(ns, text="Brass pen") is not None:
        raise LaneError("search kept a non-matching row")
    apps.shot("catalog-search")
    print("NEON_ANDROID catalog-search mug -> 1 product")

    apps.type_text("zzz")
    ns = wait_for(PACKAGE, lambda ns: find(ns, text='No products match "mugzzz"') is not None, "the empty state")
    apps.shot("catalog-empty")
    print("NEON_ANDROID catalog-empty ok")

    apps.clear_field(find(ns, desc="Search products"), 6)
    ns = wait_for(PACKAGE, lambda ns: find(ns, text=count_label(12)) is not None, "the full list again")
    apps.hide_keyboard()

    offline = find(apps.nodes(PACKAGE), desc="Simulate offline")
    if offline is None:
        raise LaneError("no offline switch")
    tap(offline)
    ns = wait_for(PACKAGE, lambda ns: find(ns, text="Could not reach the catalog. Check the connection and try again.") is not None, "the error state")
    if not find(ns, desc="Simulate offline").checked:
        raise LaneError("the switch did not stay on")
    apps.shot("catalog-error")
    print("NEON_ANDROID catalog-error ok")
    tap(find(ns, desc="Simulate offline"))
    time.sleep(0.3)
    ns = apps.nodes(PACKAGE)
    retry = find(ns, text="RETRY")
    if retry is not None:
        tap(retry)
    ns = wait_for(PACKAGE, lambda ns: find(ns, text=count_label(12)) is not None, "the list after retry")
    print("NEON_ANDROID catalog-retry ok")

    row = find(ns, desc="Ceramic mug, $18")
    if row is None:
        adb("shell", "input", "swipe", "500", "1600", "500", "900", "400")
        ns = wait_for(PACKAGE, lambda ns: find(ns, desc="Ceramic mug, $18") is not None, "the mug row")
        row = find(ns, desc="Ceramic mug, $18")
    tap(row)
    ns = wait_for(PACKAGE, lambda ns: find(ns, text="EDIT") is not None, "the detail screen")
    if find(ns, text="Ceramic mug") is None or find(ns, text="$18") is None:
        raise LaneError("detail lacks title or price; texts %s" % texts(ns))
    time.sleep(2)
    apps.shot("catalog-detail")
    print("NEON_ANDROID catalog-detail ok")

    tap(find(ns, text="EDIT"))
    ns = wait_for(PACKAGE, lambda ns: find(ns, text="Edit product") is not None, "the edit form")
    apps.clear_field(find(ns, desc="Title"), 20)
    ns = apps.nodes(PACKAGE)
    apps.hide_keyboard()
    tap(find(apps.nodes(PACKAGE), text="SAVE"))
    ns = wait_for(PACKAGE, lambda ns: find(ns, text="Title is required.") is not None, "the validation error")
    apps.shot("catalog-invalid")
    print("NEON_ANDROID catalog-validation ok")

    tap(find(ns, desc="Title"))
    apps.type_text("Clay cup")
    apps.clear_field(find(apps.nodes(PACKAGE), desc="Price"), 6)
    apps.type_text("21")
    apps.hide_keyboard()
    tap(find(apps.nodes(PACKAGE), text="SAVE"))
    saving = apps.nodes(PACKAGE)
    if find(saving, text="SAVING") is not None:
        apps.shot("catalog-saving")
        print("NEON_ANDROID catalog-saving seen")
    ns = wait_for(PACKAGE, lambda ns: find(ns, text="EDIT") is not None and find(ns, text="Clay cup") is not None, "the saved detail")
    if find(ns, text="$21") is None:
        raise LaneError("the saved price is not shown; texts %s" % texts(ns))
    apps.shot("catalog-saved")
    print("NEON_ANDROID catalog-saved ok")

    tap(find(ns, desc="Back to catalog"))
    ns = wait_for(PACKAGE, lambda ns: find(ns, desc="Clay cup, $21") is not None or find(ns, text="Clay cup") is not None, "the edited row in the list")
    apps.shot("catalog-list-after-save")
    if counter.pid() != launched:
        raise LaneError("the app restarted during the lane")
    print("NEON_ANDROID catalog-list-after-save ok")


def main():
    mode = adb("shell", "cmd", "window", "user-rotation").strip()
    try:
        lane()
    except EmulatorError as covered:
        print("FAIL: android catalog " + str(covered), file=sys.stderr)
        return EMULATOR
    except LaneError as failure:
        print("FAIL: android catalog " + str(failure), file=sys.stderr)
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
