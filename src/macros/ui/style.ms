// createStyles — typed style sheets (docs/STYLE.md §4).
//
// A macro, not a function: it rewrites each sheet entry into a styleOf(...) call,
//
//   createStyles({ box: { width: 200 }, row: { height: 20 } })
//   → { box: styleOf({ width: 200 }), row: styleOf({ height: 20 }) }
//
// so every entry literal is checked against Style at the call arg (a typo like
// `widht` is a checker error with the field name and location) and the sheet's
// fields carry the named Style type — no hand-written sheet interface needed,
// and entry-name typos report "Available: box, row". styleOf must be in scope
// at the call site, same convention as the element macro's el/attr/text.
//
// S1 sheets are static data: an entry that is not an object literal, or a field
// whose value is a call (a signal read would freeze into a silent snapshot), is
// rejected at expansion until S4 lands reactive style fields.

import { Node, NodeKind } from "std/meta";
import { Style } from "../../render/style";

export function styleOf(s: Style): Style {
	return s;
}

export macro createStyles(node: Node): Node {
	if (node.kind !== NodeKind.ObjectLiteral) {
		error("createStyles takes an object literal: createStyles({ name: { ... } })", node);
	}
	let entries: Node[] = [];
	for (const v of node.properties) {
		if (v.kind !== NodeKind.ObjectLiteral) {
			error("a sheet entry must be a static style object literal", v);
		}
		for (const fv of v.properties) {
			if (fv.kind === NodeKind.CallExpr) {
				error("a style field cannot call a function — a signal read here would be a frozen snapshot, not reactive (reactive style fields land in S4)", fv);
			}
		}
		entries.push({
			kind: NodeKind.CallExpr, line: v.line, column: v.column,
			callee: { kind: NodeKind.Identifier, line: v.line, column: v.column, name: "styleOf" },
			arguments: [v],
		});
	}
	return {
		kind: NodeKind.ObjectLiteral, line: node.line, column: node.column,
		properties: entries, keys: node.keys, keyLocations: node.keyLocations,
	};
}
