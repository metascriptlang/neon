// element macro — JSX → reactive NeonNode tree.
//
//   element(<div class="box"><p>Hi {name()}</p><button onPress={inc}>+</button></div>)
// expands to el("div", [attr("class","box")], [],
//                [ el("p", [], [], [text("Hi "), dynText(() => name())]),
//                  el("button", [], [evt("onPress", inc)], [text("+")]) ])
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
import { isReactiveExpr } from "./reactive";

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
	// as written, several become an array, and a JSX child passes RAW so the
	// converter lowers it against the prop's declared type (NeonView → the target's
	// emission, NeonNode → tree). Wrapping it in element() here would pre-pick tree
	// emission and break every view-typed child on js. Inline because node literals
	// only type-check inside a macro body (engine-mode Node view).
	const tagStart = node.jsxTag.charAt(0);
	if (tagStart >= "A" && tagStart <= "Z") {
		let keys: string[] = [];
		let values: Node[] = [];
		for (const a of node.jsxAttrs) {
			if (a.kind === NodeKind.JSXAttribute) {
				keys.push(a.jsxAttrName);
				if (a.jsxAttrValue.kind === NodeKind.StringLiteral
					|| a.jsxAttrValue.kind === NodeKind.NumberLiteral
					|| a.jsxAttrValue.kind === NodeKind.BooleanLiteral) {
					values.push(a.jsxAttrValue);
				} else if (a.jsxAttrValue.kind === NodeKind.ArrowFunction || a.jsxAttrValue.kind === NodeKind.FunctionExpr
					|| a.jsxAttrName === "ref"
					|| (a.jsxAttrName.startsWith("on") && a.jsxAttrName.charAt(2) >= "A" && a.jsxAttrName.charAt(2) <= "Z")) {
					// An arrow/function literal crosses RAW: the field's declared type
					// contextually types it (and pads its arity — bug118), so handler
					// props declare the FLAT handler type. Wrapping it in a synthesized
					// thunk instead both double-wraps (a thunk-valued prop would arrive
					// as a thunk OF a thunk) and miscompiles on C today (BUGS.md §2 —
					// engine-synthesized expr-bodied arrow around a user arrow).
					values.push(a.jsxAttrValue);
				} else {
					values.push({ kind: NodeKind.ArrowFunction, line: a.line, column: a.column, arrowParams: [], arrowParamTypes: [], arrowBody: a.jsxAttrValue, arrowFlags: "", arrowReturnType: "" });
				}
			}
		}
		let compKids: Node[] = [];
		let singleNeedsArray = false;
		for (const c of node.jsxChildren) {
			if (c.kind === NodeKind.JSXText) {
				// A raw JSXText does not survive the macro wire as a property value,
				// so a text child lowers HERE to text() — and a SINGLE one arrives
				// as [text()] (RN: strings live inside containers' children lists).
				const cleaned = cleanJsxText(c.jsxText);
				if (cleaned !== "") {
					compKids.push({
						kind: NodeKind.CallExpr, line: c.line, column: c.column,
						callee: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "text" },
						arguments: [{ kind: NodeKind.StringLiteral, line: c.line, column: c.column, value: cleaned }],
					});
					if (node.jsxChildren.length === 1) { singleNeedsArray = true; }
				}
			} else if (c.kind === NodeKind.JSXExpressionContainer) {
				// An ARROW child crosses raw — flow components (For/Show) declare
				// fn-typed children and the boundary types them. Any other
				// expression is reactive TEXT exactly as in lowercase tags:
				// dynText(() => expr) (Counter's count={n()} thunk shape, proven
				// on C), so <Text>Count: {count()}</Text> just works.
				const ex = c.jsxExpr;
				if (ex.kind === NodeKind.ArrowFunction || ex.kind === NodeKind.FunctionExpr) {
					compKids.push(ex);
				} else {
					compKids.push({
						kind: NodeKind.CallExpr, line: c.line, column: c.column,
						callee: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "dynText" },
						arguments: [{ kind: NodeKind.ArrowFunction, line: c.line, column: c.column, arrowParams: [], arrowParamTypes: [], arrowBody: ex, arrowFlags: "", arrowReturnType: "" }],
					});
					if (node.jsxChildren.length === 1) { singleNeedsArray = true; }
				}
			} else if (c.kind === NodeKind.JSXElement) {
				// The starter RN vocabulary (View/Text/Pressable/TextInput) mounts
				// children as NeonNode[], so a single element child arrives as
				// [element(…)] — built HERE because nested element() calls from a
				// MACRO re-expand (header) while ones nested in a converter result
				// do not. Every OTHER capitalized component keeps its own children
				// contract: a single element child crosses RAW and the boundary
				// lowers it (NeonView → jsxToView, NeonNode → jsxToNode) — Show's
				// element child, Card-style single-node props. Unifying these is
				// gated on the converter registry matching array targets exactly.
				const t = node.jsxTag;
				const isStarterTag = t === "View" || t === "Text" || t === "Pressable" || t === "TextInput";
				if (isStarterTag && node.jsxChildren.length === 1) {
					compKids.push({
						kind: NodeKind.MacroInvocation, line: c.line, column: c.column,
						macroName: "element", macroArgs: [c],
					});
					singleNeedsArray = true;
				} else {
					compKids.push(c);
				}
			}
		}
		if (compKids.length === 1 && singleNeedsArray) {
			keys.push("children");
			values.push({ kind: NodeKind.ArrayLiteral, line: node.line, column: node.column, elements: compKids });
		} else if (compKids.length === 1) {
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
	let refExpr: Node | null = null;
	let dynStyleAllExpr: Node | null = null;
	let dynStyleNames: string[] = [];
	let dynStyleExprs: Node[] = [];
	for (const a of node.jsxAttrs) {
		if (a.kind === NodeKind.JSXAttribute) {
			if (a.jsxAttrName === "ref") {
				refExpr = a.jsxAttrValue;
				continue;
			}
			if (a.jsxAttrName === "style" && a.jsxAttrValue.kind !== NodeKind.StringLiteral) {
				if (a.jsxAttrValue.kind === NodeKind.ObjectLiteral) {
					// S4: a reactive field peels off into its own per-property
					// effect (withDynStyle); the rest stays one static constant.
					const staticKeys: string[] = [];
					const staticProps: Node[] = [];
					for (let i = 0; i < a.jsxAttrValue.keys.length; i = i + 1) {
						const fv = a.jsxAttrValue.properties[i];
						if (isReactiveExpr(fv)) {
							dynStyleNames.push(a.jsxAttrValue.keys[i]);
							dynStyleExprs.push(fv);
						} else {
							staticKeys.push(a.jsxAttrValue.keys[i]);
							staticProps.push(fv);
						}
					}
					if (staticKeys.length > 0) {
						styleExpr = {
							kind: NodeKind.ObjectLiteral, line: a.line, column: a.column,
							properties: staticProps, keys: staticKeys,
						};
					}
					continue;
				}
				if (a.jsxAttrValue.kind === NodeKind.ArrayLiteral) {
					if (a.jsxAttrValue.elements.length === 0) {
						error("a style layer array needs at least one layer: style={[base, override]}", a.jsxAttrValue);
					}
					let allStatic = true;
					for (const layer of a.jsxAttrValue.elements) {
						if (layer.kind !== NodeKind.ObjectLiteral) { allStatic = false; }
					}
					if (allStatic) {
						const mergedKeys: string[] = [];
						const mergedValues: Node[] = [];
						for (const layer of a.jsxAttrValue.elements) {
							for (let i = 0; i < layer.keys.length; i = i + 1) {
								const fv = layer.properties[i];
								if (isReactiveExpr(fv)) {
									error("a reactive style field inside a layer array is not supported yet — pass it in a plain object style: style={{ " + layer.keys[i] + ": ... }}", fv);
								}
								// mergeStyle treats null as unset, so a later null must
								// not erase an earlier layer's value.
								if (fv.kind === NodeKind.NullLiteral) { continue; }
								const k = layer.keys[i];
								let at = -1;
								for (let j = 0; j < mergedKeys.length; j = j + 1) {
									if (mergedKeys[j] === k) { at = j; }
								}
								if (at >= 0) { mergedValues[at] = fv; } else { mergedKeys.push(k); mergedValues.push(fv); }
							}
						}
						styleExpr = {
							kind: NodeKind.ObjectLiteral, line: a.line, column: a.column,
							properties: mergedValues, keys: mergedKeys,
						};
						continue;
					}
					// Dynamic layers reach layerStyles at runtime, where a reactive
					// field would freeze silently — reject it here instead.
					for (const layer of a.jsxAttrValue.elements) {
						if (layer.kind === NodeKind.ObjectLiteral) {
							for (let i = 0; i < layer.keys.length; i = i + 1) {
								if (isReactiveExpr(layer.properties[i])) {
									error("a reactive style field inside a layer array is not supported yet — pass it in a plain object style: style={{ " + layer.keys[i] + ": ... }}", layer.properties[i]);
								}
							}
						}
					}
					styleExpr = {
						kind: NodeKind.CallExpr, line: a.line, column: a.column,
						callee: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "layerStyles" },
						arguments: [a.jsxAttrValue],
					};
					continue;
				}
				// A style expression that reads a signal (call-based rule, §6)
				// must not freeze into withStyle's one-shot constant — it gets
				// one whole-style effect instead. A static expression through
				// here (a sheet entry) keeps the constant path and its class id.
				if (isReactiveExpr(a.jsxAttrValue)) {
					dynStyleAllExpr = a.jsxAttrValue;
				} else {
					styleExpr = a.jsxAttrValue;
				}
				continue;
			}
			const nameLit: Node = { kind: NodeKind.StringLiteral, line: a.line, column: a.column, value: a.jsxAttrName };
			if (a.jsxAttrName.startsWith("on")) {
				// RN surface: onChangeText hands the handler the TEXT — wrap the user
				// handler so the Host contract stays (e: NeonEvent) => void everywhere.
				// Param is __msCte so a handler reading an outer `e` is never shadowed.
				// Inline (not a helper): flat Node fields only type inside macro bodies.
				let hVal: Node = a.jsxAttrValue;
				if (a.jsxAttrName === "onChangeText") {
					hVal = { kind: NodeKind.ArrowFunction, line: a.line, column: a.column, arrowParams: ["__msCte"], arrowParamTypes: [""], arrowFlags: "", arrowReturnType: "", arrowBody: { kind: NodeKind.CallExpr, line: a.line, column: a.column, callee: a.jsxAttrValue, arguments: [{ kind: NodeKind.MemberExpr, line: a.line, column: a.column, object: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "__msCte" }, property: "value", isOptional: false }] } };
				}
				events.push({
					kind: NodeKind.CallExpr, line: a.line, column: a.column,
					callee: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "evt" },
					arguments: [nameLit, hVal],
				});
			} else if (a.jsxAttrValue.kind === NodeKind.StringLiteral) {
				attrs.push({
					kind: NodeKind.CallExpr, line: a.line, column: a.column,
					callee: { kind: NodeKind.Identifier, line: a.line, column: a.column, name: "attr" },
					arguments: [nameLit, a.jsxAttrValue],
				});
			} else if (!isReactiveExpr(a.jsxAttrValue)) {
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
			kids.push(!isReactiveExpr(c.jsxExpr) ? {
				kind: NodeKind.CallExpr, line: c.line, column: c.column,
				callee: { kind: NodeKind.Identifier, line: c.line, column: c.column, name: "insChild" },
				arguments: [c.jsxExpr],
			} : {
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

	let acc: Node = elCall;
	if (refExpr !== null) {
		acc = {
			kind: NodeKind.CallExpr, line: node.line, column: node.column,
			callee: { kind: NodeKind.Identifier, line: node.line, column: node.column, name: "withRef" },
			arguments: [acc, refExpr as Node],
		};
	}
	if (styleExpr !== null) {
		acc = {
			kind: NodeKind.CallExpr, line: node.line, column: node.column,
			callee: { kind: NodeKind.Identifier, line: node.line, column: node.column, name: "withStyle" },
			arguments: [acc, styleExpr as Node],
		};
	}
	if (dynStyleAllExpr !== null) {
		acc = {
			kind: NodeKind.CallExpr, line: node.line, column: node.column,
			callee: { kind: NodeKind.Identifier, line: node.line, column: node.column, name: "withDynStyleAll" },
			arguments: [acc,
				{
					kind: NodeKind.ArrowFunction, line: node.line, column: node.column,
					arrowParams: [], arrowParamTypes: [], arrowBody: dynStyleAllExpr as Node, arrowFlags: "", arrowReturnType: "",
				}],
		};
	}
	for (let i = 0; i < dynStyleNames.length; i = i + 1) {
		acc = {
			kind: NodeKind.CallExpr, line: node.line, column: node.column,
			callee: { kind: NodeKind.Identifier, line: node.line, column: node.column, name: "withDynStyle" },
			arguments: [acc,
				{ kind: NodeKind.StringLiteral, line: node.line, column: node.column, value: dynStyleNames[i] },
				{
					kind: NodeKind.ArrowFunction, line: node.line, column: node.column,
					arrowParams: [], arrowParamTypes: [], arrowBody: dynStyleExprs[i], arrowFlags: "", arrowReturnType: "",
				}],
		};
	}
	return acc;
}
