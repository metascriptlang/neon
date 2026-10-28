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

export macro fieldsDo(typed: Node, step: Node, plan: Node): Node {
	const shape = getTypeImpl(typed);
	if (shape == null || shape.kind != NodeKind.TypeObject) {
		error("a store walk needs an object type with named fields", typed);
	}
	let chain: Node = { kind: NodeKind.BooleanLiteral, line: typed.line, column: typed.column, boolValue: true };
	const names = shape.typExprFieldNames;
	let i = names.length - 1;
	while (i >= 0) {
		chain = {
			kind: NodeKind.BinaryExpr, line: typed.line, column: typed.column, operator: "&&",
			left: {
				kind: NodeKind.CallExpr, line: typed.line, column: typed.column,
				callee: { kind: NodeKind.Identifier, line: typed.line, column: typed.column, name: stringValue(step) },
				arguments: [plan, { kind: NodeKind.StringLiteral, line: typed.line, column: typed.column, value: names[i] }],
			},
			right: chain,
		};
		i = i - 1;
	}
	return chain;
}

export macro keyedBy(item: Node, name: Node): Node {
	const shape = getTypeImpl(item);
	let chain: Node = { kind: NodeKind.NullLiteral, line: item.line, column: item.column, nullPlaceholder: true };
	if (shape != null && shape.kind == NodeKind.TypeObject) {
		const names = shape.typExprFieldNames;
		const types = shape.typExprFieldTypes;
		let i = names.length - 1;
		while (i >= 0) {
			const read: Node = { kind: NodeKind.MemberExpr, line: item.line, column: item.column, object: item, property: names[i], isOptional: false };
			let atomic = false;
			const fieldType: Node = types[i];
			if (fieldType.kind == NodeKind.Identifier) {
				const n = fieldType.name;
				atomic = n == "string" || n == "boolean" || n == "number" || n == "float32" || n == "float64"
					|| n == "int8" || n == "int16" || n == "int32" || n == "int64"
					|| n == "uint8" || n == "uint16" || n == "uint32" || n == "uint64";
			}
			const callee = atomic ? "keyText" : "keyNotAtomic";
			chain = {
				kind: NodeKind.ConditionalExpr, line: item.line, column: item.column,
				ternaryCondition: {
					kind: NodeKind.BinaryExpr, line: item.line, column: item.column, operator: "===",
					left: name,
					right: { kind: NodeKind.StringLiteral, line: item.line, column: item.column, value: names[i] },
				},
				ternaryConsequent: {
					kind: NodeKind.CallExpr, line: item.line, column: item.column,
					callee: { kind: NodeKind.Identifier, line: item.line, column: item.column, name: callee },
					arguments: callee == "keyText" ? [read] : [name],
				},
				ternaryAlternate: chain,
			};
			i = i - 1;
		}
	}
	return chain;
}
