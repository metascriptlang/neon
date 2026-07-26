import { Node, NodeKind } from "std/meta";

// Force the checker to reveal the static type of these virtual JSX accessors.
// If `a.jsxAttrName` is Unknown, assigning it to a number will NOT error.
// If it is genuinely `string`, it WILL error.

export macro mM(n: Node): Node {
	const a = n.jsxAttrs[0];
	const bogus = a.totallyBogusFieldXyz;      // does Node accept ANY property?
	const asNum: number = a.jsxAttrName;       // string -> number should error
	const tagNum: number = n.jsxTag;           // string -> number should error
	return { kind: NodeKind.StringLiteral, line: n.line, column: n.column, value: "x" };
}

test "M" {
	assert mM(<p class="box">hi</p>) === "x", "probe";
}
