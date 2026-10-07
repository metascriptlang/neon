import { domHost } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { sleepAsync } from "std/core/promise";
import { BookingForm } from "../../examples/components/controls";

extern class HTMLElement {
	textContent: string;
	tagName: string;
	extern querySelector(selector: cstring): HTMLElement | null;
	extern click(): void;
	extern appendChild(child: HTMLElement): void;
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

function setValue(label: string, value: string, event: string): void {
	window.eval(`(() => { const el = document.querySelector('[aria-label="${label}"]'); el.value = '${value}'; el.dispatchEvent(new Event('${event}', { bubbles: true })); })()`);
}

function pick(label: string, index: int32): void {
	window.eval(`(() => { const el = document.querySelector('[aria-label="${label}"]'); el.selectedIndex = ${index}; el.dispatchEvent(new Event('change', { bubbles: true })); })()`);
}

function shows(root: HTMLElement, text: string): boolean {
	return root.textContent.indexOf(text) >= 0;
}

test "the booking form runs in Chrome on real form controls, ARIA state and the overlay flow" {
	const mount = document.createElement("div");
	document.body.appendChild(mount);
	render(element(<BookingForm />), domHost(), mount as unknown as HostNode);
	assert labelled(mount, "Check-in date").getAttribute("type") === "date", "a date input";
	assert labelled(mount, "Arrival time").getAttribute("type") === "time", "a time input";
	assert labelled(mount, "Guests").getAttribute("type") === "range", "a range input";
	assert labelled(mount, "Room type").tagName === "SELECT", "a select";
	setValue("Check-in date", "2026-10-24", "change");
	setValue("Guests", "5", "input");
	pick("Room type", 2);
	assert shows(mount, "check-in 2026-10-24 at 15:00") && shows(mount, "guests 5") && shows(mount, "room Suite"), "native form controls: " + mount.textContent.substring(0, 300);
	const breakfast = labelled(mount, "Breakfast");
	assert breakfast.getAttribute("role") === "checkbox" && breakfast.getAttribute("aria-checked") === "false", "checkbox ARIA";
	breakfast.click();
	assert breakfast.getAttribute("aria-checked") === "true" && shows(mount, "extras breakfast"), "checked";
	labelled(mount, "Cash").click();
	assert labelled(mount, "Cash").getAttribute("aria-checked") === "true" && shows(mount, "payment cash"), "radio";
	labelled(mount, "Book").click();
	assert shows(mount, "Confirm booking"), "dialog";
	labelled(mount, "Confirm").click();
	assert shows(mount, "status booking"), "booking";
	await sleepAsync(1800);
	assert shows(mount, "status booked") && shows(mount, "Booked Suite for 5 guests"), "snackbar: " + mount.textContent.substring(0, 300);
	labelled(mount, "Undo").click();
	assert shows(mount, "status cancelled") && shows(mount, "Booking cancelled"), "toast";
	mount.remove();
}
