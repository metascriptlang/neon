// direct macro — direct emission (docs/RENDER-MODEL.md): JSX → a mount closure
// `(host) => HostNode` that performs the host ops itself, no NeonNode tree, no
// walker. V1 is correctness-first: each nested element becomes its own nested
// mount closure invoked in place (flattening into one block is a later emitter
// upgrade behind the same differential tests). Semantics must stay byte-identical
// to tree emission — tests/render/direct.test.ms pins that differentially.
//
// The emitted code calls createEffect by name and types its param as Host, so
// both must be in scope at the call site. Style and component tags are not
// supported yet (macro error).

import { Node, NodeKind, DeclKind } from "std/meta";
import { cleanJsxText } from "./element";

export macro direct(node: Node): Node {
	const L = node.line;
	const C = node.column;
	const tagStart = node.jsxTag.charAt(0);
	if (tagStart >= "A" && tagStart <= "Z") {
		error("direct emission does not support component tags yet — use tree emission (element) for now", node);
	}

	let stmts: Node[] = [];

	stmts.push({
		kind: NodeKind.VariableDecl, line: L, column: C,
		declName: "_r", declType: "", declKind: DeclKind.Const,
		initializer: {
			kind: NodeKind.CallExpr, line: L, column: C,
			callee: { kind: NodeKind.MemberExpr, line: L, column: C, object: { kind: NodeKind.Identifier, line: L, column: C, name: "host" }, property: "createElement", isOptional: false },
			arguments: [{ kind: NodeKind.StringLiteral, line: L, column: C, value: node.jsxTag }],
		},
	});

	for (const a of node.jsxAttrs) {
		if (a.kind === NodeKind.JSXAttribute) {
			if (a.jsxAttrName === "style" && a.jsxAttrValue.kind !== NodeKind.StringLiteral) {
				error("direct emission does not support the typed style channel yet", a);
			}
			const op = a.jsxAttrName.startsWith("on") ? "addEvent" : "setAttr";
			stmts.push({
				kind: NodeKind.ExprStmt, line: a.line, column: a.column,
				expr: {
					kind: NodeKind.CallExpr, line: a.line, column: a.column,
					callee: { kind: NodeKind.MemberExpr, line: a.line, column: a.column, object: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "host" }, property: op, isOptional: false },
					arguments: [
						{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: "_r" },
						{ kind: NodeKind.StringLiteral, line: a.line, column: a.column, value: a.jsxAttrName },
						a.jsxAttrValue,
					],
				},
			});
		}
	}

	let tIdx = 0;
	let cIdx = 0;
	for (const c of node.jsxChildren) {
		if (c.kind === NodeKind.JSXText) {
			const cleaned = cleanJsxText(c.jsxText);
			if (cleaned !== "") {
				stmts.push({
					kind: NodeKind.ExprStmt, line: c.line, column: c.column,
					expr: {
						kind: NodeKind.CallExpr, line: c.line, column: c.column,
						callee: { kind: NodeKind.MemberExpr, line: c.line, column: c.column, object: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "host" }, property: "append", isOptional: false },
						arguments: [
							{ kind: NodeKind.Identifier, line: c.line, column: c.column, name: "_r" },
							{
								kind: NodeKind.CallExpr, line: c.line, column: c.column,
								callee: { kind: NodeKind.MemberExpr, line: c.line, column: c.column, object: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "host" }, property: "createText", isOptional: false },
								arguments: [{ kind: NodeKind.StringLiteral, line: c.line, column: c.column, value: cleaned }],
							},
						],
					},
				});
			}
		} else if (c.kind === NodeKind.JSXExpressionContainer) {
			const tName = "_t" + tIdx.toString();
			tIdx = tIdx + 1;
			stmts.push({
				kind: NodeKind.VariableDecl, line: c.line, column: c.column,
				declName: tName, declType: "", declKind: DeclKind.Const,
				initializer: {
					kind: NodeKind.CallExpr, line: c.line, column: c.column,
					callee: { kind: NodeKind.MemberExpr, line: c.line, column: c.column, object: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "host" }, property: "createText", isOptional: false },
					arguments: [{ kind: NodeKind.StringLiteral, line: c.line, column: c.column, value: "" }],
				},
			});
			stmts.push({
				kind: NodeKind.ExprStmt, line: c.line, column: c.column,
				expr: {
					kind: NodeKind.CallExpr, line: c.line, column: c.column,
					callee: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "createEffect" },
					arguments: [{
						kind: NodeKind.ArrowFunction, line: c.line, column: c.column,
						arrowParams: [], arrowParamTypes: [], arrowFlags: "", arrowReturnType: "",
						arrowBody: {
							kind: NodeKind.BlockStmt, line: c.line, column: c.column,
							statements: [{
								kind: NodeKind.ExprStmt, line: c.line, column: c.column,
								expr: {
									kind: NodeKind.CallExpr, line: c.line, column: c.column,
									callee: { kind: NodeKind.MemberExpr, line: c.line, column: c.column, object: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "host" }, property: "setText", isOptional: false },
									arguments: [
										{ kind: NodeKind.Identifier, line: c.line, column: c.column, name: tName },
										c.jsxExpr,
									],
								},
							}],
						},
					}],
				},
			});
			stmts.push({
				kind: NodeKind.ExprStmt, line: c.line, column: c.column,
				expr: {
					kind: NodeKind.CallExpr, line: c.line, column: c.column,
					callee: { kind: NodeKind.MemberExpr, line: c.line, column: c.column, object: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "host" }, property: "append", isOptional: false },
					arguments: [
						{ kind: NodeKind.Identifier, line: c.line, column: c.column, name: "_r" },
						{ kind: NodeKind.Identifier, line: c.line, column: c.column, name: tName },
					],
				},
			});
		} else if (c.kind === NodeKind.JSXElement) {
			const cName = "_c" + cIdx.toString();
			cIdx = cIdx + 1;
			stmts.push({
				kind: NodeKind.VariableDecl, line: c.line, column: c.column,
				declName: cName, declType: "", declKind: DeclKind.Const,
				initializer: { kind: NodeKind.MacroInvocation, line: c.line, column: c.column, macroName: "direct", macroArgs: [c] },
			});
			// Bind the child mount result before append: BUGS.md §2 "call-result arg
			// at an address-taken position" — general lowerRvalue hoist is unwired in
			// the C backend, and a bound temp is the natural emission shape anyway.
			const eName = "_e" + (cIdx - 1).toString();
			stmts.push({
				kind: NodeKind.VariableDecl, line: c.line, column: c.column,
				declName: eName, declType: "", declKind: DeclKind.Const,
				initializer: {
					kind: NodeKind.CallExpr, line: c.line, column: c.column,
					callee: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: cName },
					arguments: [{ kind: NodeKind.Identifier, line: c.line, column: c.column, name: "host" }],
				},
			});
			stmts.push({
				kind: NodeKind.ExprStmt, line: c.line, column: c.column,
				expr: {
					kind: NodeKind.CallExpr, line: c.line, column: c.column,
					callee: { kind: NodeKind.MemberExpr, line: c.line, column: c.column, object: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "host" }, property: "append", isOptional: false },
					arguments: [
						{ kind: NodeKind.Identifier, line: c.line, column: c.column, name: "_r" },
						{ kind: NodeKind.Identifier, line: c.line, column: c.column, name: eName },
					],
				},
			});
		}
	}

	stmts.push({
		kind: NodeKind.ReturnStmt, line: L, column: C,
		argument: { kind: NodeKind.Identifier, line: L, column: C, name: "_r" },
	});

	return {
		kind: NodeKind.ArrowFunction, line: L, column: C,
		arrowParams: ["host"], arrowParamTypes: ["Host"], arrowFlags: "", arrowReturnType: "",
		arrowBody: { kind: NodeKind.BlockStmt, line: L, column: C, statements: stmts },
	};
}
