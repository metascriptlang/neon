import { Node, NodeKind, JSXAttributeData } from "std/meta";

// FEASIBILITY of narrow-first inside the macro VM.
// The VM wire format is flat (no `data` key) — does `.data as XData` work at all?

// N1: the 3297-call-site idiom, applied in a macro body.
export macro mN1(n: Node): Node {
	const a = n.jsxAttrs[0];
	const d = a.data as JSXAttributeData;
	return { kind: NodeKind.StringLiteral, line: n.line, column: n.column, value: d.jsxAttrName };
}

// N2: same + a chained call (the thing that breaks with flat sugar).
export macro mN2(n: Node): Node {
	const a = n.jsxAttrs[0];
	const d = a.data as JSXAttributeData;
	const v = d.jsxAttrName.startsWith("on") ? "evt" : "attr";
	return { kind: NodeKind.StringLiteral, line: n.line, column: n.column, value: v };
}

// N3: narrow by kind, then flat sugar (does narrowing alone fix dispatch?).
export macro mN3(n: Node): Node {
	const a = n.jsxAttrs[0];
	let v = "none";
	if (a.kind === NodeKind.JSXAttribute) {
		v = a.jsxAttrName.startsWith("on") ? "evt" : "attr";
	}
	return { kind: NodeKind.StringLiteral, line: n.line, column: n.column, value: v };
}

test "N1: .data as XData field read" { assert mN1(<p class="box">hi</p>) === "class", "data read"; }
test "N2: .data as XData + startsWith" { assert mN2(<p class="box">hi</p>) === "attr", "data chain"; }
test "N3: kind-narrow + flat sugar" { assert mN3(<p class="box">hi</p>) === "attr", "kind narrow"; }
