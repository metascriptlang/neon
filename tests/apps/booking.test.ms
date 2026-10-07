import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEvent, fireEventWith } from "../../src/render/host";
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

function change(root: MockNode, label: string, value: string): void {
	const e = neonEvent("valuechange");
	e.value = value;
	fireEventWith(labelled(root, label), "onValueChange", e);
}

function shows(root: MockNode, text: string): boolean {
	return mockToString(root).indexOf(text) >= 0;
}

test "booking: every control feeds the summary, the dialog books with progress, the snackbar undoes into a toast" {
	const root = mockNode("root");
	render(element(<BookingForm />), mockHost(), root as unknown as HostNode);
	assert shows(root, "status idle") && shows(root, "guests 2"), "initial: " + mockToString(root);
	change(root, "Check-in date", "2026-10-24");
	change(root, "Arrival time", "18:30");
	change(root, "Guests", "4.6");
	change(root, "Room type", "2");
	assert shows(root, "check-in 2026-10-24 at 18:30") && shows(root, "guests 5") && shows(root, "room Suite"), "native controls: " + mockToString(root);
	fireEvent(labelled(root, "Breakfast"), "onPress");
	fireEvent(labelled(root, "Cash"), "onPress");
	assert shows(root, "extras breakfast") && shows(root, "payment cash"), "checkbox and radio: " + mockToString(root);
	fireEvent(labelled(root, "Details"), "onPress");
	assert shows(root, "details Suite for 5 guests from 2026-10-24 18:30"), "bottom sheet";
	fireEvent(labelled(root, "Close"), "onPress");
	assert !shows(root, "details Suite"), "bottom sheet closed";
	fireEvent(labelled(root, "Book"), "onPress");
	assert shows(root, "Confirm booking"), "dialog open";
	fireEvent(labelled(root, "Confirm"), "onPress");
	assert shows(root, "status booking") && byAttr(root, "accessibilityLabel", "Booking in progress") !== null, "progress shown: " + mockToString(root);
	await sleepAsync(1800);
	assert shows(root, "status booked") && shows(root, "Booked Suite for 5 guests"), "snackbar: " + mockToString(root);
	assert byAttr(root, "accessibilityLabel", "Booking in progress") === null, "progress gone";
	fireEvent(labelled(root, "Undo"), "onPress");
	assert shows(root, "status cancelled") && shows(root, "Booking cancelled"), "toast: " + mockToString(root);
}
