import { Node, NodeKind } from "std/meta";

// G: bind the Node field to a typed local FIRST, then startsWith.
export macro mG(n: Node): Node {
	const a = n.jsxAttrs[0];
	const nm: string = a.jsxAttrName;
	const ctor = nm.startsWith("on") ? "evt" : "attr";
	return { kind: NodeKind.StringLiteral, line: n.line, column: n.column, value: ctor };
}

// H: a DIFFERENT string method on the Node field — is it startsWith-specific?
export macro mH(n: Node): Node {
	const a = n.jsxAttrs[0];
	const v = a.jsxAttrName.length === 5 ? "five" : "other";
	return { kind: NodeKind.StringLiteral, line: n.line, column: n.column, value: v };
}

// I: return the field itself — is the field read even correct?
export macro mI(n: Node): Node {
	const a = n.jsxAttrs[0];
	return { kind: NodeKind.StringLiteral, line: n.line, column: n.column, value: a.jsxAttrName };
}

test "I: field read itself" {
	assert mI(<p class="box">hi</p>) === "class", "field read";
}

test "H: .length on field" {
	assert mH(<p class="box">hi</p>) === "five", "length on field";
}

test "G: typed local then startsWith" {
	assert mG(<p class="box">hi</p>) === "attr", "typed local";
}
