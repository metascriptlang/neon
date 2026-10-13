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
// Platform blocks (§4 job 5, S4c) live under a `when` key, which holds every
// override the ENVIRONMENT selects and the caller passes nothing for — build
// target today, interaction states and breakpoints as they land. What the CALLER
// selects (`variants`) stays a bare data key. Grouping rather than the `_web`
// sigil of Panda/Chakra/Unistyles keeps the unconditional base style readable in
// one piece; that some conditions are cut at build time and others are not is an
// implementation fact and deliberately not visible in the spelling.
//
// The target's block merges over the base fields; every other block is dropped
// at expansion. What makes that possible is that `when` in a MACRO BODY is cut
// at parse time against the CONSUMER's defines, so the same macro source picks
// a different branch per target. Unistyles has no such lever and hands ios and
// android to RN's runtime Platform.select instead.
//
// The platform set is closed (`web`/`ios`/`android`/`macos`) because a macro
// cannot enumerate defines today. Opening it to arbitrary `-d:` flags needs the
// define table exposed to macro expansion — a compiler feature, filed not built.

import { Node, NodeKind, DeclKind, SourceLocation, isFloatLiteral, intValue, floatValue, stringValue, getImpl } from "std/meta";
import { Style } from "../../render/style";
import { STYLE_TABLE } from "../style/fields";

export function styleOf(s: Style): Style {
	return s;
}

function isPlatformName(k: string): boolean {
	return k === "web" || k === "ios" || k === "android" || k === "macos";
}

// CSS spelling of a style field. Kept beside applyCss (platform/browser/dom.ms)
// rather than shared with it: that one writes into the CSSOM, which takes
// camelCase names and per-property strings, while a stylesheet rule needs
// kebab-case text. tests/render/styleCss.test.ms pins the two against each
// other so the pair cannot drift apart silently.
function kebabCase(name: string): string {
	const lower = "abcdefghijklmnopqrstuvwxyz";
	let out = "";
	for (let i = 0; i < name.length; i += 1) {
		const c = name.charCodeAt(i);
		if (c >= 65 && c <= 90) {
			out = out + "-" + lower.charAt(c - 65);
		} else {
			out = out + name.charAt(i);
		}
	}
	return out;
}

// A bare number is points, which on the web is px — except for the ratios,
// which are unitless in CSS too.
function cssDecl(name: string, projection: string, folded: string, foldedIsNumber: boolean, numberToken: string): string {
	// A token stays a variable in the rule. That is the whole point of themes on
	// the web: the value lives in the theme's :root rule, so swapping a theme
	// changes one variable and never rewrites, re-hashes or re-registers this.
	//
	// The caller resolves the token and its type because a member read
	// (MemberExpr's `object`/`property`/`nodeType`) is visible only inside a
	// macro body — in a top-level helper a Node exposes just the common fields.
	//
	// The :root value carries no unit, so a length property multiplies it by 1px
	// here: CSS has no cast, and calc is the only way to give a bare number a
	// unit at the site that needs one.
	if (numberToken !== "") {
		if (projection === "num") {
			return kebabCase(name) + ":var(--" + numberToken + ");";
		}
		return kebabCase(name) + ":calc(var(--" + numberToken + ") * 1px);";
	}
	if (!foldedIsNumber && folded === "") { return ""; }
	const unit = foldedIsNumber && projection === "len" ? "px" : "";
	return kebabCase(name) + ":" + folded + unit + ";";
}

// djb2. The name must be stable across builds and identical on both backends,
// so it is computed here at expansion — never at runtime, where the two lanes
// could disagree on integer width.
function hashText(s: string): number {
	let h: int64 = 5381;
	for (let i = 0; i < s.length; i += 1) {
		h = (h * 33 + s.charCodeAt(i)) % 4294967296;
	}
	return h as number;
}

export macro createStyles(node: Node): Node {
	const sheet = node;
	if (sheet.kind !== NodeKind.ObjectLiteral) {
		error("createStyles takes an object literal: createStyles({ name: { ... } })", node);
	}
	when (js) {
		const activePlatform = "web";
	} else when (ios) {
		const activePlatform = "ios";
	} else when (android) {
		const activePlatform = "android";
	} else when (macos) {
		const activePlatform = "macos";
	} else {
		const activePlatform = "";
	}

	when (js) {
		const emitCss = true;
	} else {
		const emitCss = false;
	}
	when (debug) {
		const readableNames = true;
	} else {
		const readableNames = false;
	}

	let unfoldable = false;
	function themeToken(x: Node): string {
		if (x.kind !== NodeKind.MemberExpr) { return ""; }
		const obT = x.object.nodeType;
		if (obT === null || obT.kind !== NodeKind.TypeGeneric) { return ""; }
		const base = obT.typExprBase;
		if (base.kind !== NodeKind.Identifier || base.name !== "Theme") { return ""; }
		return x.property;
	}
	function typeName(x: Node): string {
		const t = x.nodeType;
		if (t === null || t.kind !== NodeKind.Identifier) { return ""; }
		return t.name;
	}
	function isIntType(x: Node): boolean {
		const t = typeName(x);
		return t === "int8" || t === "int16" || t === "int32" || t === "int64" || t === "uint8" || t === "uint16" || t === "uint32" || t === "uint64";
	}
	function constInitializer(x: Node): Node | null {
		if (x.kind !== NodeKind.Identifier) { return null; }
		const d = getImpl(x);
		if (d === null || d.kind !== NodeKind.VariableDecl || d.declKind !== DeclKind.Const) { return null; }
		return d.initializer;
	}
	function foldsToText(x: Node, depth: number): boolean {
		if (depth > 32) { return false; }
		if (x.kind === NodeKind.StringLiteral) { return true; }
		if (x.kind === NodeKind.MemberExpr) { return typeName(x) === "string"; }
		if (x.kind === NodeKind.BinaryExpr) { return x.operator === "+" && (foldsToText(x.left, depth + 1) || foldsToText(x.right, depth + 1)); }
		const init = constInitializer(x);
		return init !== null && foldsToText(init as Node, depth + 1);
	}
	function numberOf(x: Node, depth: number): float64 {
		if (depth > 32) { unfoldable = true; return 0; }
		if (x.kind === NodeKind.NumberLiteral) {
			return isFloatLiteral(x) ? floatValue(x) : (intValue(x) as float64);
		}
		if (x.kind === NodeKind.UnaryExpr && x.unaryOp === "-") {
			return -numberOf(x.operand, depth + 1);
		}
		if (x.kind === NodeKind.BinaryExpr) {
			const l = numberOf(x.left, depth + 1);
			const r = numberOf(x.right, depth + 1);
			if (x.operator === "+") { return l + r; }
			if (x.operator === "-") { return l - r; }
			if (x.operator === "*") { return l * r; }
			if (x.operator === "/" && r !== 0) {
				const q = l / r;
				if (!isIntType(x)) { return q; }
				return q < 0 ? Math.ceil(q) : Math.floor(q);
			}
			unfoldable = true;
			return 0;
		}
		const init = constInitializer(x);
		if (init === null) { unfoldable = true; return 0; }
		return numberOf(init as Node, depth + 1);
	}
	function textOf(x: Node, depth: number): string {
		if (depth > 32) { unfoldable = true; return ""; }
		if (x.kind === NodeKind.StringLiteral) { return stringValue(x); }
		if (x.kind === NodeKind.MemberExpr) {
			const tok = themeToken(x);
			if (tok === "") { unfoldable = true; return ""; }
			return "var(--" + tok + ")";
		}
		if (x.kind === NodeKind.BinaryExpr && x.operator === "+") {
			const l = foldsToText(x.left, depth + 1) ? textOf(x.left, depth + 1) : numberOf(x.left, depth + 1).toString();
			const r = foldsToText(x.right, depth + 1) ? textOf(x.right, depth + 1) : numberOf(x.right, depth + 1).toString();
			return l + r;
		}
		const init = constInitializer(x);
		if (init === null) { unfoldable = true; return ""; }
		return textOf(init as Node, depth + 1);
	}

	let entries: Node[] = [];
	for (let e = 0; e < sheet.properties.length; e += 1) {
		const v = sheet.properties[e];
		if (v.kind !== NodeKind.ObjectLiteral) {
			error("a sheet entry must be a static style object literal", v);
		}
		let fields: Node[] = [];
		let names: string[] = [];
		let locs: SourceLocation[] = [];
		let numberTokens: string[] = [];
		let overlay: Node | null = null;
		let vGroups: string[] = [];
		let vGroupOf: string[] = [];
		let vNames: string[] = [];
		let vBlocks: Node[] = [];
		for (let i = 0; i < v.properties.length; i += 1) {
			const fv = v.properties[i];
			const name = v.keys[i];
			if (name === "when") {
				if (fv.kind !== NodeKind.ObjectLiteral) {
					error("`when` takes a map of platform to style: when: { ios: { ... } }", fv);
				}
				for (let p = 0; p < fv.properties.length; p += 1) {
					const block = fv.properties[p];
					const platform = fv.keys[p];
					if (!isPlatformName(platform)) {
						error("unknown platform '" + platform + "' in a `when` block — available: web, ios, android, macos", block);
					}
					if (block.kind !== NodeKind.ObjectLiteral) {
						error("a platform block must be a style object literal", block);
					}
					if (platform === activePlatform) { overlay = block; }
				}
				continue;
			}
			// `variants` is the caller-selected axis (§2): the entry becomes an
			// arrow taking a selector, and each group merges its matched block
			// over the base at runtime. Selection is a one-off combination, so
			// the result takes the inline path like a merged layer array.
			if (name === "variants") {
				if (fv.kind !== NodeKind.ObjectLiteral) {
					error("`variants` takes named groups of style blocks: variants: { size: { sm: { ... } } }", fv);
				}
				for (let g = 0; g < fv.properties.length; g += 1) {
					const group = fv.properties[g];
					const groupName = fv.keys[g];
					if (group.kind !== NodeKind.ObjectLiteral) {
						error("a variant group maps names to style blocks: " + groupName + ": { sm: { ... } }", group);
					}
					vGroups.push(groupName);
					for (let m = 0; m < group.properties.length; m += 1) {
						const block = group.properties[m];
						if (block.kind !== NodeKind.ObjectLiteral) {
							error("a variant must be a style object literal", block);
						}
						for (let f = 0; f < block.properties.length; f += 1) {
							if (block.properties[f].kind === NodeKind.CallExpr) {
								error("a style field cannot call a function — a signal read here would be a frozen snapshot, not reactive (drive the selection at the use site instead: s.entry({ " + groupName + ": ... }))", block.properties[f]);
							}
						}
						vGroupOf.push(groupName);
						vNames.push(group.keys[m]);
						vBlocks.push(block);
					}
				}
				continue;
			}
			if (fv.kind === NodeKind.CallExpr) {
				error("a style field cannot call a function — a signal read here would be a frozen snapshot, not reactive (put reactive fields on the element: style={{ width: w() }})", fv);
			}
			// `theme.sp2` and `cfg.gap` are the same syntax, so a token is
			// recognized by TYPE: themeOf brands its result Theme<T>, which is
			// transparent everywhere else and survives here only as the name.
			fields.push(fv);
			names.push(name);
			locs.push(v.keyLocations[i]);
			numberTokens.push(foldsToText(fv, 0) ? "" : themeToken(fv));
		}
		if (overlay !== null) {
			const ov = overlay as Node;
			for (let j = 0; j < ov.properties.length; j += 1) {
				const pv = ov.properties[j];
				const pname = ov.keys[j];
				if (pv.kind === NodeKind.CallExpr) {
					error("a style field cannot call a function — a signal read here would be a frozen snapshot, not reactive (put reactive fields on the element: style={{ width: w() }})", pv);
				}
				const ptok = foldsToText(pv, 0) ? "" : themeToken(pv);
				let replaced = false;
				for (let b = 0; b < names.length; b += 1) {
					if (names[b] === pname) {
						fields[b] = pv;
						numberTokens[b] = ptok;
						replaced = true;
					}
				}
				if (!replaced) {
					fields.push(pv);
					names.push(pname);
					locs.push(ov.keyLocations[j]);
					numberTokens.push(ptok);
				}
			}
		}
		// A sheet entry is shared by every element that references it, so on a
		// host with a stylesheet it becomes one rule plus a class instead of a
		// field-by-field write per node. The rule text is baked here; the id is
		// content-hashed, so an unchanged entry keeps its name across builds and
		// an edited one lands under a new name (which is what lets a hot reload
		// swap rules without a frame of wrong styling).
		if (emitCss && fields.length > 0 && vGroups.length === 0) {
			let decls = "";
			let spelled = true;
			for (const row of STYLE_TABLE) {
				for (let b = 0; b < names.length; b += 1) {
					if (names[b] !== row[0]) { continue; }
					unfoldable = false;
					const isText = foldsToText(fields[b], 0);
					let folded = "";
					if (numberTokens[b] === "") {
						folded = isText ? textOf(fields[b], 0) : numberOf(fields[b], 0).toString();
					}
					if (unfoldable) { spelled = false; }
					decls = decls + cssDecl(names[b], row[2], folded, !isText, numberTokens[b]);
				}
			}
			if (spelled && decls !== "") {
				const readable = readableNames ? sheet.keys[e] + "_" : "";
				const id = "n_" + readable + hashText(decls).toString();
				const loc = locs[0];
				fields.push({
					kind: NodeKind.StringLiteral, line: v.line, column: v.column, value: id,
				});
				names.push("cssId");
				locs.push(loc);
				fields.push({
					kind: NodeKind.StringLiteral, line: v.line, column: v.column,
					value: "." + id + "{" + decls + "}",
				});
				names.push("css");
				locs.push(loc);
			}
		}
		const merged: Node = {
			kind: NodeKind.ObjectLiteral, line: v.line, column: v.column,
			properties: fields, keys: names, keyLocations: locs,
		};
		let entry: Node = {
			kind: NodeKind.CallExpr, line: v.line, column: v.column,
			callee: { kind: NodeKind.Identifier, line: v.line, column: v.column, name: "styleOf" },
			arguments: [merged],
		};
		if (vGroups.length > 0) {
			// mergeStyle(mergeStyle(base, <size chain>), <state chain>) where each
			// chain is sel.group === "name" ? styleOf({...}) : ... : emptyStyle().
			// styleOf on every block keeps the checker's excess-property check on
			// variant fields, at the block's own location.
			for (let g = 0; g < vGroups.length; g += 1) {
				const gname = vGroups[g];
				let chain: Node = {
					kind: NodeKind.CallExpr, line: v.line, column: v.column,
					callee: { kind: NodeKind.Identifier, line: v.line, column: v.column, name: "emptyStyle" },
					arguments: [],
				};
				for (let m = vNames.length - 1; m >= 0; m -= 1) {
					if (vGroupOf[m] !== gname) { continue; }
					const cond: Node = {
						kind: NodeKind.BinaryExpr, line: v.line, column: v.column, operator: "===",
						left: {
							kind: NodeKind.MemberExpr, line: v.line, column: v.column,
							object: { kind: NodeKind.Identifier, line: v.line, column: v.column, name: "sel" },
							property: gname, isOptional: false,
						},
						right: { kind: NodeKind.StringLiteral, line: v.line, column: v.column, value: vNames[m] },
					};
					chain = {
						kind: NodeKind.ConditionalExpr, line: v.line, column: v.column,
						ternaryCondition: cond,
						ternaryConsequent: {
							kind: NodeKind.CallExpr, line: v.line, column: v.column,
							callee: { kind: NodeKind.Identifier, line: v.line, column: v.column, name: "styleOf" },
							arguments: [vBlocks[m]],
						},
						ternaryAlternate: chain,
					};
				}
				entry = {
					kind: NodeKind.CallExpr, line: v.line, column: v.column,
					callee: { kind: NodeKind.Identifier, line: v.line, column: v.column, name: "mergeStyle" },
					arguments: [entry, chain],
				};
			}
			let selType = "{ ";
			for (let g = 0; g < vGroups.length; g += 1) {
				selType = selType + (g > 0 ? ", " : "") + vGroups[g] + "?: string";
			}
			selType = selType + " }";
			entry = {
				kind: NodeKind.ArrowFunction, line: v.line, column: v.column,
				arrowParams: ["sel"], arrowParamTypes: [selType], arrowBody: entry,
				arrowFlags: "", arrowReturnType: "",
			};
		}
		entries.push(entry);
	}
	return {
		kind: NodeKind.ObjectLiteral, line: node.line, column: node.column,
		properties: entries, keys: sheet.keys, keyLocations: sheet.keyLocations,
	};
}
