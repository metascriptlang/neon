// A client region only moves rows its compute built; one handed an unbuilt row is a reader that would mount in the apply and halt
// reactivity on a pending read, so the reconciler refuses it by name.
import { el, text, regionNode } from "../../src/render/node";
import { Host, HostNode, MockNode, mockHost, render } from "../../src/render/host";
import { Row, makeRow, reconcileArrays } from "../../src/render/reconcile";
import { createMemo } from "../../src/core/memo";

test "reconcileArrays refuses an unbuilt row" {
	const host = mockHost();
	const parent = host.createElement("ul");
	let message = "";
	try {
		reconcileArrays(host, parent, [], [makeRow(el("li", [], [], text("a")))], null);
	} catch (e) {
		message = e.message;
	}
	assert message.indexOf("[ROW_NOT_BUILT]") === 0, "the code leads the message: " + message;
	assert (parent as unknown as MockNode).children.length === 0, "nothing was mounted";
}

test "a client regionNode whose rows memo hands over an unbuilt row throws ROW_NOT_BUILT" {
	const host = mockHost();
	const root = host.createElement("root");
	let message = "";
	try {
		render(regionNode((h: Host) => createMemo<Row[]>((): Row[] => [makeRow(el("li", [], [], text("a")))])), host, root);
	} catch (e) {
		message = e.message;
	}
	assert message.indexOf("[ROW_NOT_BUILT]") === 0, "the code leads the message: " + message;
	assert message.indexOf("regionNode") >= 0, "the region is named: " + message;
}
