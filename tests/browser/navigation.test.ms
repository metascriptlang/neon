import { domHost } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { sleepAsync } from "std/core/promise";
import { dispatchHardwareBackPress } from "../../src/api/backHandler";
import { NavigationContainerRef } from "../../src/navigation/index";
import { NavigationDemo, navigationRef } from "../../examples/components/navigation";

extern function js(code: cstring): string from "String((0, eval)(#))";

extern class HTMLElement {
	extern appendChild(child: HTMLElement): void;
	extern remove(): void;
}

extern class document {
	static body: HTMLElement;
	static extern createElement(tag: cstring): HTMLElement;
}

function press(label: string): void {
	const done = js(`(() => { for (const el of document.querySelectorAll('[aria-label="${label}"]')) { if (el.getClientRects().length > 0) { el.click(); return 'ok'; } } return 'none'; })()`);
	if (done !== "ok") { throw new Error("no visible element labelled " + label + " in: " + shown()); }
}

function type(label: string, value: string): void {
	js(`(() => { for (const el of document.querySelectorAll('[aria-label="${label}"]')) { if (el.getClientRects().length > 0) { el.value = '${value}'; el.dispatchEvent(new Event('input', { bubbles: true })); } } return ''; })()`);
}

function shown(): string {
	return js("document.body.innerText").replaceAll("\n", "|");
}

function shows(text: string): boolean {
	return shown().indexOf(text) >= 0;
}

test "the navigation demo runs in Chrome: stack with params, kept state, tabs, badge, drawer, back and a deep link" {
	const mount = document.createElement("div");
	document.body.appendChild(mount);
	const dispose = render(element(<NavigationDemo />), domHost(), mount as unknown as HostNode);
	await sleepAsync(100);
	assert shows("Home taps 0"), shown();
	press("Increment home");
	press("Open Void shader");
	await sleepAsync(100);
	const sliding = js(`document.querySelectorAll('[style*="translateX"]').length`);
	assert sliding !== "0", "the pushed screen slides in";
	await sleepAsync(500);
	assert js(`document.querySelectorAll('[style*="translateX"]').length`) === "0", "and settles";
	assert shows("Item number 2") && !shows("Home taps 1"), "only the top screen is visible: " + shown();
	press("Edit item");
	await sleepAsync(500);
	type("Item name", "Void renderer");
	press("Save");
	await sleepAsync(500);
	assert shows("Void renderer") && shows("Item number 2"), "saved: " + shown();
	press("Back");
	await sleepAsync(500);
	assert shows("Home taps 1") && shows("Void renderer"), "list kept its state: " + shown();

	press("Search");
	press("Increment search");
	press("Add badge");
	await sleepAsync(500);
	assert shows("Searches 1"), shown();
	assert js(`document.querySelector('[aria-label="Search"]').innerText`).indexOf("1") >= 0, "badge on the tab";
	press("Profile");
	press("Increment profile");
	press("Search");
	await sleepAsync(500);
	assert shows("Searches 1") && !shows("Profile taps"), shown();

	press("Home");
	press("Show navigation menu");
	await sleepAsync(500);
	assert js(`document.querySelector('[aria-label="Close navigation menu"]').getClientRects().length > 0`) === "true", "drawer open";
	press("Settings");
	await sleepAsync(500);
	assert shows("Settings taps 0"), shown();
	assert dispatchHardwareBackPress(), "back is consumed by the drawer";
	await sleepAsync(500);
	assert shows("Home taps 1"), shown();

	assert navigationRef.linkTo("/items/4");
	await sleepAsync(500);
	assert shows("Ion window") && shows("Item number 4"), shown();
	dispose();
	mount.remove();
}
