// A Counter in a macOS Ion window under `msc run --hcr`: an edit of counter.ms reloads into the running window.
//   cd examples/macosNative/hcr && msc run --hcr app.ms
// It clicks the counter three times once mounted and once after each reload, so a kept count reads 4 after the first edit.

import { reload, lastReload, reloadKindName, ReloadKind } from "std/hcr";
import { runNativeWindow, nativeWindowOptions } from "../../../src/platform/macos/ion";
import { Counter } from "./counter";
import { harnessClick } from "../harness.h";
import { exit } from "std/process";

when (macos) {
	@compile("../harness.m", "-fobjc-arc");
}

let events = 0;

function click(): void { harnessClick("Neon HCR on Ion", 100, 50); }

function poll(): void {
	const kind = reload();
	if (kind != ReloadKind.NoChange && kind != ReloadKind.Pending) {
		events += 1;
		const r = lastReload();
		console.log(`HCR event${events} ${reloadKindName(kind)} [${r.modules.join(",")}] ${r.reason}`);
		setTimeout(click, 500);
	}
	setTimeout(poll, 50);
}

exit(runNativeWindow(nativeWindowOptions("Neon HCR on Ion", 400, 200), Counter, (): void => {
	console.log("HCR ready");
	setTimeout(click, 500);
	setTimeout(click, 1000);
	setTimeout(click, 1500);
	setTimeout(poll, 50);
}));
