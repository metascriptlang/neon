import { Node, NodeKind } from "std/meta";

interface Box { s: string; }

// J: chained member on a PLAIN local object (not a bridge Node).
export macro mJ(n: Node): Node {
	const b: Box = { s: "class" };
	const v = b.s.length === 5 ? "five" : "other";
	return { kind: NodeKind.StringLiteral, line: n.line, column: n.column, value: v };
}

// K: chained member on a DIRECT Node field of the macro param (not via jsxAttrs[]).
export macro mK(n: Node): Node {
	const v = n.jsxTag.length === 1 ? "one" : "other";
	return { kind: NodeKind.StringLiteral, line: n.line, column: n.column, value: v };
}

// L: chained on a local string const (control — known good).
export macro mL(n: Node): Node {
	const s = "class";
	const v = s.length === 5 ? "five" : "other";
	return { kind: NodeKind.StringLiteral, line: n.line, column: n.column, value: v };
}

test "L: chain on local string (control)" {
	assert mL(<p class="box">hi</p>) === "five", "local string";
}

test "J: chain on plain object field" {
	assert mJ(<p class="box">hi</p>) === "five", "plain object field";
}

test "K: chain on direct Node field" {
	assert mK(<p class="box">hi</p>) === "one", "direct node field";
}
