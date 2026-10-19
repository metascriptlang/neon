import { domHost } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { flush } from "../../src/core/runtime";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { sleepAsync } from "std/core/promise";
import { BookingForm } from "../../examples/components/controls";

extern class HTMLElement {
	textContent: string;
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

// A touch drag on the slider's gesture surface, its first child, far enough to reach the maximum.
function dragToEnd(label: string): void {
	window.eval(`(() => { const el = document.querySelector('[aria-label="${label}"]').firstChild; const at = (type, x) => new PointerEvent(type, { bubbles: true, cancelable: true, pointerId: 7, pointerType: 'touch', clientX: x, clientY: 10 }); el.dispatchEvent(at('pointerdown', 10)); el.dispatchEvent(at('pointermove', 400)); el.dispatchEvent(at('pointermove', 2000)); el.dispatchEvent(at('pointerup', 2000)); })()`);
}

function shows(root: HTMLElement, text: string): boolean {
	return root.textContent.indexOf(text) >= 0;
}

test "the booking form runs in Chrome on neon-ui controls, ARIA state and the overlay flow" {
	const mount = document.createElement("div");
	document.body.appendChild(mount);
	render(element(<BookingForm />), domHost(), mount as unknown as HostNode);
	await sleepAsync(50);
	labelled(mount, "Check-in date").click();
	flush();
	labelled(document.body, "October 24, 2026").click();
	flush();
	labelled(document.body, "OK").click();
	flush();
	dragToEnd("Guests");
	flush();
	labelled(mount, "Room type").click();
	flush();
	labelled(document.body, "Suite").click();
	flush();
	assert shows(mount, "check-in 2026-10-24 at 15:00") && shows(mount, "guests 8") && shows(mount, "room Suite"), "neon-ui controls: " + mount.textContent.substring(0, 300);
	const breakfast = labelled(mount, "Breakfast");
	assert breakfast.getAttribute("role") === "checkbox" && breakfast.getAttribute("aria-checked") === "false", "checkbox ARIA";
	breakfast.click();
	flush();
	assert breakfast.getAttribute("aria-checked") === "true" && shows(mount, "extras breakfast"), "checked";
	labelled(mount, "Cash").click();
	flush();
	assert labelled(mount, "Cash").getAttribute("aria-checked") === "true" && shows(mount, "payment cash"), "radio";
	labelled(mount, "Book").click();
	flush();
	assert shows(mount, "Confirm booking"), "dialog";
	labelled(mount, "Confirm").click();
	flush();
	assert shows(mount, "status booking"), "booking";
	await sleepAsync(1800);
	assert shows(mount, "status booked") && shows(mount, "Booked Suite for 8 guests"), "snackbar: " + mount.textContent.substring(0, 300);
	labelled(mount, "Undo").click();
	flush();
	assert shows(mount, "status cancelled") && shows(mount, "Booking cancelled"), "toast";
	mount.remove();
}
