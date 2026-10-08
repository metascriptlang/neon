import { Node, NodeKind, expansionFile } from "std/meta";

export macro thisFile(): Node {
	return { kind: NodeKind.StringLiteral, line: 0, column: 0, value: expansionFile() };
}
