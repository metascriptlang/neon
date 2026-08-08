// direct macro — direct emission (docs/RENDER-MODEL.md): JSX → a mount closure
// `(host) => HostNode` that performs the host ops itself, no NeonNode tree, no
// walker. V1 is correctness-first: each nested element becomes its own nested
// mount closure invoked in place (flattening into one block is a later emitter
// upgrade behind the same differential tests). Semantics must stay byte-identical
// to tree emission — tests/render/direct.test.ms pins that differentially.
//
// The emitted code calls createEffect / createComponent / renderNode /
// renderToHost / element / text by name and types its param as Host, so all of
// those must be in scope at the call site. Attr classification mirrors
// element.ms: string literal → setAttr once, on* → addEvent, any other expr →
// one createEffect around setAttr (1 dynamic spot = 1 effect); a non-literal
// style routes through host.setStyle with the same S4 field validation.

import { Node, NodeKind, DeclKind } from "std/meta";
import { cleanJsxText } from "./element";

export macro direct(node: Node): Node {
	const L = node.line;
	const C = node.column;
	// Capitalized tag → createComponent(Tag, { props }), mirroring element.ms's prop
	// contract byte for byte (string literals pass through, expression props become
	// thunks, children stay structural NeonNode trees via element/text). The NeonNode
	// then goes through the runtime mount seam instead of being returned as data:
	// root position mounts via renderNode (loud throw if the component expands to a
	// region — same contract as the tree walker), child position via renderToHost
	// (which mirrors the renderNode child loop: peel componentFn chain, region →
	// anchor + reconcile, node → append). Inline in both branches because node
	// literals only type-check inside a macro body (engine-mode Node view).
	const tagStart = node.jsxTag.charAt(0);
	if (tagStart >= "A" && tagStart <= "Z") {
		let keys: string[] = [];
		let values: Node[] = [];
		for (const a of node.jsxAttrs) {
			if (a.kind === NodeKind.JSXAttribute) {
				keys.push(a.jsxAttrName);
				if (a.jsxAttrValue.kind === NodeKind.StringLiteral) {
					values.push(a.jsxAttrValue);
				} else {
					values.push({ kind: NodeKind.ArrowFunction, line: a.line, column: a.column, arrowParams: [], arrowParamTypes: [], arrowBody: a.jsxAttrValue, arrowFlags: "", arrowReturnType: "" });
				}
			}
		}
		let compKids: Node[] = [];
		for (const c of node.jsxChildren) {
			if (c.kind === NodeKind.JSXText) {
				const cleaned = cleanJsxText(c.jsxText);
				if (cleaned !== "") {
					compKids.push({
						kind: NodeKind.CallExpr, line: c.line, column: c.column,
						callee: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "text" },
						arguments: [{ kind: NodeKind.StringLiteral, line: c.line, column: c.column, value: cleaned }],
					});
				}
			} else if (c.kind === NodeKind.JSXExpressionContainer) {
				compKids.push(c.jsxExpr);
			} else if (c.kind === NodeKind.JSXElement) {
				compKids.push({
					kind: NodeKind.CallExpr, line: c.line, column: c.column,
					callee: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "element" },
					arguments: [c],
				});
			}
		}
		if (compKids.length === 1) {
			keys.push("children");
			values.push(compKids[0]);
		} else if (compKids.length > 1) {
			keys.push("children");
			values.push({ kind: NodeKind.ArrayLiteral, line: L, column: C, elements: compKids });
		}
		const rootStmts: Node[] = [
			{
				kind: NodeKind.VariableDecl, line: L, column: C,
				declName: "_k0", declType: "", declKind: DeclKind.Const,
				initializer: {
					kind: NodeKind.CallExpr, line: L, column: C,
					callee: { kind: NodeKind.Identifier, line: L, column: C, name: "createComponent" },
					arguments: [
						{ kind: NodeKind.Identifier, line: L, column: C, name: node.jsxTag },
						{ kind: NodeKind.ObjectLiteral, line: L, column: C, properties: values, keys: keys },
					],
				},
			},
			{
				kind: NodeKind.ReturnStmt, line: L, column: C,
				argument: {
					kind: NodeKind.CallExpr, line: L, column: C,
					callee: { kind: NodeKind.Identifier, line: L, column: C, name: "renderNode" },
					arguments: [
						{ kind: NodeKind.Identifier, line: L, column: C, name: "_k0" },
						{ kind: NodeKind.Identifier, line: L, column: C, name: "host" },
					],
				},
			},
		];
		return {
			kind: NodeKind.ArrowFunction, line: L, column: C,
			arrowParams: ["host"], arrowParamTypes: ["Host"], arrowFlags: "", arrowReturnType: "",
			arrowBody: { kind: NodeKind.BlockStmt, line: L, column: C, statements: rootStmts },
		};
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

	let sIdx = 0;
	for (const a of node.jsxAttrs) {
		if (a.kind === NodeKind.JSXAttribute) {
			if (a.jsxAttrName === "style" && a.jsxAttrValue.kind !== NodeKind.StringLiteral) {
				if (a.jsxAttrValue.kind === NodeKind.ObjectLiteral) {
					for (const fv of a.jsxAttrValue.properties) {
						if (fv.kind === NodeKind.CallExpr) {
							error("a style field cannot call a function — a signal read here would be a frozen snapshot, not reactive (reactive style fields land in S4)", fv);
						}
					}
				}
				// Bind the style expr to a temp before the call: BUGS.md §2 call-result
				// arg at an address-taken position (same reason as the _e child temps).
				const sName = "_s" + sIdx.toString();
				sIdx = sIdx + 1;
				stmts.push({
					kind: NodeKind.VariableDecl, line: a.line, column: a.column,
					declName: sName, declType: "", declKind: DeclKind.Const,
					initializer: a.jsxAttrValue,
				});
				stmts.push({
					kind: NodeKind.ExprStmt, line: a.line, column: a.column,
					expr: {
						kind: NodeKind.CallExpr, line: a.line, column: a.column,
						callee: { kind: NodeKind.MemberExpr, line: a.line, column: a.column, object: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "host" }, property: "setStyle", isOptional: false },
						arguments: [
							{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: "_r" },
							{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: sName },
						],
					},
				});
				continue;
			}
			const nameLit: Node = { kind: NodeKind.StringLiteral, line: a.line, column: a.column, value: a.jsxAttrName };
			if (a.jsxAttrName.startsWith("on")) {
				stmts.push({
					kind: NodeKind.ExprStmt, line: a.line, column: a.column,
					expr: {
						kind: NodeKind.CallExpr, line: a.line, column: a.column,
						callee: { kind: NodeKind.MemberExpr, line: a.line, column: a.column, object: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "host" }, property: "addEvent", isOptional: false },
						arguments: [
							{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: "_r" },
							nameLit,
							a.jsxAttrValue,
						],
					},
				});
			} else if (a.jsxAttrValue.kind === NodeKind.StringLiteral) {
				stmts.push({
					kind: NodeKind.ExprStmt, line: a.line, column: a.column,
					expr: {
						kind: NodeKind.CallExpr, line: a.line, column: a.column,
						callee: { kind: NodeKind.MemberExpr, line: a.line, column: a.column, object: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "host" }, property: "setAttr", isOptional: false },
						arguments: [
							{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: "_r" },
							nameLit,
							a.jsxAttrValue,
						],
					},
				});
			} else {
				stmts.push({
					kind: NodeKind.ExprStmt, line: a.line, column: a.column,
					expr: {
						kind: NodeKind.CallExpr, line: a.line, column: a.column,
						callee: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "createEffect" },
						arguments: [{
							kind: NodeKind.ArrowFunction, line: a.line, column: a.column,
							arrowParams: [], arrowParamTypes: [], arrowFlags: "", arrowReturnType: "",
							arrowBody: {
								kind: NodeKind.BlockStmt, line: a.line, column: a.column,
								statements: [{
									kind: NodeKind.ExprStmt, line: a.line, column: a.column,
									expr: {
										kind: NodeKind.CallExpr, line: a.line, column: a.column,
										callee: { kind: NodeKind.MemberExpr, line: a.line, column: a.column, object: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "host" }, property: "setAttr", isOptional: false },
										arguments: [
											{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: "_r" },
											nameLit,
											a.jsxAttrValue,
										],
									},
								}],
							},
						}],
					},
				});
			}
		}
	}

	let tIdx = 0;
	let cIdx = 0;
	let kIdx = 0;
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
		} else if (c.kind === NodeKind.JSXElement && c.jsxTag.charAt(0) >= "A" && c.jsxTag.charAt(0) <= "Z") {
			let ckeys: string[] = [];
			let cvalues: Node[] = [];
			for (const a of c.jsxAttrs) {
				if (a.kind === NodeKind.JSXAttribute) {
					ckeys.push(a.jsxAttrName);
					if (a.jsxAttrValue.kind === NodeKind.StringLiteral) {
						cvalues.push(a.jsxAttrValue);
					} else {
						cvalues.push({ kind: NodeKind.ArrowFunction, line: a.line, column: a.column, arrowParams: [], arrowParamTypes: [], arrowBody: a.jsxAttrValue, arrowFlags: "", arrowReturnType: "" });
					}
				}
			}
			let cKids: Node[] = [];
			for (const gc of c.jsxChildren) {
				if (gc.kind === NodeKind.JSXText) {
					const gcleaned = cleanJsxText(gc.jsxText);
					if (gcleaned !== "") {
						cKids.push({
							kind: NodeKind.CallExpr, line: gc.line, column: gc.column,
							callee: { kind: NodeKind.Identifier, line: gc.line, column: gc.column, name: "text" },
							arguments: [{ kind: NodeKind.StringLiteral, line: gc.line, column: gc.column, value: gcleaned }],
						});
					}
				} else if (gc.kind === NodeKind.JSXExpressionContainer) {
					cKids.push(gc.jsxExpr);
				} else if (gc.kind === NodeKind.JSXElement) {
					cKids.push({
						kind: NodeKind.CallExpr, line: gc.line, column: gc.column,
						callee: { kind: NodeKind.Identifier, line: gc.line, column: gc.column, name: "element" },
						arguments: [gc],
					});
				}
			}
			if (cKids.length === 1) {
				ckeys.push("children");
				cvalues.push(cKids[0]);
			} else if (cKids.length > 1) {
				ckeys.push("children");
				cvalues.push({ kind: NodeKind.ArrayLiteral, line: c.line, column: c.column, elements: cKids });
			}
			const kName = "_k" + kIdx.toString();
			kIdx = kIdx + 1;
			stmts.push({
				kind: NodeKind.VariableDecl, line: c.line, column: c.column,
				declName: kName, declType: "", declKind: DeclKind.Const,
				initializer: {
					kind: NodeKind.CallExpr, line: c.line, column: c.column,
					callee: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "createComponent" },
					arguments: [
						{ kind: NodeKind.Identifier, line: c.line, column: c.column, name: c.jsxTag },
						{ kind: NodeKind.ObjectLiteral, line: c.line, column: c.column, properties: cvalues, keys: ckeys },
					],
				},
			});
			stmts.push({
				kind: NodeKind.ExprStmt, line: c.line, column: c.column,
				expr: {
					kind: NodeKind.CallExpr, line: c.line, column: c.column,
					callee: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "renderToHost" },
					arguments: [
						{ kind: NodeKind.Identifier, line: c.line, column: c.column, name: kName },
						{ kind: NodeKind.Identifier, line: c.line, column: c.column, name: "host" },
						{ kind: NodeKind.Identifier, line: c.line, column: c.column, name: "_r" },
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
