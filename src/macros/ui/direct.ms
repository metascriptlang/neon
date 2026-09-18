import { Node, NodeKind } from "std/meta";

export macro direct(node: Node): Node {
	return { kind: NodeKind.MacroInvocation, line: node.line, column: node.column, macroName: "element", macroArgs: [node] };
}
