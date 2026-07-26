import { Node, NodeKind } from "std/meta";

// Direct reads (no chaining) under TYPED params — separates "member read broken"
// from "chain lowering broken".

export macro mTagDirect(n: Node): Node {
	return { kind: NodeKind.StringLiteral, line: n.line, column: n.column, value: n.jsxTag };
}

export macro mAttrNameDirect(n: Node): Node {
	const a = n.jsxAttrs[0];
	return { kind: NodeKind.StringLiteral, line: n.line, column: n.column, value: a.jsxAttrName };
}

test "tag direct = div" { assert mTagDirect(<div onClick="x" class="box">hi</div>) === "div", "tag div"; }
test "attr[0] name direct = onClick" { assert mAttrNameDirect(<div onClick="x" class="box">hi</div>) === "onClick", "attr onClick"; }
