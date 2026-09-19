// element macro — JSX → a NeonNode: `(host, parent, before) => void`, a function
// that performs the host ops itself (docs/RENDER-MODEL.md). Nested lowercase
// elements flatten INLINE into the one mount block (D3): a single statement
// list, temps numbered across the whole tree (_r0/_r1/... elements, _t0/...
// dynamic texts, _k0/... component children, _s0/... style temps), child subtree
// emitted depth-first then appended to its parent — no per-level closure, no
// per-level call. A subtree with a static skeleton is built once and cloned per
// mount instead (D4, src/render/template.ms).
//
// Component tags, Show and For do NOT flatten: their structure changes at
// runtime, so they stay runtime calls through createComponent.
//
// The emitted code calls bindText / bindAttr / createComponent / mountChild /
// place / text / dynText by name and types its params as Host / HostNode, so all
// of those must be in scope at the call site. Attr classification: string
// literal → setAttr once, on* → addEvent, any other expr → one createEffect
// around setAttr (1 dynamic spot = 1 effect); a non-literal style splits by
// shape: object literal → static fields once + bindStyleProp per reactive field,
// layer array → compile-time merge or layerStyles (a reactive layer or field is
// rejected), reactive expr → bindStyleAll, anything else → applyStaticStyle.

import { Node, NodeKind, DeclKind, NodeFlag } from "std/meta";
import { isReactiveExpr, isRawPropValue, isEventName, peelHidden } from "./reactive";

function trimEdgeSpaces(s: string, fromStart: boolean, fromEnd: boolean): string {
	let lo = 0;
	let hi = s.length;
	if (fromStart) {
		while (lo < hi && s.charAt(lo) === " ") { lo = lo + 1; }
	}
	if (fromEnd) {
		while (hi > lo && s.charAt(hi - 1) === " ") { hi = hi - 1; }
	}
	return s.slice(lo, hi);
}

// JSX whitespace rule (Babel cleanJSXElementLiteralChild): a text child that
// spans lines has each line's indentation stripped and is rejoined with single
// spaces; a whitespace-only one collapses to "" and is dropped by the caller.
// Text with no newline is significant and passes through untouched.
export function cleanJsxText(raw: string): string {
	let hasNewline = false;
	let i = 0;
	while (i < raw.length) {
		const ch = raw.charAt(i);
		if (ch === "\n" || ch === "\r") { hasNewline = true; break; }
		i = i + 1;
	}
	if (!hasNewline) { return raw; }

	const lines: string[] = [];
	let cur = "";
	i = 0;
	while (i < raw.length) {
		const ch = raw.charAt(i);
		if (ch === "\n") { lines.push(cur); cur = ""; }
		else if (ch === "\t") { cur = cur + " "; }
		else if (ch !== "\r") { cur = cur + ch; }
		i = i + 1;
	}
	lines.push(cur);

	let lastNonEmpty = -1;
	i = 0;
	while (i < lines.length) {
		if (trimEdgeSpaces(lines[i], true, true) !== "") { lastNonEmpty = i; }
		i = i + 1;
	}

	let out = "";
	i = 0;
	while (i < lines.length) {
		const line = trimEdgeSpaces(lines[i], i !== 0, i !== lines.length - 1);
		if (line !== "") {
			out = i !== lastNonEmpty ? out + line + " " : out + line;
		}
		i = i + 1;
	}
	return out;
}

export macro element(node: Node): Node {
	const L = node.line;
	const C = node.column;
	function kidsOf(n: Node): Node[] {
		return n.kind === NodeKind.JSXFragment ? n.jsxFragChildren : n.jsxChildren;
	}
	function peelTypeRef(t: Node): Node {
		let cur = t;
		while (cur.kind === NodeKind.TypeGeneric) {
			const b = cur.typExprBase;
			if (b.kind !== NodeKind.Identifier) { return cur; }
			if (b.name !== "Ref" && b.name !== "Borrow" && b.name !== "Cursor" && b.name !== "Lent") { return cur; }
			if (cur.typExprArgs.length !== 1) { return cur; }
			cur = cur.typExprArgs[0];
		}
		return cur;
	}
	function isAccessorType(t: Node): boolean {
		if (t.kind !== NodeKind.TypeGeneric) { return false; }
		const b = t.typExprBase;
		return b.kind === NodeKind.Identifier && b.name === "Accessor";
	}
	function unionHasNull(t: Node): boolean {
		if (t.kind !== NodeKind.TypeUnion) { return false; }
		for (const m of t.typExprMembers) {
			if (m.kind === NodeKind.Identifier && m.name === "null") { return true; }
		}
		return false;
	}
	function clonePath(e: Node): Node | null {
		const p = peelHidden(e);
		if (p.kind === NodeKind.Identifier) {
			return { kind: NodeKind.Identifier, line: p.line, column: p.column, name: p.name };
		}
		if (p.kind === NodeKind.MemberExpr) {
			const base = clonePath(p.object);
			if (base === null) { return null; }
			return { kind: NodeKind.MemberExpr, line: p.line, column: p.column, object: base as Node, property: p.property, isOptional: false };
		}
		return null;
	}
	function expandAttrs(list: Node[]): Node[] {
		let names: string[] = [];
		let out: Node[] = [];
		for (const a of list) {
			if (a.kind === NodeKind.JSXAttribute) {
				let at = -1;
				for (let i = 0; i < names.length; i = i + 1) { if (names[i] === a.jsxAttrName) { at = i; } }
				if (at >= 0) { out[at] = a; } else { names.push(a.jsxAttrName); out.push(a); }
				continue;
			}
			if (a.kind !== NodeKind.JSXSpreadAttribute) { continue; }
			const arg = a.jsxSpreadArg;
			const argType = arg.nodeType;
			if (argType === null) {
				error("a spread needs a typed object: annotate the value being spread", a as Node);
				continue;
			}
			const t = peelTypeRef(argType as Node);
			if (t.kind !== NodeKind.TypeObject || t.typExprFieldNames.length === 0) {
				error("a spread needs an object type with named fields — a map or an index signature has no names to read at compile time", a as Node);
				continue;
			}
			if (clonePath(arg) === null) {
				error("a spread needs a variable or a field, not an expression: it is read once per prop", a as Node);
				continue;
			}
			for (let i = 0; i < t.typExprFieldNames.length; i = i + 1) {
				const fname = t.typExprFieldNames[i];
				const ftype = t.typExprFieldTypes[i];
				if (fname === "children") {
					error("children cannot come from a spread: pass it as a child of the element", a as Node);
					continue;
				}
				const isEvent = isEventName(fname);
				if (isEvent && unionHasNull(ftype)) {
					error("a nullable " + fname + " handler is not supported yet: give the prop a non-null handler", a as Node);
					continue;
				}
				if (fname === "style" && unionHasNull(ftype)) {
					error("a nullable style is not supported yet: pass an empty style instead of null", a as Node);
					continue;
				}
				let value: Node = {
					kind: NodeKind.MemberExpr, line: a.line, column: a.column,
					object: clonePath(arg) as Node, property: fname, isOptional: false,
				};
				if (isAccessorType(ftype)) {
					value = { kind: NodeKind.CallExpr, line: a.line, column: a.column, callee: value, arguments: [] };
				}
				const attrNode: Node = {
					kind: NodeKind.JSXAttribute, line: a.line, column: a.column,
					jsxAttrName: fname, jsxAttrValue: value,
				};
				let at = -1;
				for (let j = 0; j < names.length; j = j + 1) { if (names[j] === fname) { at = j; } }
				if (at >= 0) { out[at] = attrNode; } else { names.push(fname); out.push(attrNode); }
			}
		}
		return out;
	}
	function flattenFragments(n: Node): Node {
		let out: Node[] = [];
		for (const c of kidsOf(n)) {
			if (c.kind === NodeKind.JSXFragment) {
				for (const g of kidsOf(flattenFragments(c))) { out.push(g); }
			} else if (c.kind === NodeKind.JSXElement) {
				out.push(flattenFragments(c));
			} else {
				out.push(c);
			}
		}
		if (n.kind === NodeKind.JSXFragment) {
			return { kind: NodeKind.JSXFragment, line: n.line, column: n.column, jsxFragChildren: out };
		}
		return { kind: NodeKind.JSXElement, line: n.line, column: n.column, jsxTag: n.jsxTag, jsxAttrs: expandAttrs(n.jsxAttrs), jsxChildren: out, jsxSelfClosing: n.jsxSelfClosing };
	}
	function isAccessorTyped(n: Node): boolean {
		const t = peelHidden(n).nodeType;
		if (t !== null && t.kind === NodeKind.TypeGeneric) {
			const base = t.typExprBase;
			return base.kind === NodeKind.Identifier && base.name === "Accessor";
		}
		return false;
	}
	function isNumberTyped(n: Node): boolean {
		const t = peelHidden(n).nodeType;
		if (t === null) { return false; }
		let payload: Node = t as Node;
		if (payload.kind === NodeKind.TypeGeneric && payload.typExprArgs.length === 1) {
			const base = payload.typExprBase;
			if (base.kind === NodeKind.Identifier && base.name === "Accessor") { payload = payload.typExprArgs[0]; }
		}
		if (payload.kind !== NodeKind.Identifier) { return false; }
		const name = payload.name;
		return name === "number" || name === "float32" || name === "float64"
			|| name === "int8" || name === "int16" || name === "int32" || name === "int64"
			|| name === "uint8" || name === "uint16" || name === "uint32" || name === "uint64";
	}
	function asText(n: Node): Node {
		if (!isNumberTyped(n)) { return n; }
		return {
			kind: NodeKind.CallExpr, line: n.line, column: n.column,
			callee: { kind: NodeKind.MemberExpr, line: n.line, column: n.column, object: n, property: "toString", isOptional: false },
			arguments: [],
		};
	}
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

	let errNodes: Node[] = [];
	let errMsgs: string[] = [];
	let optIdx = 0;
	function presentKind(n: Node): string {
		const t = peelHidden(n).nodeType;
		if (t === null || t.kind !== NodeKind.TypeUnion) { return ""; }
		let hasNull = false;
		let kind = "value";
		for (const m of t.typExprMembers) {
			if (m.kind === NodeKind.Identifier && m.name === "null") { hasNull = true; }
			if (m.kind === NodeKind.TypeGeneric) {
				const base = m.typExprBase;
				if (base.kind === NodeKind.Identifier && base.name === "Accessor") { kind = "accessor"; }
			}
		}
		return hasNull ? kind : "";
	}
	function pushIfPresent(into: Node[], name: string, value: Node, then: Node, otherwise: Node[], ln: int32, col: int32): void {
		into.push({
			kind: NodeKind.VariableDecl, line: ln, column: col,
			declName: name, declType: "", declKind: DeclKind.Const,
			initializer: value,
		});
		into.push({
			kind: NodeKind.IfStmt, line: ln, column: col,
			condition: {
				kind: NodeKind.BinaryExpr, line: ln, column: col, operator: "!==",
				left: { kind: NodeKind.Identifier, line: ln, column: col, name: name },
				right: { kind: NodeKind.NullLiteral, line: ln, column: col },
			},
			consequent: {
				kind: NodeKind.BlockStmt, line: ln, column: col,
				statements: [{ kind: NodeKind.ExprStmt, line: ln, column: col, expr: then }],
			},
			alternate: { kind: NodeKind.BlockStmt, line: ln, column: col, statements: otherwise },
		});
	}
	function pushWhenPresent(into: Node[], callee: Node, lead: Node[], value: Node, otherwise: Node[], ln: int32, col: int32): void {
		const name = "_o" + optIdx.toString();
		optIdx = optIdx + 1;
		const args: Node[] = [];
		for (const l of lead) { args.push(l); }
		args.push({ kind: NodeKind.Identifier, line: ln, column: col, name: name });
		pushIfPresent(into, name, value, { kind: NodeKind.CallExpr, line: ln, column: col, callee: callee, arguments: args }, otherwise, ln, col);
	}
	function pushAttrWhenPresent(into: Node[], elName: string, attrName: string, value: Node, otherwise: Node[], ln: int32, col: int32): void {
		const name = "_o" + optIdx.toString();
		optIdx = optIdx + 1;
		const read: Node = {
			kind: NodeKind.CallExpr, line: ln, column: col,
			callee: { kind: NodeKind.TypeAssertion, line: ln, column: col, asExpr: { kind: NodeKind.Identifier, line: ln, column: col, name: name }, asType: "() => string" },
			arguments: [],
		};
		const bind: Node = {
			kind: NodeKind.CallExpr, line: ln, column: col,
			callee: { kind: NodeKind.Identifier, line: ln, column: col, name: "bindAttr" },
			arguments: [
				{ kind: NodeKind.Identifier, line: ln, column: col, name: "host" },
				{ kind: NodeKind.Identifier, line: ln, column: col, name: elName },
				{ kind: NodeKind.StringLiteral, line: ln, column: col, value: attrName },
				{ kind: NodeKind.ArrowFunction, line: ln, column: col, arrowParams: [], arrowParamTypes: [], arrowFlags: "", arrowReturnType: "", arrowBody: read },
			],
		};
		pushIfPresent(into, name, value, bind, otherwise, ln, col);
	}
	const optChangeTextMsg = "a nullable onChangeText handler is not supported yet — pass a handler that is always present";
	function pushStyleConst(into: Node[], init: Node, nodeVar: string, tempName: string, ln: int32, col: int32): void {
		into.push({
			kind: NodeKind.VariableDecl, line: ln, column: col,
			declName: tempName, declType: "Style", declKind: DeclKind.Const,
			initializer: init,
		});
		into.push({
			kind: NodeKind.ExprStmt, line: ln, column: col,
			expr: {
				kind: NodeKind.CallExpr, line: ln, column: col,
				callee: { kind: NodeKind.MemberExpr, line: ln, column: col, object: { kind: NodeKind.Identifier, line: ln, column: col, name: "host" }, property: "setStyle", isOptional: false },
				arguments: [
					{ kind: NodeKind.Identifier, line: ln, column: col, name: nodeVar },
					{ kind: NodeKind.Identifier, line: ln, column: col, name: tempName },
				],
			},
		});
	}
	function pushStyleLayers(into: Node[], sv: Node, nodeVar: string, tempName: string, ln: int32, col: int32): void {
		if (sv.elements.length === 0) {
			errNodes.push(sv);
			errMsgs.push("a style layer array needs at least one layer: style={[base, override]}");
			return;
		}
		let allStatic = true;
		for (const layer of sv.elements) {
			if (layer.kind !== NodeKind.ObjectLiteral) {
				if (isReactiveExpr(layer) || isAccessorTyped(layer)) {
					errNodes.push(layer);
					errMsgs.push("a reactive style layer is not supported yet — merge it in a whole-style expression instead: style={layerStyles([base, pick()])}");
					return;
				}
				allStatic = false;
				continue;
			}
			for (let i = 0; i < layer.keys.length; i = i + 1) {
				const fv = layer.properties[i];
				if (isReactiveExpr(fv) || isAccessorTyped(fv)) {
					errNodes.push(fv);
					errMsgs.push("a reactive style field inside a layer array is not supported yet — pass it in a plain object style: style={{ " + layer.keys[i] + ": ... }}");
					return;
				}
			}
		}
		if (!allStatic) {
			pushStyleConst(into, {
				kind: NodeKind.CallExpr, line: ln, column: col,
				callee: { kind: NodeKind.Identifier, line: ln, column: col, name: "layerStyles" },
				arguments: [sv],
			}, nodeVar, tempName, ln, col);
			return;
		}
		const mergedKeys: string[] = [];
		const mergedValues: Node[] = [];
		for (const layer of sv.elements) {
			for (let i = 0; i < layer.keys.length; i = i + 1) {
				const fv = layer.properties[i];
				if (fv.kind === NodeKind.NullLiteral) { continue; }
				const k = layer.keys[i];
				let at = -1;
				for (let j = 0; j < mergedKeys.length; j = j + 1) {
					if (mergedKeys[j] === k) { at = j; }
				}
				if (at >= 0) { mergedValues[at] = fv; } else { mergedKeys.push(k); mergedValues.push(fv); }
			}
		}
		pushStyleConst(into, { kind: NodeKind.ObjectLiteral, line: ln, column: col, properties: mergedValues, keys: mergedKeys }, nodeVar, tempName, ln, col);
	}
	function pushStyleObject(into: Node[], sv: Node, nodeVar: string, tempName: string, ln: int32, col: int32): void {
		const staticKeys: string[] = [];
		const staticProps: Node[] = [];
		const dynNames: string[] = [];
		const dynExprs: Node[] = [];
		for (let i = 0; i < sv.keys.length; i = i + 1) {
			const fv = sv.properties[i];
			if (isReactiveExpr(fv) || isAccessorTyped(fv)) {
				dynNames.push(sv.keys[i]);
				dynExprs.push(fv);
			} else {
				staticKeys.push(sv.keys[i]);
				staticProps.push(fv);
			}
		}
		pushStyleConst(into, staticKeys.length > 0
			? { kind: NodeKind.ObjectLiteral, line: ln, column: col, properties: staticProps, keys: staticKeys }
			: { kind: NodeKind.CallExpr, line: ln, column: col, callee: { kind: NodeKind.Identifier, line: ln, column: col, name: "emptyStyle" }, arguments: [] },
			nodeVar, tempName, ln, col);
		for (let i = 0; i < dynNames.length; i = i + 1) {
			into.push({
				kind: NodeKind.ExprStmt, line: ln, column: col,
				expr: {
					kind: NodeKind.CallExpr, line: ln, column: col,
					callee: { kind: NodeKind.Identifier, line: ln, column: col, name: "bindStyleProp" },
					arguments: [
						{ kind: NodeKind.Identifier, line: ln, column: col, name: "host" },
						{ kind: NodeKind.Identifier, line: ln, column: col, name: nodeVar },
						{ kind: NodeKind.Identifier, line: ln, column: col, name: tempName },
						{ kind: NodeKind.StringLiteral, line: ln, column: col, value: dynNames[i] },
						{
							kind: NodeKind.ArrowFunction, line: ln, column: col,
							arrowParams: [], arrowParamTypes: [], arrowFlags: "", arrowReturnType: "",
							arrowBody: dynExprs[i],
						},
					],
				},
			});
		}
	}
	function isNodeType(t: Node): boolean {
		if (t.kind !== NodeKind.TypeFunction || t.typExprParams.length !== 3) { return false; }
		const names = t.typExprParamNames;
		return names.length === 3 && names[0] === "host" && names[1] === "parent" && names[2] === "before";
	}
	function isNodeArrayTyped(n: Node): boolean {
		const t = peelHidden(n).nodeType;
		if (t === null) { return false; }
		if (t.kind === NodeKind.TypeArray) { return isNodeType(t.typExprElement); }
		if (t.kind !== NodeKind.TypeGeneric || t.typExprArgs.length !== 1) { return false; }
		const arg = t.typExprArgs[0];
		if (arg.kind === NodeKind.TypeArray) { return isNodeType(arg.typExprElement); }
		return false;
	}
	function isNodeTyped(n: Node): boolean {
		const t = peelHidden(n).nodeType;
		return t !== null && isNodeType(t as Node);
	}
	function isNullableNodeTyped(n: Node): boolean {
		const t = peelHidden(n).nodeType;
		if (t === null || t.kind !== NodeKind.TypeUnion) { return false; }
		let hasNull = false;
		let hasNode = false;
		for (const m of t.typExprMembers) {
			if (m.kind === NodeKind.Identifier && m.name === "null") { hasNull = true; }
			else if (isNodeType(m)) { hasNode = true; }
			else { return false; }
		}
		return hasNull && hasNode;
	}
	function isNodeValued(n: Node): boolean {
		return isNodeTyped(n) || isNodeArrayTyped(n) || isNullableNodeTyped(n);
	}
	function isFunctionValued(n: Node): boolean {
		if (n.kind === NodeKind.ArrowFunction || n.kind === NodeKind.FunctionExpr) { return true; }
		const t = peelHidden(n).nodeType;
		return t !== null && t.kind === NodeKind.TypeFunction;
	}
	function isRawChild(n: Node): boolean {
		return isFunctionValued(n);
	}
	function isReactiveSelection(n: Node): boolean {
		const p = peelHidden(n);
		if (p.kind === NodeKind.ConditionalExpr) { return isReactiveExpr(p.ternaryCondition); }
		if (p.kind === NodeKind.BinaryExpr && (p.operator === "&&" || p.operator === "||" || p.operator === "??")) {
			return isReactiveExpr(p.left);
		}
		return false;
	}
	function showOf(when: Node, child: Node, fallback: Node | null, ln: int32, col: int32): Node {
		let attrs: Node[] = [{ kind: NodeKind.JSXAttribute, line: ln, column: col, jsxAttrName: "when", jsxAttrValue: when }];
		if (fallback !== null) {
			attrs.push({ kind: NodeKind.JSXAttribute, line: ln, column: col, jsxAttrName: "fallback", jsxAttrValue: fallback as Node });
		}
		return { kind: NodeKind.JSXElement, line: ln, column: col, jsxTag: "Show", jsxAttrs: attrs, jsxChildren: [child], jsxSelfClosing: false };
	}
	function forOf(each: Node, row: Node, ln: int32, col: int32): Node {
		return {
			kind: NodeKind.JSXElement, line: ln, column: col, jsxTag: "For",
			jsxAttrs: [{ kind: NodeKind.JSXAttribute, line: ln, column: col, jsxAttrName: "each", jsxAttrValue: each }],
			jsxChildren: [{ kind: NodeKind.JSXExpressionContainer, line: ln, column: col, jsxExpr: row }],
			jsxSelfClosing: false,
		};
	}
	function isJsx(n: Node): boolean {
		return n.kind === NodeKind.JSXElement || n.kind === NodeKind.JSXFragment;
	}
	function lowerFlowTree(elNode: Node): Node {
		let kids: Node[] = [];
		for (const c of kidsOf(elNode)) {
			let lowered: Node | null = null;
			if (isJsx(c)) {
				lowered = lowerFlowTree(c);
			} else if (c.kind === NodeKind.JSXExpressionContainer) {
				const ex = peelHidden(c.jsxExpr);
				if (ex.kind === NodeKind.BinaryExpr && ex.operator === "&&") {
					const rhs = peelHidden(ex.right);
					if (isJsx(rhs)) { lowered = showOf(ex.left, lowerFlowTree(rhs), null, c.line, c.column); }
				} else if (ex.kind === NodeKind.ConditionalExpr) {
					const yes = peelHidden(ex.ternaryConsequent);
					const no = peelHidden(ex.ternaryAlternate);
					if (isJsx(yes) && isJsx(no)) {
						lowered = showOf(ex.ternaryCondition, lowerFlowTree(yes), lowerFlowTree(no), c.line, c.column);
					} else if (isJsx(yes) && no.kind === NodeKind.NullLiteral) {
						lowered = showOf(ex.ternaryCondition, lowerFlowTree(yes), null, c.line, c.column);
					} else if (yes.kind === NodeKind.NullLiteral && isJsx(no)) {
						const not: Node = { kind: NodeKind.UnaryExpr, line: c.line, column: c.column, unaryOp: "!", operand: ex.ternaryCondition };
						lowered = showOf(not, lowerFlowTree(no), null, c.line, c.column);
					}
				} else if (ex.kind === NodeKind.CallExpr && ex.arguments.length === 1) {
					const callee = peelHidden(ex.callee);
					const row = peelHidden(ex.arguments[0]);
					if (callee.kind === NodeKind.MemberExpr && callee.property === "map" && isFunctionValued(row)) {
						lowered = forOf(peelHidden(callee.object), row, c.line, c.column);
					}
				}
			}
			if (lowered !== null) { const picked = lowered as Node; kids.push(picked); } else { kids.push(c); }
		}
		if (elNode.kind === NodeKind.JSXFragment) {
			return { kind: NodeKind.JSXFragment, line: elNode.line, column: elNode.column, jsxFragChildren: kids };
		}
		return { kind: NodeKind.JSXElement, line: elNode.line, column: elNode.column, jsxTag: elNode.jsxTag, jsxAttrs: elNode.jsxAttrs, jsxChildren: kids, jsxSelfClosing: elNode.jsxSelfClosing };
	}
	node = flattenFragments(lowerFlowTree(node));

	const reactiveNodeMsg = "a NeonNode child picked by a reactive condition would mount once and never switch — use <Show> or a JSX branch: {cond() ? <A/> : <B/>}";

	// Capitalized tag → createComponent(Tag, { props }). Prop contract: every value
	// prop — literal or expression — becomes accessor(() => v) (the component's props
	// interface declares Accessor<T>); arrow literals, ref and on* cross RAW. Children
	// arrive as ONE NeonNode: an arrow or a NeonNode value crosses as written, anything
	// else lowers through element. Inline because node literals only type-check inside a macro body
	// (engine-mode Node view).
	function componentCall(c: Node): Node {
		let keys: string[] = [];
		let values: Node[] = [];
		for (const a of c.jsxAttrs) {
			if (a.kind === NodeKind.JSXAttribute) {
				keys.push(a.jsxAttrName);
				if (isRawPropValue(a.jsxAttrName, a.jsxAttrValue) || isAccessorTyped(a.jsxAttrValue)) {
					values.push(a.jsxAttrValue);
				} else {
					values.push({ kind: NodeKind.CallExpr, line: a.line, column: a.column, callee: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "accessor" }, arguments: [{ kind: NodeKind.ArrowFunction, line: a.line, column: a.column, arrowParams: [], arrowParamTypes: [], arrowBody: a.jsxAttrValue, arrowFlags: "", arrowReturnType: "" }] });
				}
			}
		}
		const tag = c.jsxTag;
		let significant: Node[] = [];
		for (const k of c.jsxChildren) {
			if (!(k.kind === NodeKind.JSXText && cleanJsxText(k.jsxText) === "")) { significant.push(k); }
		}
		if (significant.length === 1 && significant[0].kind === NodeKind.JSXExpressionContainer && isRawChild(significant[0].jsxExpr)) {
			const only = significant[0].jsxExpr;
			if (isNodeTyped(only) && isReactiveSelection(only)) { errNodes.push(only); errMsgs.push(reactiveNodeMsg); }
			keys.push("children");
			values.push(only);
		} else if (significant.length === 1 && significant[0].kind === NodeKind.JSXElement) {
			keys.push("children");
			values.push({ kind: NodeKind.MacroInvocation, line: significant[0].line, column: significant[0].column, macroName: "element", macroArgs: [significant[0]] });
		} else if (significant.length > 0) {
			keys.push("children");
			values.push({
				kind: NodeKind.MacroInvocation, line: c.line, column: c.column, macroName: "element",
				macroArgs: [{ kind: NodeKind.JSXFragment, line: c.line, column: c.column, jsxFragChildren: c.jsxChildren }],
			});
		}
		// A dotted tag (Ctx.Provider) resolves through member access, not a flat
		// name: fold the parts so the checker sees Ctx.Provider and types the call
		// through the field's declared component type.
		let tagRef: Node = { kind: NodeKind.Identifier, line: c.line, column: c.column, name: tag };
		if (tag.indexOf(".") >= 0) {
			const parts: string[] = tag.split(".");
			tagRef = { kind: NodeKind.Identifier, line: c.line, column: c.column, name: parts[0] };
			for (let i = 1; i < parts.length; i = i + 1) {
				tagRef = { kind: NodeKind.MemberExpr, line: c.line, column: c.column, object: tagRef, property: parts[i], isOptional: false };
			}
		}
		return {
			kind: NodeKind.CallExpr, line: c.line, column: c.column,
			callee: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "createComponent" },
			arguments: [
				tagRef,
				{ kind: NodeKind.ObjectLiteral, line: c.line, column: c.column, properties: values, keys: keys },
			],
		};
	}
	function isComponentTag(c: Node): boolean {
		const first = c.jsxTag.charAt(0);
		return first >= "A" && first <= "Z";
	}
	if (node.kind === NodeKind.JSXElement && isComponentTag(node)) {
		const call = componentCall(node);
		if (errNodes.length > 0) { error(errMsgs[0], errNodes[0]); }
		return call;
	}

	// ---- D4 template mode ----
	// A subtree of nothing but lowercase elements, text, attrs, events and style
	// has a STATIC skeleton: build it once, duplicate it per mount, and walk to
	// the dynamic spots along a path computed here at compile time. Component
	// tags and regions change structure at runtime, so a subtree containing one
	// keeps the D3 flat emission below, unchanged.
	function isPureSubtree(el: Node): boolean {
		for (const c of el.jsxChildren) {
			if (c.kind === NodeKind.JSXExpressionContainer && isNodeValued(c.jsxExpr)) { return false; }
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
				if (isEventName(a.jsxAttrName) || a.jsxAttrName === "ref") { return true; }
				if (a.jsxAttrValue.kind !== NodeKind.StringLiteral) { return true; }
			}
		}
		for (const c of el.jsxChildren) {
			if (c.kind === NodeKind.JSXExpressionContainer) { return true; }
			if (c.kind === NodeKind.JSXElement && needsHandle(c)) { return true; }
		}
		return false;
	}

	if (node.kind === NodeKind.JSXElement && isPureSubtree(node)) {
		let bStmts: Node[] = [];
		let wStmts: Node[] = [];
		let bIdx = 0;
		let pIdx = 1;
		let tsIdx = 0;

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
					if (isEventName(a.jsxAttrName)) { continue; }
					if (a.jsxAttrName === "ref") { continue; }
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
			let wRef: Node | null = null;
			for (const a of el.jsxAttrs) {
				if (a.kind === NodeKind.JSXAttribute) {
					if (a.jsxAttrName === "ref") {
						wRef = a.jsxAttrValue;
						continue;
					}
					if (a.jsxAttrName === "style" && a.jsxAttrValue.kind !== NodeKind.StringLiteral) {
						const sv = a.jsxAttrValue;
						if (sv.kind === NodeKind.ObjectLiteral) {
							pushStyleObject(wStmts, sv, elVar, "_ts" + tsIdx.toString(), a.line, a.column);
							tsIdx = tsIdx + 1;
						} else if (sv.kind === NodeKind.ArrayLiteral) {
							pushStyleLayers(wStmts, sv, elVar, "_ts" + tsIdx.toString(), a.line, a.column);
							tsIdx = tsIdx + 1;
						} else if (!isReactiveExpr(sv) && presentKind(sv) !== "") {
							pushWhenPresent(wStmts, ident(presentKind(sv) === "accessor" ? "bindStyleAll" : "applyStaticStyle", a.line, a.column), [ident("host", a.line, a.column), ident(elVar, a.line, a.column)], sv, [], a.line, a.column);
						} else if (isReactiveExpr(sv) || isAccessorTyped(sv)) {
							wStmts.push({
								kind: NodeKind.ExprStmt, line: a.line, column: a.column,
								expr: {
									kind: NodeKind.CallExpr, line: a.line, column: a.column,
									callee: ident("bindStyleAll", a.line, a.column),
									arguments: [
										ident("host", a.line, a.column),
										ident(elVar, a.line, a.column),
										{
											kind: NodeKind.ArrowFunction, line: a.line, column: a.column,
											arrowParams: [], arrowParamTypes: [], arrowFlags: "", arrowReturnType: "",
											arrowBody: sv,
										},
									],
								},
							});
						} else {
							const sName = "_ts" + tsIdx.toString();
							tsIdx = tsIdx + 1;
							wStmts.push({
								kind: NodeKind.VariableDecl, line: a.line, column: a.column,
								declName: sName, declType: "", declKind: DeclKind.Const,
								initializer: sv,
							});
							wStmts.push({
								kind: NodeKind.ExprStmt, line: a.line, column: a.column,
								expr: {
									kind: NodeKind.CallExpr, line: a.line, column: a.column,
									callee: ident("applyStaticStyle", a.line, a.column),
									arguments: [ident("host", a.line, a.column), ident(elVar, a.line, a.column), ident(sName, a.line, a.column)],
								},
							});
						}
					} else if (isEventName(a.jsxAttrName) && presentKind(a.jsxAttrValue) !== "") {
						if (a.jsxAttrName === "onChangeText") {
							errNodes.push(a.jsxAttrValue);
							errMsgs.push(optChangeTextMsg);
						} else {
							pushWhenPresent(wStmts, { kind: NodeKind.MemberExpr, line: a.line, column: a.column, object: ident("host", a.line, a.column), property: "addEvent", isOptional: false }, [ident(elVar, a.line, a.column), strLit(a.jsxAttrName, a.line, a.column)], a.jsxAttrValue, [], a.line, a.column);
						}
					} else if (isEventName(a.jsxAttrName)) {
						// onChangeText text-unwrap — mirrors element.ms, see the comment there.
						let hVal: Node = a.jsxAttrValue;
						if (a.jsxAttrName === "onChangeText") {
							hVal = { kind: NodeKind.ArrowFunction, line: a.line, column: a.column, arrowParams: ["__msCte"], arrowParamTypes: [""], arrowFlags: "", arrowReturnType: "", arrowBody: { kind: NodeKind.CallExpr, line: a.line, column: a.column, callee: a.jsxAttrValue, arguments: [{ kind: NodeKind.MemberExpr, line: a.line, column: a.column, object: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "__msCte" }, property: "value", isOptional: false }] } };
						}
						wStmts.push({
							kind: NodeKind.ExprStmt, line: a.line, column: a.column,
							expr: hostCall("host", "addEvent", [ident(elVar, a.line, a.column), strLit(a.jsxAttrName, a.line, a.column), hVal], a.line, a.column),
						});
					} else if (presentKind(a.jsxAttrValue) === "accessor") {
						pushAttrWhenPresent(wStmts, elVar, a.jsxAttrName, a.jsxAttrValue, [{
							kind: NodeKind.ExprStmt, line: a.line, column: a.column,
							expr: hostCall("host", "removeAttr", [ident(elVar, a.line, a.column), strLit(a.jsxAttrName, a.line, a.column)], a.line, a.column),
						}], a.line, a.column);
					} else if (a.jsxAttrValue.kind !== NodeKind.StringLiteral) {
						wStmts.push({
							kind: NodeKind.ExprStmt, line: a.line, column: a.column,
							expr: !isReactiveExpr(a.jsxAttrValue) && !isAccessorTyped(a.jsxAttrValue) ? {
								kind: NodeKind.CallExpr, line: a.line, column: a.column,
								callee: ident("writeAttr", a.line, a.column),
								arguments: [ident("host", a.line, a.column), ident(elVar, a.line, a.column), strLit(a.jsxAttrName, a.line, a.column), a.jsxAttrValue],
							} : {
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
							expr: !isReactiveExpr(c.jsxExpr) && !isAccessorTyped(c.jsxExpr) ? hostCall("host", "setText", [ident(curVar, c.line, c.column), asText(c.jsxExpr)], c.line, c.column) : {
								kind: NodeKind.CallExpr, line: c.line, column: c.column,
								callee: ident("bindText", c.line, c.column),
								arguments: [
									ident("host", c.line, c.column),
									ident(curVar, c.line, c.column),
									{
										kind: NodeKind.ArrowFunction, line: c.line, column: c.column,
										arrowParams: [], arrowParamTypes: [], arrowFlags: "", arrowReturnType: "",
										arrowBody: asText(c.jsxExpr),
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

			if (wRef !== null && presentKind(wRef as Node) !== "") {
				pushWhenPresent(wStmts, ident("applyRef", el.line, el.column), [ident(elVar, el.line, el.column)], wRef as Node, [], el.line, el.column);
			} else if (wRef !== null) {
				wStmts.push({
					kind: NodeKind.ExprStmt, line: el.line, column: el.column,
					expr: {
						kind: NodeKind.CallExpr, line: el.line, column: el.column,
						callee: ident("applyRef", el.line, el.column),
						arguments: [ident(elVar, el.line, el.column), wRef as Node],
					},
				});
			}
		}

		const tplRoot = emitBuild(node);
		emitWire(node, "_p0");
		if (errNodes.length > 0) { error(errMsgs[0], errNodes[0]); }
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

	function pushInsert(parentVar: string, child: Node, atRoot: boolean, ln: int32, col: int32): void {
		stmts.push({
			kind: NodeKind.ExprStmt, line: ln, column: col,
			expr: atRoot ? {
				kind: NodeKind.CallExpr, line: ln, column: col,
				callee: ident("place", ln, col),
				arguments: [ident("host", ln, col), ident(parentVar, ln, col), child, ident("before", ln, col)],
			} : hostCall("host", "append", [ident(parentVar, ln, col), child], ln, col),
		});
	}

	function emitKids(list: Node[], parentVar: string, atRoot: boolean): void {
		for (const c of list) {
			const beforeArg: Node = atRoot ? ident("before", c.line, c.column) : { kind: NodeKind.NullLiteral, line: c.line, column: c.column };
			if (c.kind === NodeKind.JSXText) {
				const cleaned = cleanJsxText(c.jsxText);
				if (cleaned !== "") {
					pushInsert(parentVar, hostCall("host", "createText", [strLit(cleaned, c.line, c.column)], c.line, c.column), atRoot, c.line, c.column);
				}
			} else if (c.kind === NodeKind.JSXExpressionContainer) {
				const nodeValued = isNodeValued(c.jsxExpr);
				if (nodeValued && isReactiveSelection(c.jsxExpr)) { errNodes.push(c.jsxExpr); errMsgs.push(reactiveNodeMsg); }
				const liveSpot = !nodeValued && (isReactiveExpr(c.jsxExpr) || isAccessorTyped(c.jsxExpr));
				if (isNullableNodeTyped(c.jsxExpr)) {
					pushWhenPresent(stmts, ident("mountChild", c.line, c.column), [ident("host", c.line, c.column), ident(parentVar, c.line, c.column), beforeArg], c.jsxExpr, [], c.line, c.column);
					continue;
				}
				if (!liveSpot) {
					stmts.push({
						kind: NodeKind.ExprStmt, line: c.line, column: c.column,
						expr: {
							kind: NodeKind.CallExpr, line: c.line, column: c.column,
							callee: ident("mountChild", c.line, c.column),
							arguments: [ident("host", c.line, c.column), ident(parentVar, c.line, c.column), beforeArg, asText(c.jsxExpr)],
						},
					});
					continue;
				}
				const tName = "_t" + tIdx.toString();
				tIdx = tIdx + 1;
				stmts.push({
					kind: NodeKind.VariableDecl, line: c.line, column: c.column,
					declName: tName, declType: "", declKind: DeclKind.Const,
					initializer: hostCall("host", "createText", [strLit("", c.line, c.column)], c.line, c.column),
				});
				stmts.push({
					kind: NodeKind.ExprStmt, line: c.line, column: c.column,
					expr: {
						kind: NodeKind.CallExpr, line: c.line, column: c.column,
						callee: ident("bindText", c.line, c.column),
						arguments: [
							ident("host", c.line, c.column),
							ident(tName, c.line, c.column),
							{
								kind: NodeKind.ArrowFunction, line: c.line, column: c.column,
								arrowParams: [], arrowParamTypes: [], arrowFlags: "", arrowReturnType: "",
								arrowBody: asText(c.jsxExpr),
							},
						],
					},
				});
				pushInsert(parentVar, ident(tName, c.line, c.column), atRoot, c.line, c.column);
			} else if (c.kind === NodeKind.JSXElement && isComponentTag(c)) {
				const kName = "_k" + kIdx.toString();
				kIdx = kIdx + 1;
				stmts.push({
					kind: NodeKind.VariableDecl, line: c.line, column: c.column,
					declName: kName, declType: "", declKind: DeclKind.Const,
					initializer: componentCall(c),
				});
				stmts.push({
					kind: NodeKind.ExprStmt, line: c.line, column: c.column,
					expr: {
						kind: NodeKind.CallExpr, line: c.line, column: c.column,
						callee: ident(kName, c.line, c.column),
						arguments: [ident("host", c.line, c.column), ident(parentVar, c.line, c.column), beforeArg],
					},
				});
			} else if (c.kind === NodeKind.JSXElement) {
				const el = c;
				const rName = "_r" + rIdx.toString();
				let refFor: Node | null = null;
				rIdx = rIdx + 1;
				stmts.push({
					kind: NodeKind.VariableDecl, line: el.line, column: el.column,
					declName: rName, declType: "", declKind: DeclKind.Const,
					initializer: hostCall("host", "createElement", [strLit(el.jsxTag, el.line, el.column)], el.line, el.column),
				});

				for (const a of el.jsxAttrs) {
					if (a.kind === NodeKind.JSXAttribute) {
						if (a.jsxAttrName === "ref") {
							refFor = a.jsxAttrValue;
							continue;
						}
						if (a.jsxAttrName === "style" && a.jsxAttrValue.kind !== NodeKind.StringLiteral) {
							const sv = a.jsxAttrValue;
							if (sv.kind === NodeKind.ObjectLiteral) {
								pushStyleObject(stmts, sv, rName, "_s" + sIdx.toString(), a.line, a.column);
								sIdx = sIdx + 1;
								continue;
							}
							if (sv.kind === NodeKind.ArrayLiteral) {
								pushStyleLayers(stmts, sv, rName, "_s" + sIdx.toString(), a.line, a.column);
								sIdx = sIdx + 1;
								continue;
							}
							if (!isReactiveExpr(sv) && presentKind(sv) !== "") {
								pushWhenPresent(stmts, { kind: NodeKind.Identifier, line: a.line, column: a.column, name: presentKind(sv) === "accessor" ? "bindStyleAll" : "applyStaticStyle" }, [{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: "host" }, { kind: NodeKind.Identifier, line: a.line, column: a.column, name: rName }], sv, [], a.line, a.column);
								continue;
							}
							if (isReactiveExpr(sv) || isAccessorTyped(sv)) {
								stmts.push({
									kind: NodeKind.ExprStmt, line: a.line, column: a.column,
									expr: {
										kind: NodeKind.CallExpr, line: a.line, column: a.column,
										callee: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "bindStyleAll" },
										arguments: [
											{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: "host" },
											{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: rName },
											{
												kind: NodeKind.ArrowFunction, line: a.line, column: a.column,
												arrowParams: [], arrowParamTypes: [], arrowFlags: "", arrowReturnType: "",
												arrowBody: sv,
											},
										],
									},
								});
								continue;
							}
							// Bind the style expr to a temp before the call: BUGS.md §2 call-result
							// arg at an address-taken position (same reason as the _e child temps).
							const sName = "_s" + sIdx.toString();
							sIdx = sIdx + 1;
							stmts.push({
								kind: NodeKind.VariableDecl, line: a.line, column: a.column,
								declName: sName, declType: "", declKind: DeclKind.Const,
								initializer: sv,
							});
							stmts.push({
								kind: NodeKind.ExprStmt, line: a.line, column: a.column,
								expr: {
									kind: NodeKind.CallExpr, line: a.line, column: a.column,
									callee: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "applyStaticStyle" },
									arguments: [
										{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: "host" },
										{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: rName },
										{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: sName },
									],
								},
							});
							continue;
						}
						const nameLit: Node = { kind: NodeKind.StringLiteral, line: a.line, column: a.column, value: a.jsxAttrName };
						if (isEventName(a.jsxAttrName) && presentKind(a.jsxAttrValue) !== "") {
							if (a.jsxAttrName === "onChangeText") {
								errNodes.push(a.jsxAttrValue);
								errMsgs.push(optChangeTextMsg);
							} else {
								pushWhenPresent(stmts, { kind: NodeKind.MemberExpr, line: a.line, column: a.column, object: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "host" }, property: "addEvent", isOptional: false }, [{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: rName }, nameLit], a.jsxAttrValue, [], a.line, a.column);
							}
						} else if (isEventName(a.jsxAttrName)) {
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
						} else if (presentKind(a.jsxAttrValue) === "accessor") {
							pushAttrWhenPresent(stmts, rName, a.jsxAttrName, a.jsxAttrValue, [], a.line, a.column);
						} else {
							stmts.push({
								kind: NodeKind.ExprStmt, line: a.line, column: a.column,
								expr: !isReactiveExpr(a.jsxAttrValue) && !isAccessorTyped(a.jsxAttrValue) ? {
									kind: NodeKind.CallExpr, line: a.line, column: a.column,
									callee: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "writeAttr" },
									arguments: [
										{ kind: NodeKind.Identifier, line: a.line, column: a.column, name: "host" },
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

				emitKids(el.jsxChildren, rName, false);

				if (refFor !== null && presentKind(refFor as Node) !== "") {
					pushWhenPresent(stmts, { kind: NodeKind.Identifier, line: el.line, column: el.column, name: "applyRef" }, [{ kind: NodeKind.Identifier, line: el.line, column: el.column, name: rName }], refFor as Node, [], el.line, el.column);
				} else if (refFor !== null) {
					stmts.push({
						kind: NodeKind.ExprStmt, line: el.line, column: el.column,
						expr: {
							kind: NodeKind.CallExpr, line: el.line, column: el.column,
							callee: { kind: NodeKind.Identifier, line: el.line, column: el.column, name: "applyRef" },
							arguments: [{ kind: NodeKind.Identifier, line: el.line, column: el.column, name: rName }, refFor as Node],
						},
					});
				}

				pushInsert(parentVar, ident(rName, el.line, el.column), atRoot, el.line, el.column);
			}
		}
	}

	emitKids(node.kind === NodeKind.JSXFragment ? node.jsxFragChildren : [node], "parent", true);
	if (errNodes.length > 0) { error(errMsgs[0], errNodes[0]); }

	return {
		kind: NodeKind.ArrowFunction, line: L, column: C,
		arrowParams: ["host", "parent", "before"], arrowParamTypes: ["Host", "HostNode", "HostNode | null"], arrowFlags: "", arrowReturnType: "void",
		arrowBody: { kind: NodeKind.BlockStmt, line: L, column: C, statements: stmts },
	};
}
