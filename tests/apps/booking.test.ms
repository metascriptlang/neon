import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Host, HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEvent, fireEventWith, fireTouch } from "../../src/render/host";
import { neonEvent } from "../../src/render/event";
import { sleepAsync } from "std/core/promise";
import { BookingForm } from "../../examples/components/controls";

function byAttr(n: MockNode, name: string, value: string): MockNode | null {
	for (const a of n.attrs) {
		if (a.name === name && a.isDyn && a.dyn() === value) { return n; }
		if (a.name === name && !a.isDyn && a.value === value) { return n; }
	}
	for (const c of n.children) {
		const found = byAttr(c, name, value);
		if (found !== null) { return found; }
	}
	return null;
}

function labelled(root: MockNode, label: string): MockNode {
	const found = byAttr(root, "accessibilityLabel", label);
	if (found === null) { throw "no node labelled " + label + " in " + mockToString(root); }
	return found as MockNode;
}

function overlayOf(host: Host): MockNode {
	return (host.overlayRoot as (n: HostNode) => HostNode)(mockNode("any") as unknown as HostNode) as unknown as MockNode;
}

function scrollWheel(wheel: MockNode, item: number): void {
	const e = neonEvent("scroll");
	e.y = item * 32;
	e.height = 160;
	fireEventWith(wheel, "onScroll", e);
	flush();
}

function wheels(n: MockNode, out: MockNode[]): MockNode[] {
	if (n.tag === "scrollview") { out.push(n); }
	for (const c of n.children) { wheels(c, out); }
	return out;
}

// The slider at 304 pt has a 280 pt track, 40 pt per guest over 1..8.
function slide(root: MockNode, label: string, dx: number): void {
	const slider = labelled(root, label);
	const e = neonEvent("layout");
	e.width = 304;
	e.height = 40;
	fireEventWith(slider, "onLayout", e);
	flush();
	const surface = slider.children[0];
	fireTouch(surface, "onTouchStart", 100, 20, 1000);
	flush();
	fireTouch(surface, "onTouchMove", 100 + dx, 20, 1016);
	flush();
	fireTouch(surface, "onTouchEnd", 100 + dx, 20, 1032);
	flush();
}

function shows(root: MockNode, text: string): boolean {
	return mockToString(root).indexOf(text) >= 0;
}

test "booking: every control feeds the summary, the dialog books with progress, the snackbar undoes into a toast" {
	const root = mockNode("root");
	const host = mockHost();
	const dispose = render(element(<BookingForm />), host, root as unknown as HostNode);
	const overlay = overlayOf(host);
	assert shows(root, "status idle") && shows(root, "guests 2"), "initial: " + mockToString(root);
	fireEvent(labelled(root, "Check-in date"), "onPress");
	flush();
	fireEvent(labelled(overlay, "October 24, 2026"), "onPress");
	flush();
	fireEvent(labelled(overlay, "OK"), "onPress");
	flush();
	fireEvent(labelled(root, "Arrival time"), "onPress");
	flush();
	const pair = wheels(overlay, []);
	scrollWheel(pair[0], 18);
	scrollWheel(pair[1], 30);
	fireEvent(labelled(overlay, "OK"), "onPress");
	flush();
	slide(root, "Guests", 120);
	fireEvent(labelled(root, "Room type"), "onPress");
	flush();
	fireEvent(labelled(overlay, "Suite"), "onPress");
	flush();
	assert shows(root, "check-in 2026-10-24 at 18:30") && shows(root, "guests 5") && shows(root, "room Suite"), "neon-ui controls: " + mockToString(root);
	fireEvent(labelled(root, "Breakfast"), "onPress");
	flush();
	fireEvent(labelled(root, "Cash"), "onPress");
	flush();
	assert shows(root, "extras breakfast") && shows(root, "payment cash"), "checkbox and radio: " + mockToString(root);
	fireEvent(labelled(root, "Details"), "onPress");
	assert shows(overlay, "details Suite for 5 guests from 2026-10-24 18:30"), "bottom sheet";
	assert !shows(root, "details Suite"), "the sheet escapes the form";
	fireEvent(labelled(overlay, "Close"), "onPress");
	flush();
	assert !shows(overlay, "details Suite"), "bottom sheet closed";
	fireEvent(labelled(root, "Book"), "onPress");
	flush();
	assert shows(overlay, "Confirm booking") && !shows(root, "Confirm booking"), "dialog open outside the form";
	fireEvent(labelled(overlay, "Confirm"), "onPress");
	flush();
	assert shows(root, "status booking") && byAttr(root, "accessibilityLabel", "Booking in progress") !== null, "progress shown: " + mockToString(root);
	await sleepAsync(1800);
	assert shows(root, "status booked") && shows(overlay, "Booked Suite for 5 guests"), "snackbar: " + mockToString(overlay);
	assert byAttr(root, "accessibilityLabel", "Booking in progress") === null, "progress gone";
	fireEvent(labelled(overlay, "Undo"), "onPress");
	flush();
	assert shows(root, "status cancelled") && shows(overlay, "Booking cancelled"), "toast: " + mockToString(overlay);
	dispose();
	flush();
	assert !shows(overlay, "Booking cancelled"), "owner cleanup removes the toast from its physical root";
}
