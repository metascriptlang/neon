import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";

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

test "accessibilityState maps onto aria-checked, aria-selected and aria-disabled and clears what it drops" {
	const h = domHost();
	const el = mount("pressable");
	h.setAttr(el, "accessibilityState", "checked,selected,disabled");
	const first = `${probe(el).getAttribute("aria-checked")} ${probe(el).getAttribute("aria-selected")} ${probe(el).getAttribute("aria-disabled")}`;
	assert first === "true true true", "first: " + first;
	h.setAttr(el, "accessibilityState", "mixed");
	const second = `${probe(el).getAttribute("aria-checked")} ${probe(el).getAttribute("aria-selected")} ${probe(el).getAttribute("aria-disabled")}`;
	assert second === "mixed null null", "second: " + second;
	probe(el).remove();
}
