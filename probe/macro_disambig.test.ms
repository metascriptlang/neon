import { Node, NodeKind } from "std/meta";

// Disambiguation: <div onClick="x" class="box"> — tag len 3, attr count 2,
// attr[0] name "onClick" len 7. Every candidate value is distinct, so exactly
// one test per group passes and the pattern names the mechanism.

export macro mTagLen(n: Node): Node {
	return { kind: NodeKind.NumberLiteral, line: n.line, column: n.column, value: n.jsxTag.length, isFloat: false };
}

export macro mAttrNameLen(n: Node): Node {
	const a = n.jsxAttrs[0];
	return { kind: NodeKind.NumberLiteral, line: n.line, column: n.column, value: a.jsxAttrName.length, isFloat: false };
}

test "tagLen = 3 (truth)" { assert mTagLen(<div onClick="x" class="box">hi</div>) === 3, "tag 3"; }
test "tagLen = 2 (attr-count wrong)" { assert mTagLen(<div onClick="x" class="box">hi</div>) === 2, "tag 2"; }
test "tagLen = 1 (const wrong)" { assert mTagLen(<div onClick="x" class="box">hi</div>) === 1, "tag 1"; }

test "attrNameLen = 7 (truth)" { assert mAttrNameLen(<div onClick="x" class="box">hi</div>) === 7, "an 7"; }
test "attrNameLen = 2 (attr-count wrong)" { assert mAttrNameLen(<div onClick="x" class="box">hi</div>) === 2, "an 2"; }
test "attrNameLen = 1 (const wrong)" { assert mAttrNameLen(<div onClick="x" class="box">hi</div>) === 1, "an 1"; }
