import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { NeonEvent } from "../../src/render/event";

extern class Node {
	extern getAttribute(name: cstring): string | null;
	extern remove(): void;
}

function probe(n: HostNode): Node {
	return n as unknown as Node;
}

function mount(tag: string): HostNode {
	const h = domHost();
	const el = h.createElement(tag);
	h.insertBefore(documentBody(), el, null);
	return el;
}

test "accessibilityValue, live region, hidden, modal, labelledBy and focusable map onto aria attributes and tabindex, and clear" {
	const h = domHost();
	const el = mount("view");
	h.setAttr(el, "accessibilityValue", "0,10,3,three, of ten");
	h.setAttr(el, "accessibilityLiveRegion", "none");
	h.setAttr(el, "accessibilityViewIsModal", "true");
	h.setAttr(el, "accessibilityLabelledBy", "a,b");
	h.setAttr(el, "importantForAccessibility", "no-hide-descendants");
	h.setAttr(el, "accessibilityActions", "magicTap");
	h.setAttr(el, "focusable", "true");
	const got = ["aria-valuemin", "aria-valuemax", "aria-valuenow", "aria-valuetext", "aria-live", "aria-modal", "aria-labelledby", "aria-hidden", "tabindex"]
		.map((n: string): string => `${probe(el).getAttribute(n)}`).join("|");
	assert got === "0|10|3|three, of ten|off|true|a b|true|0", got;
	assert probe(el).getAttribute("accessibilityActions") === null, "actions write no attribute";
	h.setAttr(el, "accessibilityValue", ",,,");
	assert probe(el).getAttribute("aria-valuemin") === null, "empty value fields clear";
	h.setAttr(el, "focusable", "false");
	assert probe(el).getAttribute("tabindex") === "-1", "not focusable";
	h.setAttr(el, "accessibilityElementsHidden", "false");
	assert probe(el).getAttribute("aria-hidden") === null, "elements shown";
	h.removeAttr(el, "accessibilityLabelledBy");
	h.removeAttr(el, "accessibilityValue");
	assert probe(el).getAttribute("aria-labelledby") === null && probe(el).getAttribute("aria-valuetext") === null, "removed";
	probe(el).remove();
}

test "a focusable div takes DOM focus through ViewHandle.focus" {
	const h = domHost();
	const el = mount("view");
	h.setAttr(el, "focusable", "true");
	let seen = "";
	h.addEvent(el, "onFocus", (e: NeonEvent): void => { seen += "focus;"; });
	const focus = h.focus;
	assert focus !== null, "the browser host advertises focus";
	if (focus !== null) { focus(el, true); }
	assert seen === "focus;", "a div with tabindex takes focus: " + seen;
	probe(el).remove();
}

test "accessibilityState maps onto aria-checked, aria-selected and aria-disabled and clears what it drops" {
	const h = domHost();
	const el = mount("pressable");
	h.setAttr(el, "accessibilityState", "checked,selected,disabled");
	const first = `${probe(el).getAttribute("aria-checked")} ${probe(el).getAttribute("aria-selected")} ${probe(el).getAttribute("aria-disabled")}`;
	assert first === "true true true", "first: " + first;
	h.setAttr(el, "accessibilityState", "mixed");
	const second = `${probe(el).getAttribute("aria-checked")} ${probe(el).getAttribute("aria-selected")} ${probe(el).getAttribute("aria-disabled")}`;
	assert second === "mixed null null", "second: " + second;
	h.removeAttr(el, "accessibilityState");
	assert probe(el).getAttribute("aria-checked") === null, "removed: " + (probe(el).getAttribute("aria-checked") as string);
	probe(el).remove();
}
