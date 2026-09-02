// direct macro — direct emission (docs/RENDER-MODEL.md): JSX → a mount closure
// `(host) => HostNode` that performs the host ops itself, no NeonNode tree, no
// walker. Nested lowercase elements flatten INLINE into the one mount block
// (D3): a single statement list, temps numbered across the whole tree
// (_r0/_r1/... elements, _t0/... dynamic texts, _k0/... component children,
// _s0/... style temps), child subtree emitted depth-first then appended to its
// parent — no per-level closure, no per-level call. Semantics must stay
// byte-identical to tree emission — tests/render/direct.test.ms pins that
// differentially.
//
// Component tags, Show and For do NOT flatten: their structure changes at
// runtime, so they stay runtime calls — root position mounts via renderNode,
// child position via createComponent + renderToHost (the same seam the tree
// walker uses).
//
// The emitted code calls bindText / bindAttr / createComponent / renderNode /
// renderToHost / element / text by name and types its param as Host, so all of
// those must be in scope at the call site. Attr classification mirrors
// element.ms: string literal → setAttr once, on* → addEvent, any other expr →
// one createEffect around setAttr (1 dynamic spot = 1 effect); a non-literal
// style routes through host.setStyle with the same S4 field validation.

import { Node, NodeKind, DeclKind, NodeFlag } from "std/meta";
import { cleanJsxText } from "./element";
import { isReactiveExpr } from "./reactive";

export macro direct(node: Node): Node {
	const L = node.line;
	const C = node.column;
	// Capitalized tag → createComponent(Tag, { props }), mirroring element.ms's prop
	// contract byte for byte (string literals pass through, expression props become
	// thunks, a JSX child passes RAW so the converter picks the emission from the
	// prop's declared type — wrapping it here would pre-pick tree). The NeonNode
	// then goes through the runtime mount seam instead of being returned as data:
	// root position mounts via renderNode (loud throw if the component expands to a
	// region — same contract as the tree walker). Inline because node literals only
	// type-check inside a macro body (engine-mode Node view).
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
				compKids.push(c);
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

	// ---- D4 template mode ----
	// A subtree of nothing but lowercase elements, text, attrs, events and style
	// has a STATIC skeleton: build it once, duplicate it per mount, and walk to
	// the dynamic spots along a path computed here at compile time. Component
	// tags and regions change structure at runtime, so a subtree containing one
	// keeps the D3 flat emission below, unchanged.
	function isPureSubtree(el: Node): boolean {
		for (const c of el.jsxChildren) {
			if (c.kind === NodeKind.JSXElement) {
				const t0 = c.jsxTag.charAt(0);
				if (t0 >= "A" && t0 <= "Z") { return false; }
				if (!isPureSubtree(c)) { return false; }
			}
		}
		return true;
	}

	// Does this element need a runtime handle in the instance (as opposed to
	// living entirely inside the template)? Only handles get walk steps.
	function needsHandle(el: Node): boolean {
		for (const a of el.jsxAttrs) {
			if (a.kind === NodeKind.JSXAttribute) {
				if (a.jsxAttrName.startsWith("on")) { return true; }
				if (a.jsxAttrValue.kind !== NodeKind.StringLiteral) { return true; }
			}
		}
		for (const c of el.jsxChildren) {
			if (c.kind === NodeKind.JSXExpressionContainer) { return true; }
			if (c.kind === NodeKind.JSXElement && needsHandle(c)) { return true; }
		}
		return false;
	}

	if (node.jsxTag !== "" && isPureSubtree(node)) {
		let bStmts: Node[] = [];
		let wStmts: Node[] = [];
		let bIdx = 0;
		let pIdx = 1;
		let tsIdx = 0;
		let tplOffenders: Node[] = [];

		function hostCall(recv: string, method: string, args: Node[], ln: int32, col: int32): Node {
			return {
				kind: NodeKind.CallExpr, line: ln, column: col,
				callee: { kind: NodeKind.MemberExpr, line: ln, column: col, object: { kind: NodeKind.Identifier, line: ln, column: col, name: recv }, property: method, isOptional: false },
				arguments: args,
			};
		}

		function ident(n: string, ln: int32, col: int32): Node {
			return { kind: NodeKind.Identifier, line: ln, column: col, name: n };
		}

		function strLit(v: string, ln: int32, col: int32): Node {
			return { kind: NodeKind.StringLiteral, line: ln, column: col, value: v };
		}

		// Skeleton: elements, static attrs, and a placeholder for every dynamic
		// slot. A dynamic attr keeps its SOURCE position with an empty value —
		// the per-instance effect upserts it, so markup order matches tree
		// emission (probe/tmplShape.ms "attr order" is the red-proof).
		function emitBuild(el: Node): string {
			const rName = "_r" + bIdx.toString();
			bIdx = bIdx + 1;
			bStmts.push({
				kind: NodeKind.VariableDecl, line: el.line, column: el.column,
				declName: rName, declType: "", declKind: DeclKind.Const,
				initializer: hostCall("h", "createElement", [strLit(el.jsxTag, el.line, el.column)], el.line, el.column),
			});
			for (const a of el.jsxAttrs) {
				if (a.kind === NodeKind.JSXAttribute) {
					if (a.jsxAttrName.startsWith("on")) { continue; }
					if (a.jsxAttrName === "style" && a.jsxAttrValue.kind !== NodeKind.StringLiteral) { continue; }
					const v = a.jsxAttrValue.kind === NodeKind.StringLiteral ? a.jsxAttrValue : strLit("", a.line, a.column);
					bStmts.push({
						kind: NodeKind.ExprStmt, line: a.line, column: a.column,
						expr: hostCall("h", "setAttr", [ident(rName, a.line, a.column), strLit(a.jsxAttrName, a.line, a.column), v], a.line, a.column),
					});
				}
			}
			for (const c of el.jsxChildren) {
				if (c.kind === NodeKind.JSXText) {
					const cleaned = cleanJsxText(c.jsxText);
					if (cleaned !== "") {
						bStmts.push({
							kind: NodeKind.ExprStmt, line: c.line, column: c.column,
							expr: hostCall("h", "append", [ident(rName, c.line, c.column), hostCall("h", "createText", [strLit(cleaned, c.line, c.column)], c.line, c.column)], c.line, c.column),
						});
					}
				} else if (c.kind === NodeKind.JSXExpressionContainer) {
					bStmts.push({
						kind: NodeKind.ExprStmt, line: c.line, column: c.column,
						expr: hostCall("h", "append", [ident(rName, c.line, c.column), hostCall("h", "createText", [strLit("", c.line, c.column)], c.line, c.column)], c.line, c.column),
					});
				} else if (c.kind === NodeKind.JSXElement) {
					const kid = emitBuild(c);
					bStmts.push({
						kind: NodeKind.ExprStmt, line: c.line, column: c.column,
						expr: hostCall("h", "append", [ident(rName, c.line, c.column), ident(kid, c.line, c.column)], c.line, c.column),
					});
				}
			}
			return rName;
		}

		// Per-instance wiring: dynamic attrs (one effect each), events, style,
		// then the walk into children that carry dynamic spots.
		function emitWire(el: Node, elVar: string): void {
			for (const a of el.jsxAttrs) {
				if (a.kind === NodeKind.JSXAttribute) {
					if (a.jsxAttrName === "style" && a.jsxAttrValue.kind !== NodeKind.StringLiteral) {
						if (a.jsxAttrValue.kind === NodeKind.ObjectLiteral) {
							for (const fv of a.jsxAttrValue.properties) {
								if (fv.kind === NodeKind.CallExpr) { tplOffenders.push(fv); }
							}
						}
						const sName = "_ts" + tsIdx.toString();
						tsIdx = tsIdx + 1;
						wStmts.push({
							kind: NodeKind.VariableDecl, line: a.line, column: a.column,
							declName: sName, declType: "", declKind: DeclKind.Const,
							initializer: a.jsxAttrValue,
						});
						wStmts.push({
							kind: NodeKind.ExprStmt, line: a.line, column: a.column,
							expr: hostCall("host", "setStyle", [ident(elVar, a.line, a.column), ident(sName, a.line, a.column)], a.line, a.column),
						});
					} else if (a.jsxAttrName.startsWith("on")) {
						// onChangeText text-unwrap — mirrors element.ms, see the comment there.
						let hVal: Node = a.jsxAttrValue;
						if (a.jsxAttrName === "onChangeText") {
							hVal = { kind: NodeKind.ArrowFunction, line: a.line, column: a.column, arrowParams: ["__msCte"], arrowParamTypes: [""], arrowFlags: "", arrowReturnType: "", arrowBody: { kind: NodeKind.CallExpr, line: a.line, column: a.column, callee: a.jsxAttrValue, arguments: [{ kind: NodeKind.MemberExpr, line: a.line, column: a.column, object: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "__msCte" }, property: "value", isOptional: false }] } };
						}
						wStmts.push({
							kind: NodeKind.ExprStmt, line: a.line, column: a.column,
							expr: hostCall("host", "addEvent", [ident(elVar, a.line, a.column), strLit(a.jsxAttrName, a.line, a.column), hVal], a.line, a.column),
						});
					} else if (a.jsxAttrValue.kind !== NodeKind.StringLiteral) {
						wStmts.push({
							kind: NodeKind.ExprStmt, line: a.line, column: a.column,
							expr: !isReactiveExpr(a.jsxAttrValue) ? hostCall("host", "setAttr", [ident(elVar, a.line, a.column), strLit(a.jsxAttrName, a.line, a.column), a.jsxAttrValue], a.line, a.column) : {
								kind: NodeKind.CallExpr, line: a.line, column: a.column,
								callee: ident("bindAttr", a.line, a.column),
								arguments: [
									ident("host", a.line, a.column),
									ident(elVar, a.line, a.column),
									strLit(a.jsxAttrName, a.line, a.column),
									{
										kind: NodeKind.ArrowFunction, line: a.line, column: a.column,
										arrowParams: [], arrowParamTypes: [], arrowFlags: "", arrowReturnType: "",
										arrowBody: a.jsxAttrValue,
									},
								],
							},
						});
					}
				}
			}

			let lastVar = "";
			let lastIdx = 0 - 1;
			let slot = 0;
			for (const c of el.jsxChildren) {
				let occupies = true;
				let wants = false;
				if (c.kind === NodeKind.JSXText) {
					occupies = cleanJsxText(c.jsxText) !== "";
				} else if (c.kind === NodeKind.JSXExpressionContainer) {
					wants = true;
				} else if (c.kind === NodeKind.JSXElement) {
					wants = needsHandle(c);
				} else {
					occupies = false;
				}
				if (!occupies) { continue; }
				if (wants) {
					let curVar = lastVar;
					let k = lastIdx;
					if (lastVar === "") {
						curVar = "_p" + pIdx.toString();
						pIdx = pIdx + 1;
						wStmts.push({
							kind: NodeKind.VariableDecl, line: c.line, column: c.column,
							declName: curVar, declType: "", declKind: DeclKind.Const,
							initializer: {
								kind: NodeKind.CallExpr, line: c.line, column: c.column,
								callee: ident("childOf", c.line, c.column),
								arguments: [ident("host", c.line, c.column), ident(elVar, c.line, c.column)],
							},
						});
						k = 0;
					}
					while (k < slot) {
						const nextVar = "_p" + pIdx.toString();
						pIdx = pIdx + 1;
						wStmts.push({
							kind: NodeKind.VariableDecl, line: c.line, column: c.column,
							declName: nextVar, declType: "", declKind: DeclKind.Const,
							initializer: {
								kind: NodeKind.CallExpr, line: c.line, column: c.column,
								callee: ident("siblingOf", c.line, c.column),
								arguments: [ident("host", c.line, c.column), ident(curVar, c.line, c.column)],
							},
						});
						curVar = nextVar;
						k = k + 1;
					}
					lastVar = curVar;
					lastIdx = slot;
					if (c.kind === NodeKind.JSXExpressionContainer) {
						wStmts.push({
							kind: NodeKind.ExprStmt, line: c.line, column: c.column,
							expr: !isReactiveExpr(c.jsxExpr) ? hostCall("host", "setText", [ident(curVar, c.line, c.column), c.jsxExpr], c.line, c.column) : {
								kind: NodeKind.CallExpr, line: c.line, column: c.column,
								callee: ident("bindText", c.line, c.column),
								arguments: [
									ident("host", c.line, c.column),
									ident(curVar, c.line, c.column),
									{
										kind: NodeKind.ArrowFunction, line: c.line, column: c.column,
										arrowParams: [], arrowParamTypes: [], arrowFlags: "", arrowReturnType: "",
										arrowBody: c.jsxExpr,
									},
								],
							},
						});
					} else {
						emitWire(c, curVar);
					}
				}
				slot = slot + 1;
			}
		}

		const tplRoot = emitBuild(node);
		emitWire(node, "_p0");
		if (tplOffenders.length > 0) {
			error("a style field cannot call a function — a signal read here would be a frozen snapshot, not reactive (reactive style fields land in S4)", tplOffenders[0]);
		}
		bStmts.push({
			kind: NodeKind.ReturnStmt, line: L, column: C,
			argument: { kind: NodeKind.Identifier, line: L, column: C, name: tplRoot },
		});

		const tplName = "_tpl" + L.toString() + "_" + C.toString();
		return {
			kind: NodeKind.SpliceMany, line: L, column: C,
			spliceNodes: [
				{
					kind: NodeKind.VariableDecl, line: L, column: C,
					flags: NodeFlag.StaticStorage,
					declName: tplName, declType: "", declKind: DeclKind.Const,
					nameLocation: { line: L, column: C },
					initializer: {
						kind: NodeKind.CallExpr, line: L, column: C,
						callee: { kind: NodeKind.Identifier, line: L, column: C, name: "createTemplate" },
						arguments: [{
							kind: NodeKind.ArrowFunction, line: L, column: C,
							arrowParams: ["h"], arrowParamTypes: ["Host"], arrowFlags: "", arrowReturnType: "HostNode",
							arrowBody: { kind: NodeKind.BlockStmt, line: L, column: C, statements: bStmts },
						}],
					},
				},
				{
					kind: NodeKind.CallExpr, line: L, column: C,
					callee: { kind: NodeKind.Identifier, line: L, column: C, name: "mountTemplate" },
					arguments: [
						{ kind: NodeKind.Identifier, line: L, column: C, name: tplName },
						{
							kind: NodeKind.ArrowFunction, line: L, column: C,
							arrowParams: ["host", "_p0"], arrowParamTypes: ["Host", "HostNode"], arrowFlags: "", arrowReturnType: "void",
							arrowBody: { kind: NodeKind.BlockStmt, line: L, column: C, statements: wStmts },
						},
					],
				},
			],
		};
	}

	let stmts: Node[] = [];
	let rIdx = 0;
	let tIdx = 0;
	let kIdx = 0;
	let sIdx = 0;
	// error() only type-checks at the macro body's top level (the engine folds its
	// compileError value into a nested function's return type), so emitEl records
	// the offending node and the error fires after the walk — same message, same
	// location, and error() aborts expansion either way.
	let styleOffenders: Node[] = [];

	function emitEl(el: Node): string {
		const rName = "_r" + rIdx.toString();
		rIdx = rIdx + 1;
		stmts.push({
			kind: NodeKind.VariableDecl, line: el.line, column: el.column,
			declName: rName, declType: "", declKind: DeclKind.Const,
			initializer: {
				kind: NodeKind.CallExpr, line: el.line, column: el.column,
				callee: { kind: NodeKind.MemberExpr, line: el.line, column: el.column, object: { kind: NodeKind.Identifier, line: el.line, column: el.column, name: "host" }, property: "createElement", isOptional: false },
				arguments: [{ kind: NodeKind.StringLiteral, line: el.line, column: el.column, value: el.jsxTag }],
			},
		});

		for (const a of el.jsxAttrs) {
			if (a.kind === NodeKind.JSXAttribute) {
				if (a.jsxAttrName === "style" && a.jsxAttrValue.kind !== NodeKind.StringLiteral) {
					if (a.jsxAttrValue.kind === NodeKind.ObjectLiteral) {
						for (const fv of a.jsxAttrValue.properties) {
							if (fv.kind === NodeKind.CallExpr) {
								styleOffenders.push(fv);
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
								{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: rName },
								{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: sName },
							],
						},
					});
					continue;
				}
				const nameLit: Node = { kind: NodeKind.StringLiteral, line: a.line, column: a.column, value: a.jsxAttrName };
				if (a.jsxAttrName.startsWith("on")) {
					// onChangeText text-unwrap — mirrors element.ms, see the comment there.
					let hVal: Node = a.jsxAttrValue;
					if (a.jsxAttrName === "onChangeText") {
						hVal = { kind: NodeKind.ArrowFunction, line: a.line, column: a.column, arrowParams: ["__msCte"], arrowParamTypes: [""], arrowFlags: "", arrowReturnType: "", arrowBody: { kind: NodeKind.CallExpr, line: a.line, column: a.column, callee: a.jsxAttrValue, arguments: [{ kind: NodeKind.MemberExpr, line: a.line, column: a.column, object: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "__msCte" }, property: "value", isOptional: false }] } };
					}
					stmts.push({
						kind: NodeKind.ExprStmt, line: a.line, column: a.column,
						expr: {
							kind: NodeKind.CallExpr, line: a.line, column: a.column,
							callee: { kind: NodeKind.MemberExpr, line: a.line, column: a.column, object: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "host" }, property: "addEvent", isOptional: false },
							arguments: [
								{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: rName },
								nameLit,
								hVal,
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
								{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: rName },
								nameLit,
								a.jsxAttrValue,
							],
						},
					});
				} else {
					stmts.push({
						kind: NodeKind.ExprStmt, line: a.line, column: a.column,
						expr: !isReactiveExpr(a.jsxAttrValue) ? {
							kind: NodeKind.CallExpr, line: a.line, column: a.column,
							callee: { kind: NodeKind.MemberExpr, line: a.line, column: a.column, object: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "host" }, property: "setAttr", isOptional: false },
							arguments: [
								{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: rName },
								nameLit,
								a.jsxAttrValue,
							],
						} : {
							kind: NodeKind.CallExpr, line: a.line, column: a.column,
							callee: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "bindAttr" },
							arguments: [
								{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: "host" },
								{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: rName },
								nameLit,
								{
									kind: NodeKind.ArrowFunction, line: a.line, column: a.column,
									arrowParams: [], arrowParamTypes: [], arrowFlags: "", arrowReturnType: "",
									arrowBody: a.jsxAttrValue,
								},
							],
						},
					});
				}
			}
		}

		for (const c of el.jsxChildren) {
			if (c.kind === NodeKind.JSXText) {
				const cleaned = cleanJsxText(c.jsxText);
				if (cleaned !== "") {
					stmts.push({
						kind: NodeKind.ExprStmt, line: c.line, column: c.column,
						expr: {
							kind: NodeKind.CallExpr, line: c.line, column: c.column,
							callee: { kind: NodeKind.MemberExpr, line: c.line, column: c.column, object: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "host" }, property: "append", isOptional: false },
							arguments: [
								{ kind: NodeKind.Identifier, line: c.line, column: c.column, name: rName },
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
				const liveSpot = isReactiveExpr(c.jsxExpr);
				stmts.push({
					kind: NodeKind.VariableDecl, line: c.line, column: c.column,
					declName: tName, declType: "", declKind: DeclKind.Const,
					initializer: {
						kind: NodeKind.CallExpr, line: c.line, column: c.column,
						callee: { kind: NodeKind.MemberExpr, line: c.line, column: c.column, object: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "host" }, property: "createText", isOptional: false },
						arguments: [liveSpot ? { kind: NodeKind.StringLiteral, line: c.line, column: c.column, value: "" } : c.jsxExpr],
					},
				});
				if (liveSpot) {
					stmts.push({
						kind: NodeKind.ExprStmt, line: c.line, column: c.column,
						expr: {
							kind: NodeKind.CallExpr, line: c.line, column: c.column,
							callee: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "bindText" },
							arguments: [
								{ kind: NodeKind.Identifier, line: c.line, column: c.column, name: "host" },
								{ kind: NodeKind.Identifier, line: c.line, column: c.column, name: tName },
								{
									kind: NodeKind.ArrowFunction, line: c.line, column: c.column,
									arrowParams: [], arrowParamTypes: [], arrowFlags: "", arrowReturnType: "",
									arrowBody: c.jsxExpr,
								},
							],
						},
					});
				}
				stmts.push({
					kind: NodeKind.ExprStmt, line: c.line, column: c.column,
					expr: {
						kind: NodeKind.CallExpr, line: c.line, column: c.column,
						callee: { kind: NodeKind.MemberExpr, line: c.line, column: c.column, object: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "host" }, property: "append", isOptional: false },
						arguments: [
							{ kind: NodeKind.Identifier, line: c.line, column: c.column, name: rName },
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
						cKids.push(gc);
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
							{ kind: NodeKind.Identifier, line: c.line, column: c.column, name: rName },
						],
					},
				});
			} else if (c.kind === NodeKind.JSXElement) {
				const kidName = emitEl(c);
				stmts.push({
					kind: NodeKind.ExprStmt, line: c.line, column: c.column,
					expr: {
						kind: NodeKind.CallExpr, line: c.line, column: c.column,
						callee: { kind: NodeKind.MemberExpr, line: c.line, column: c.column, object: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "host" }, property: "append", isOptional: false },
						arguments: [
							{ kind: NodeKind.Identifier, line: c.line, column: c.column, name: rName },
							{ kind: NodeKind.Identifier, line: c.line, column: c.column, name: kidName },
						],
					},
				});
			}
		}

		return rName;
	}

	const rootName = emitEl(node);
	if (styleOffenders.length > 0) {
		error("a style field cannot call a function — a signal read here would be a frozen snapshot, not reactive (reactive style fields land in S4)", styleOffenders[0]);
	}
	stmts.push({
		kind: NodeKind.ReturnStmt, line: L, column: C,
		argument: { kind: NodeKind.Identifier, line: L, column: C, name: rootName },
	});

	return {
		kind: NodeKind.ArrowFunction, line: L, column: C,
		arrowParams: ["host"], arrowParamTypes: ["Host"], arrowFlags: "", arrowReturnType: "",
		arrowBody: { kind: NodeKind.BlockStmt, line: L, column: C, statements: stmts },
	};
}
