import { Node, NodeKind } from "std/meta";

// What does compile-time `.length` actually yield on an array-element Node field?
// "class".length === 5 is the truth. Bracket the observed value.
export macro mLen(n: Node): Node {
	const a = n.jsxAttrs[0];
	return { kind: NodeKind.NumberLiteral, line: n.line, column: n.column, value: a.jsxAttrName.length, isFloat: false };
}

// Control: same shape on the macro param's own field ("p".length === 1).
export macro mLenTag(n: Node): Node {
	return { kind: NodeKind.NumberLiteral, line: n.line, column: n.column, value: n.jsxTag.length, isFloat: false };
}

test "tag length is 1" { assert mLenTag(<p class="box">hi</p>) === 1, "tag len"; }

test "attr-name length is 5" { assert mLen(<p class="box">hi</p>) === 5, "is 5"; }
test "attr-name length is 0" { assert mLen(<p class="box">hi</p>) === 0, "is 0"; }
test "attr-name length is 1" { assert mLen(<p class="box">hi</p>) === 1, "is 1"; }
