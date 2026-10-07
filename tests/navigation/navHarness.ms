import { MockNode } from "../../src/render/host";
import { Style } from "../../src/render/style";
import { fireEvent } from "../../src/render/host";

export function hidden(node: MockNode): boolean {
	const style = node.style;
	return style !== null && (style as Style).display === "none";
}

export function visibleText(node: MockNode): string {
	if (node.tag === "") { return node.text; }
	if (hidden(node)) { return ""; }
	let out = "";
	for (const child of node.children) {
		const part = visibleText(child);
		if (part === "") { continue; }
		out = out === "" ? part : out + "|" + part;
	}
	return out;
}

export function attrOf(node: MockNode, name: string): string {
	for (const a of node.attrs) {
		if (a.name === name) { return a.value ?? ""; }
	}
	return "";
}

export function findLabel(node: MockNode, label: string): MockNode | null {
	if (hidden(node)) { return null; }
	if (attrOf(node, "accessibilityLabel") === label) { return node; }
	for (const child of node.children) {
		const found = findLabel(child, label);
		if (found !== null) { return found; }
	}
	return null;
}

export function press(root: MockNode, label: string): void {
	const node = findLabel(root, label);
	if (node === null) { throw new Error("no visible element labelled '" + label + "' in " + visibleText(root)); }
	fireEvent(node as MockNode, "onPress");
}
