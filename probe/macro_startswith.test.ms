import { Node, NodeKind } from "std/meta";

// No JSX. Does a compile-time `.startsWith()` inside a macro body corrupt the
// macro's return value?

export macro m1(n: Node): Node {
	const s = "onClick";
	const c = s.startsWith("on") ? "yes" : "no";
	return { kind: NodeKind.StringLiteral, line: n.line, column: n.column, value: c };
}

export macro m2(n: Node): Node {
	const s = "onClick";
	const c = s === "onClick" ? "yes" : "no";
	return { kind: NodeKind.StringLiteral, line: n.line, column: n.column, value: c };
}

test "m2: ternary on === (control)" {
	assert m2(0) === "yes", "eq-ternary macro";
}

test "m1: ternary on startsWith" {
	assert m1(0) === "yes", "startsWith-ternary macro";
}
