import { TerminalNode, createTerminalNode, createTerminalTextNode } from "../../src/platform/terminal/types";
import { terminalHost } from "../../src/platform/terminal/host";
import { paintNode, paintTree } from "../../src/platform/terminal/paint";
import { HostNode } from "../../src/render/hostTypes";

function tn(hostNode: HostNode): TerminalNode {
	return hostNode as unknown as TerminalNode;
}

test "paintNode: text node produces one line" {
	const node = createTerminalTextNode("hello");
	const lines = paintNode(node, 80);
	assert lines.length === 1, "single text node = 1 line";
	assert lines[0] === "hello", "content is hello";
}

test "paintNode: text wraps to width" {
	const node = createTerminalTextNode("hello world foo bar");
	const lines = paintNode(node, 10);
	assert lines.length >= 2, "should wrap into 2+ lines";
}

test "paintNode: box stacks children vertically" {
	const root = createTerminalNode("box");
	const child1 = createTerminalTextNode("line one");
	const child2 = createTerminalTextNode("line two");
	root.children.push(child1);
	child1.parent = root;
	root.children.push(child2);
	child2.parent = root;
	const lines = paintNode(root, 80);
	assert lines.length === 2, "two children = 2 lines";
}

test "paintNode: box with border adds top and bottom" {
	const root = createTerminalNode("box");
	root.attrs.set("border", "true");
	root.attrs.set("padding", "0");
	const child = createTerminalTextNode("hi");
	root.children.push(child);
	child.parent = root;
	const lines = paintNode(root, 80);
	assert lines.length === 3, "border + 1 child + border = 3 lines";
}

test "paintNode: hr fills width" {
	const node = createTerminalNode("hr");
	const lines = paintNode(node, 20);
	assert lines.length === 1, "hr is one line";
	assert lines[0].length >= 20, "hr fills width";
}

test "paintNode: gap produces N blank lines" {
	const node = createTerminalNode("gap");
	node.attrs.set("height", "3");
	const lines = paintNode(node, 80);
	assert lines.length === 3, "gap height 3 = 3 blank lines";
}

test "paintNode: row lays children side by side" {
	const root = createTerminalNode("row");
	const left = createTerminalTextNode("AB");
	const right = createTerminalTextNode("CD");
	root.children.push(left);
	left.parent = root;
	root.children.push(right);
	right.parent = root;
	const lines = paintNode(root, 20);
	assert lines.length === 1, "two short text in row = 1 line";
}

test "terminalHost: createElement creates TerminalNode" {
	const host = terminalHost();
	const node = host.createElement("box");
	const n = tn(node);
	assert n.tag === "box", "tag is box";
	assert n.children.length === 0, "no children yet";
}

test "terminalHost: append adds child" {
	const host = terminalHost();
	const parent = host.createElement("box");
	const child = host.createText("hi");
	host.append(parent, child);
	assert tn(parent).children.length === 1, "one child after append";
}

test "terminalHost: setAttr applies style" {
	const host = terminalHost();
	const node = host.createElement("text");
	host.setAttr(node, "color", "red");
	host.setAttr(node, "bold", "true");
	const n = tn(node);
	assert n.style.color === "red", "color set";
	assert n.style.bold === true, "bold set";
}

test "terminalHost: full tree build via Host ops" {
	const host = terminalHost();
	const root = host.createElement("box");
	host.setAttr(root, "border", "true");
	const child = host.createText("Hello Terminal");
	host.append(root, child);
	const lines = paintTree(tn(root), 40);
	assert lines.length === 3, "border + content + border = 3 lines";
}
