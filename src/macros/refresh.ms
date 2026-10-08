import {
	Node,
	NodeKind,
	expansionFile,
	childCount,
	childAt,
	stringValue,
	intValue,
	floatValue,
	isFloatLiteral,
} from "std/meta";

function isComponentName(name: string): boolean {
	if (name.length == 0) return false;
	const c = name.charCodeAt(0);
	return c >= 65 && c <= 90;
}

function isPlainParam(name: string): boolean {
	if (name.length == 0) return false;
	for (let i = 0; i < name.length; i += 1) {
		const c = name.charCodeAt(i);
		const letter = (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
		const digit = c >= 48 && c <= 57;
		if (!letter && !digit && c != 95 && c != 36) return false;
	}
	return true;
}

export macro refreshPass(mod: Node): Node {
	when (refresh) {
		const file = expansionFile();
		let out: Node[] = [];
		let tail: Node[] = [];
		for (const s of mod.programStmts) {
			let decl = s;
			if (s.kind == NodeKind.ExportDecl) decl = s.exportedDecl;
			if (decl.kind != NodeKind.FunctionDecl ||
				!isComponentName(decl.fnName) ||
				decl.fnReturnType != "NeonNode" ||
				decl.fnFlags.indexOf("gen:") >= 0 ||
				decl.params.length > 1 ||
				(decl.params.length == 1 && !isPlainParam(decl.params[0]))) {
				out.push(s);
				continue;
			}
			const L = decl.line;
			const C = decl.column;
			const bodyName = "__refreshBody_" + decl.fnName;
			const sigName = "__refreshSig_" + decl.fnName;
			const hasProps = decl.params.length == 1;
			const id = decl.fnName + "|" + (hasProps ? decl.fnParamTypes[0] : "");

			let sig = decl.params.join(",") + "|" + decl.fnParamTypes.join(",") + "|" +
				decl.fnReturnType;
			let stack: Node[] = [decl.fnBody];
			while (stack.length > 0) {
				const m = stack.pop() as Node;
				sig = sig + "|" + m.kind.toString();
				if (m.kind == NodeKind.Identifier) {
					sig = sig + ":" + m.name;
				} else if (m.kind == NodeKind.StringLiteral) {
					sig = sig + ":" + stringValue(m);
				} else if (m.kind == NodeKind.NumberLiteral) {
					const n = isFloatLiteral(m) ? floatValue(m).toString() : intValue(m).toString();
					sig = sig + ":" + n;
				} else if (m.kind == NodeKind.BooleanLiteral) {
					sig = sig + ":" + (m.boolValue ? "true" : "false");
				} else if (m.kind == NodeKind.MemberExpr) {
					sig = sig + ":" + m.property;
				} else if (m.kind == NodeKind.BinaryExpr) {
					sig = sig + ":" + m.operator;
				} else if (m.kind == NodeKind.UnaryExpr) {
					sig = sig + ":" + m.unaryOp;
				} else if (m.kind == NodeKind.UpdateExpr) {
					sig = sig + ":" + m.updateOp;
				} else if (m.kind == NodeKind.VariableDecl) {
					sig = sig + ":" + m.declName + ":" + m.declType;
				} else if (m.kind == NodeKind.ArrowFunction) {
					sig = sig + ":" + m.arrowParams.join(",") + ":" + m.arrowParamTypes.join(",") +
						":" + m.arrowReturnType;
				} else if (m.kind == NodeKind.TypeAssertion) {
					sig = sig + ":" + m.asType;
				} else if (m.kind == NodeKind.ObjectLiteral) {
					sig = sig + ":" + m.keys.join(",");
				} else if (m.kind == NodeKind.ForOfStmt) {
					sig = sig + ":" + m.forOfBinding;
				} else if (m.kind == NodeKind.ObjectPatternProp) {
					sig = sig + ":" + m.propKey;
				} else if (m.kind == NodeKind.JSXElement) {
					sig = sig + ":" + m.jsxTag;
				} else if (m.kind == NodeKind.JSXText) {
					sig = sig + ":" + m.jsxText;
				} else if (m.kind == NodeKind.JSXAttribute) {
					sig = sig + ":" + m.jsxAttrName;
				}
				const k = childCount(m);
				for (let i = k - 1; i >= 0; i -= 1) { stack.push(childAt(m, i)); }
			}

			out.push({
				kind: NodeKind.FunctionDecl,
				line: L,
				column: C,
				fnName: bodyName,
				params: decl.params,
				fnParamTypes: decl.fnParamTypes,
				fnBody: decl.fnBody,
				fnFlags: decl.fnFlags,
				fnReturnType: decl.fnReturnType,
				fnDefaults: [],
				nativeName: "",
				nameLocation: { line: L, column: C },
			});
			out.push({
				kind: NodeKind.FunctionDecl,
				line: L,
				column: C,
				fnName: sigName,
				params: [],
				fnParamTypes: [],
				fnBody: { kind: NodeKind.BlockStmt, line: L, column: C, statements: [{
					kind: NodeKind.ReturnStmt,
					line: L,
					column: C,
					argument: { kind: NodeKind.StringLiteral, line: L, column: C, value: sig },
				}] },
				fnFlags: "",
				fnReturnType: "string",
				fnDefaults: [],
				nativeName: "",
				nameLocation: { line: L, column: C },
			});
			let mountArgs: Node[] = [
				{ kind: NodeKind.StringLiteral, line: L, column: C, value: file },
				{ kind: NodeKind.StringLiteral, line: L, column: C, value: id },
				{ kind: NodeKind.Identifier, line: L, column: C, name: bodyName },
				{ kind: NodeKind.Identifier, line: L, column: C, name: sigName },
			];
			if (hasProps) {
				const props = decl.params[0];
				mountArgs.push({ kind: NodeKind.Identifier, line: L, column: C, name: props });
			}
			decl.fnBody = { kind: NodeKind.BlockStmt, line: L, column: C, statements: [{
				kind: NodeKind.ReturnStmt,
				line: L,
				column: C,
				argument: {
					kind: NodeKind.CallExpr,
					line: L,
					column: C,
					callee: {
						kind: NodeKind.Identifier,
						line: L,
						column: C,
						name: hasProps ? "refreshBoundary" : "refreshBoundary0",
					},
					arguments: mountArgs,
				},
			}] };
			out.push(s);
			tail.push({ kind: NodeKind.ExprStmt, line: L, column: C, expr: {
				kind: NodeKind.CallExpr,
				line: L,
				column: C,
				callee: {
					kind: NodeKind.Identifier,
					line: L,
					column: C,
					name: hasProps ? "refreshComponent" : "refreshComponent0",
				},
				arguments: [
					{ kind: NodeKind.StringLiteral, line: L, column: C, value: file },
					{ kind: NodeKind.StringLiteral, line: L, column: C, value: id },
					{ kind: NodeKind.Identifier, line: L, column: C, name: bodyName },
					{ kind: NodeKind.Identifier, line: L, column: C, name: sigName },
				],
			} });
		}
		if (tail.length == 0) return mod;
		for (const t of tail) out.push(t);
		const ML = mod.line;
		const MC = mod.column;
		out.push({ kind: NodeKind.ExprStmt, line: ML, column: MC, expr: {
			kind: NodeKind.CallExpr,
			line: ML,
			column: MC,
			callee: { kind: NodeKind.Identifier, line: ML, column: MC, name: "refreshModule" },
			arguments: [{ kind: NodeKind.StringLiteral, line: ML, column: MC, value: file }],
		} });
		return { kind: NodeKind.Program, line: mod.line, column: mod.column, programStmts: out };
	}
	return mod;
}
