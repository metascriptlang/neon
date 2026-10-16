import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { sleepAsync } from "std/core/promise";
import { SettingsApp } from "../../examples/components/settings";

extern class HTMLElement {
	textContent: string;
	value: string;
	checked: boolean;
	tagName: string;
	extern querySelector(selector: cstring): HTMLElement | null;
	extern click(): void;
	extern appendChild(child: HTMLElement): void;
	extern focus(): void;
	extern getAttribute(name: cstring): string | null;
	extern remove(): void;
}

extern class window {
	static extern eval(code: cstring): void;
}

extern class document {
	static body: HTMLElement;
	static extern createElement(tag: cstring): HTMLElement;
}

function labelled(root: HTMLElement, label: string): HTMLElement {
	const found = root.querySelector(`[aria-label="${label}"]`);
	if (found === null) { throw "no element labelled " + label; }
	return found as HTMLElement;
}

function type(label: string, value: string): void {
	window.eval(`(() => { const el = document.querySelector('[aria-label="${label}"]'); el.value = '${value}'; el.dispatchEvent(new Event('input', { bubbles: true })); })()`);
}

function enter(label: string): void {
	window.eval(`document.querySelector('[aria-label="${label}"]').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))`);
}

function shows(root: HTMLElement, text: string): boolean {
	return root.textContent.indexOf(text) >= 0;
}

// parked: the catalog workflow returns with the product list, see ~/metascript/.inbox/compiler/2026-10-16-function-returning-one-member-is-refused-where-a-function-returning-the-union-is-expected.md

test "settings runs in Chrome: return key moves DOM focus, Enter saves, a switch flips the theme" {
	const mount = document.createElement("div");
	document.body.appendChild(mount);
	render(element(<SettingsApp />), domHost(), mount as unknown as HostNode);
	labelled(mount, "Name").focus();
	await sleepAsync(50);
	assert shows(mount, "Focus: name"), "focus reported";
	type("Name", "Grace Hopper");
	enter("Name");
	await sleepAsync(50);
	assert shows(mount, "Focus: email"), "return key moved focus to email: " + mount.textContent.substring(0, 160);
	enter("Email");
	await sleepAsync(50);
	assert shows(mount, "Saved Grace Hopper <ada@example.com>"), "saved";
	assert labelled(mount, "Use system theme").getAttribute("role") === "switch", "switch role";
	labelled(mount, "Use system theme").click();
	labelled(mount, "Dark mode").click();
	assert shows(mount, "dark theme"), "manual dark theme";
	mount.remove();
}
