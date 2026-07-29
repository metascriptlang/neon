import { Node, NodeKind } from "std/meta";

function shout(s: string): string {
	return s + "!";
}

export macro jsxmacx(node: Node): Node {
	return {
		kind: NodeKind.StringLiteral,
		line: node.line,
		column: node.column,
		value: shout("expanded-x"),
	};
}
