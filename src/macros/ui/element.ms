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

import { Node, NodeKind } from "std/meta";

export macro element(node: Node): Node {
	let attrs: Node[] = [];
	let events: Node[] = [];
	for (const a of node.jsxAttrs) {
		if (a.kind === NodeKind.JSXAttribute) {
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
			kids.push({
				kind: NodeKind.CallExpr, line: c.line, column: c.column,
				callee: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "text" },
				arguments: [{ kind: NodeKind.StringLiteral, line: c.line, column: c.column, value: c.jsxText }],
			});
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

	return {
		kind: NodeKind.CallExpr, line: node.line, column: node.column,
		callee: { kind: NodeKind.Identifier, line: node.line, column: node.column, name: "el" },
		arguments: [
			{ kind: NodeKind.StringLiteral, line: node.line, column: node.column, value: node.jsxTag },
			{ kind: NodeKind.ArrayLiteral, line: node.line, column: node.column, elements: attrs },
			{ kind: NodeKind.ArrayLiteral, line: node.line, column: node.column, elements: events },
			{ kind: NodeKind.ArrayLiteral, line: node.line, column: node.column, elements: kids },
		],
	};
}
