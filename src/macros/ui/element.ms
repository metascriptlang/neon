// element macro — JSX → reactive VNode tree.
//
//   element(<div class="box"><p>Hi {name()}</p><button onClick={inc}>+</button></div>)
// expands to el("div", [attr("class","box")], [],
//                [ el("p", [], [], [text("Hi "), dynText(() => name())]),
//                  el("button", [], [evt("onClick", inc)], [text("+")]) ])
//
// el/attr/evt/text/dynText come from "../render/node" and must be in scope at the
// call site. Attributes whose name starts with "on" become events; expression
// containers become reactive (dynText); nested JSX re-expands through `element`.
//
// `style` is the one attribute with two channels: a string literal keeps the legacy
// attr path (host parses it), while any other expression is a typed Style and routes
// through withStyle() into VNode.style — which then also needs withStyle in scope.

import { Node, NodeKind } from "std/meta";

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
function cleanJsxText(raw: string): string {
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
	let attrs: Node[] = [];
	let events: Node[] = [];
	let styleExpr: Node | null = null;
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
				styleExpr = a.jsxAttrValue;
				continue;
			}
			const nameLit: Node = { kind: NodeKind.StringLiteral, line: a.line, column: a.column, value: a.jsxAttrName };
			const ctor = a.jsxAttrName.startsWith("on") ? "evt" : "attr";
			const call: Node = {
				kind: NodeKind.CallExpr, line: a.line, column: a.column,
				callee: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: ctor },
				arguments: [nameLit, a.jsxAttrValue],
			};
			if (ctor === "evt") { events.push(call); } else { attrs.push(call); }
		}
	}

	let kids: Node[] = [];
	for (const c of node.jsxChildren) {
		if (c.kind === NodeKind.JSXText) {
			const cleaned = cleanJsxText(c.jsxText);
			if (cleaned !== "") {
				kids.push({
					kind: NodeKind.CallExpr, line: c.line, column: c.column,
					callee: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "text" },
					arguments: [{ kind: NodeKind.StringLiteral, line: c.line, column: c.column, value: cleaned }],
				});
			}
		} else if (c.kind === NodeKind.JSXExpressionContainer) {
			kids.push({
				kind: NodeKind.CallExpr, line: c.line, column: c.column,
				callee: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "dynText" },
				arguments: [{
					kind: NodeKind.ArrowFunction, line: c.line, column: c.column,
					arrowParams: [], arrowParamTypes: [], arrowBody: c.jsxExpr, arrowFlags: "", arrowReturnType: "",
				}],
			});
		} else if (c.kind === NodeKind.JSXElement) {
			kids.push({
				kind: NodeKind.CallExpr, line: c.line, column: c.column,
				callee: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "element" },
				arguments: [c],
			});
		}
	}

	const elCall: Node = {
		kind: NodeKind.CallExpr, line: node.line, column: node.column,
		callee: { kind: NodeKind.Identifier, line: node.line, column: node.column, name: "el" },
		arguments: [
			{ kind: NodeKind.StringLiteral, line: node.line, column: node.column, value: node.jsxTag },
			{ kind: NodeKind.ArrayLiteral, line: node.line, column: node.column, elements: attrs },
			{ kind: NodeKind.ArrayLiteral, line: node.line, column: node.column, elements: events },
			{ kind: NodeKind.ArrayLiteral, line: node.line, column: node.column, elements: kids },
		],
	};

	if (styleExpr === null) { return elCall; }
	return {
		kind: NodeKind.CallExpr, line: node.line, column: node.column,
		callee: { kind: NodeKind.Identifier, line: node.line, column: node.column, name: "withStyle" },
		arguments: [elCall, styleExpr as Node],
	};
}
