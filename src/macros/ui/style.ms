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
// rejected at expansion. Reactive fields live on the JSX site instead (S4a,
// element.ms → withDynStyle), where each one gets its own effect.
//
// Platform blocks (§4 job 5, S4c) are underscore-prefixed keys, the spelling
// Unistyles 3.0 ships for `_web`. The target's block is merged over the base
// fields and every other block is dropped, so a non-target style is not dead
// weight in the binary — it never exists. `when` in a macro body is cut at parse
// time against the CONSUMER's defines, which is what makes that possible here
// and is why Unistyles has to resolve ios/android at runtime instead.

import { Node, NodeKind, SourceLocation } from "std/meta";
import { Style } from "../../render/style";

export function styleOf(s: Style): Style {
	return s;
}

function isPlatformKey(k: string): boolean {
	return k === "_web" || k === "_ios" || k === "_android" || k === "_macos";
}

export macro createStyles(node: Node): Node {
	if (node.kind !== NodeKind.ObjectLiteral) {
		error("createStyles takes an object literal: createStyles({ name: { ... } })", node);
	}
	when (js) {
		const activeKey = "_web";
	} else when (ios) {
		const activeKey = "_ios";
	} else when (android) {
		const activeKey = "_android";
	} else when (macos) {
		const activeKey = "_macos";
	} else {
		const activeKey = "";
	}

	let entries: Node[] = [];
	for (const v of node.properties) {
		if (v.kind !== NodeKind.ObjectLiteral) {
			error("a sheet entry must be a static style object literal", v);
		}
		let fields: Node[] = [];
		let names: string[] = [];
		let locs: SourceLocation[] = [];
		let overlay: Node | null = null;
		for (let i = 0; i < v.properties.length; i += 1) {
			const fv = v.properties[i];
			const name = v.keys[i];
			if (isPlatformKey(name)) {
				if (fv.kind !== NodeKind.ObjectLiteral) {
					error("a platform block must be a style object literal: _web: { ... }", fv);
				}
				if (name === activeKey) { overlay = fv; }
				continue;
			}
			if (fv.kind === NodeKind.CallExpr) {
				error("a style field cannot call a function — a signal read here would be a frozen snapshot, not reactive (put reactive fields on the element: style={{ width: w() }})", fv);
			}
			fields.push(fv);
			names.push(name);
			locs.push(v.keyLocations[i]);
		}
		if (overlay !== null) {
			const ov = overlay as Node;
			for (let j = 0; j < ov.properties.length; j += 1) {
				const pv = ov.properties[j];
				const pname = ov.keys[j];
				if (pv.kind === NodeKind.CallExpr) {
					error("a style field cannot call a function — a signal read here would be a frozen snapshot, not reactive (put reactive fields on the element: style={{ width: w() }})", pv);
				}
				let replaced = false;
				for (let b = 0; b < names.length; b += 1) {
					if (names[b] === pname) {
						fields[b] = pv;
						replaced = true;
					}
				}
				if (!replaced) {
					fields.push(pv);
					names.push(pname);
					locs.push(ov.keyLocations[j]);
				}
			}
		}
		const merged: Node = {
			kind: NodeKind.ObjectLiteral, line: v.line, column: v.column,
			properties: fields, keys: names, keyLocations: locs,
		};
		entries.push({
			kind: NodeKind.CallExpr, line: v.line, column: v.column,
			callee: { kind: NodeKind.Identifier, line: v.line, column: v.column, name: "styleOf" },
			arguments: [merged],
		});
	}
	return {
		kind: NodeKind.ObjectLiteral, line: node.line, column: node.column,
		properties: entries, keys: node.keys, keyLocations: node.keyLocations,
	};
}
