import { Node, NodeKind } from "std/meta";

// Narrowing element.ms: which part of the jsxAttrs loop corrupts the result?

// D: loop over jsxAttrs, NO startsWith — constant assign.
export macro mD(n: Node): Node {
	let ctor = "none";
	for (const a of n.jsxAttrs) {
		if (a.kind === NodeKind.JSXAttribute) { ctor = "sawAttr"; }
	}
	return { kind: NodeKind.StringLiteral, line: n.line, column: n.column, value: ctor };
}

// E: loop + startsWith on a Node FIELD receiver (element.ms:20 shape).
export macro mE(n: Node): Node {
	let ctor = "none";
	for (const a of n.jsxAttrs) {
		if (a.kind === NodeKind.JSXAttribute) {
			ctor = a.jsxAttrName.startsWith("on") ? "evt" : "attr";
		}
	}
	return { kind: NodeKind.StringLiteral, line: n.line, column: n.column, value: ctor };
}

// F: no loop, startsWith on a Node field receiver via jsxAttrs[0].
export macro mF(n: Node): Node {
	const a = n.jsxAttrs[0];
	const ctor = a.jsxAttrName.startsWith("on") ? "evt" : "attr";
	return { kind: NodeKind.StringLiteral, line: n.line, column: n.column, value: ctor };
}

test "D: loop, no startsWith" {
	assert mD(<p class="box">hi</p>) === "sawAttr", "loop alone";
}

test "E: loop + startsWith on field" {
	assert mE(<p class="box">hi</p>) === "attr", "loop + startsWith";
}

test "F: indexed, startsWith on field" {
	assert mF(<p class="box">hi</p>) === "attr", "indexed + startsWith";
}
