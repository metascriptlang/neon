// element macro — JSX → reactive NeonNode tree.
//
//   element(<div class="box"><p>Hi {name()}</p><button onClick={inc}>+</button></div>)
// expands to el("div", [attr("class","box")], [],
//                [ el("p", [], [], [text("Hi "), dynText(() => name())]),
//                  el("button", [], [evt("onClick", inc)], [text("+")]) ])
//
// el/attr/dynAttr/evt/text/dynText come from "../render/node" and must be in scope
// at the call site. Attributes whose name starts with "on" become events; a string
// literal attr stays static (attr); any other attr expression becomes a reactive
// thunk (dynAttr), mirroring how expression children become dynText; nested JSX
// re-expands through `element`.
//
// `style` is the one attribute with two channels: a string literal keeps the legacy
// attr path (host parses it), while any other expression is a typed Style and routes
// through withStyle() into NeonNode.style — which then also needs withStyle in scope.

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
	// Capitalized tag → createComponent(Tag, { props }). V1 prop contract: a string
	// literal passes through, every expression prop becomes a thunk (the component's
	// props interface declares () => T); children stay structural — one child passes
	// as written, several become an array, a lone expression container passes raw
	// (For/Index row templates). Inline because node literals only type-check
	// inside a macro body (engine-mode Node view).
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
			values.push({ kind: NodeKind.ArrayLiteral, line: node.line, column: node.column, elements: compKids });
		}
		return {
			kind: NodeKind.CallExpr, line: node.line, column: node.column,
			callee: { kind: NodeKind.Identifier, line: node.line, column: node.column, name: "createComponent" },
			arguments: [
				{ kind: NodeKind.Identifier, line: node.line, column: node.column, name: node.jsxTag },
				{ kind: NodeKind.ObjectLiteral, line: node.line, column: node.column, properties: values, keys: keys },
			],
		};
	}
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
			if (a.jsxAttrName.startsWith("on")) {
				events.push({
					kind: NodeKind.CallExpr, line: a.line, column: a.column,
					callee: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "evt" },
					arguments: [nameLit, a.jsxAttrValue],
				});
			} else if (a.jsxAttrValue.kind === NodeKind.StringLiteral) {
				attrs.push({
					kind: NodeKind.CallExpr, line: a.line, column: a.column,
					callee: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "attr" },
					arguments: [nameLit, a.jsxAttrValue],
				});
			} else {
				attrs.push({
					kind: NodeKind.CallExpr, line: a.line, column: a.column,
					callee: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "dynAttr" },
					arguments: [nameLit, {
						kind: NodeKind.ArrowFunction, line: a.line, column: a.column,
						arrowParams: [], arrowParamTypes: [], arrowBody: a.jsxAttrValue, arrowFlags: "", arrowReturnType: "",
					}],
				});
			}
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
