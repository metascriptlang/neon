import { Node, NodeKind } from "std/meta";

// Hypothesis: `a.jsxAttrName.length` collapses to the length of the ARRAY
// `jsxAttrs`, not the string. With TWO attributes it should yield 2
// (truth for "class".length is still 5).
export macro mLen2(n: Node): Node {
	const a = n.jsxAttrs[0];
	return { kind: NodeKind.NumberLiteral, line: n.line, column: n.column, value: a.jsxAttrName.length, isFloat: false };
}

// Control: the documented-DONE shape — array field .length.
export macro mArrLen(n: Node): Node {
	return { kind: NodeKind.NumberLiteral, line: n.line, column: n.column, value: n.jsxAttrs.length, isFloat: false };
}

// Typed-local route (the workaround) — should be the true 5.
export macro mTyped(n: Node): Node {
	const a = n.jsxAttrs[0];
	const nm: string = a.jsxAttrName;
	return { kind: NodeKind.NumberLiteral, line: n.line, column: n.column, value: nm.length, isFloat: false };
}

test "control: jsxAttrs.length is 2" { assert mArrLen(<p class="box" id="z">hi</p>) === 2, "arr len 2"; }

test "typed local: length is 5" { assert mTyped(<p class="box" id="z">hi</p>) === 5, "typed 5"; }

test "chained equals ARRAY length 2" { assert mLen2(<p class="box" id="z">hi</p>) === 2, "chained is 2"; }
test "chained equals TRUE length 5" { assert mLen2(<p class="box" id="z">hi</p>) === 5, "chained is 5"; }
