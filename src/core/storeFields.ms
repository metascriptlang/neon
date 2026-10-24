import { Node, NodeKind, getTypeImpl, stringValue } from "std/meta";

export macro fieldsLiteral(typed: Node, step: Node, arg: Node): Node {
	const shape = getTypeImpl(typed);
	if (shape == null || shape.kind != NodeKind.TypeObject) {
		error("a store walk needs an object type with named fields", typed);
	}
	const names: string[] = [];
	const properties: Node[] = [];
	for (const name of shape.typExprFieldNames) {
		names.push(name);
		properties.push({
			kind: NodeKind.CallExpr, line: typed.line, column: typed.column,
			callee: { kind: NodeKind.Identifier, line: typed.line, column: typed.column, name: stringValue(step) },
			arguments: [arg, { kind: NodeKind.StringLiteral, line: typed.line, column: typed.column, value: name }],
		});
	}
	return { kind: NodeKind.ObjectLiteral, line: typed.line, column: typed.column, properties: properties, keys: names, keyLocations: [] };
}
