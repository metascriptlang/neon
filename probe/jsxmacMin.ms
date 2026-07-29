import { Node, NodeKind } from "std/meta";

export macro jsxmac(node: Node): Node {
	return {
		kind: NodeKind.StringLiteral,
		line: node.line,
		column: node.column,
		value: "expanded",
	};
}

const x = jsxmac(<div><p>hi</p></div>);
console.log(x);
