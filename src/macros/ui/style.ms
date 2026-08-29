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

import { Node, NodeKind, SourceLocation, isFloatLiteral, intValue, floatValue, stringValue } from "std/meta";
import { Style } from "../../render/style";

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
function isUnitless(name: string): boolean {
	return name === "flex" || name === "flexGrow" || name === "flexShrink"
		|| name === "aspectRatio" || name === "opacity";
}

function cssDecl(name: string, v: Node, token: string): string {
	// A token stays a variable in the rule. That is the whole point of themes on
	// the web: the value lives in the theme's :root rule, so swapping a theme
	// changes one variable and never rewrites, re-hashes or re-registers this.
	//
	// The caller resolves the token name because a variant field (MemberExpr's
	// `object`/`property`) reads only inside a macro body — in a top-level helper
	// a Node exposes just the common fields.
	if (token !== "") {
		return kebabCase(name) + ":var(--" + token + ");";
	}
	if (v.kind === NodeKind.NumberLiteral) {
		// Two accessors, not one: the macro VM picks typed opcodes from the static
		// type, so a `number`-returning reader computes on the wrong field for
		// whichever of int/float it wasn't compiled for.
		const n = isFloatLiteral(v) ? floatValue(v).toString() : intValue(v).toString();
		const unit = isUnitless(name) ? "" : "px";
		return kebabCase(name) + ":" + n + unit + ";";
	}
	if (v.kind === NodeKind.StringLiteral) {
		return kebabCase(name) + ":" + stringValue(v) + ";";
	}
	return "";
}

// djb2. The name must be stable across builds and identical on both backends,
// so it is computed here at expansion — never at runtime, where the two lanes
// could disagree on integer width.
function hashText(s: string): number {
	let h = 5381;
	for (let i = 0; i < s.length; i += 1) {
		h = (h * 33 + s.charCodeAt(i)) % 4294967296;
	}
	return h;
}

export macro createStyles(node: Node): Node {
	// `createStyles(theme => ({ ... }))`: the arrow is a MARKER, not a runtime
	// function. It only names the identifier that stands for the theme, so a
	// field can be recognized as a token; the body is then emitted as-is, which
	// leaves `theme.sp2` binding to the const of that name in the enclosing
	// scope — that is what keeps the token's real type on the native lane.
	let sheet = node;
	let themeName = "";
	if (node.kind === NodeKind.ArrowFunction) {
		if (node.arrowParams.length !== 1) {
			error("createStyles takes one theme parameter: createStyles(theme => ({ ... }))", node);
		}
		themeName = node.arrowParams[0];
		sheet = node.arrowBody;
	}
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

	let entries: Node[] = [];
	for (let e = 0; e < sheet.properties.length; e += 1) {
		const v = sheet.properties[e];
		if (v.kind !== NodeKind.ObjectLiteral) {
			error("a sheet entry must be a static style object literal", v);
		}
		let fields: Node[] = [];
		let names: string[] = [];
		let locs: SourceLocation[] = [];
		let tokens: string[] = [];
		let overlay: Node | null = null;
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
			if (fv.kind === NodeKind.CallExpr) {
				error("a style field cannot call a function — a signal read here would be a frozen snapshot, not reactive (put reactive fields on the element: style={{ width: w() }})", fv);
			}
			let tok = "";
			if (themeName !== "" && fv.kind === NodeKind.MemberExpr) {
				const ob = fv.object;
				if (ob.kind === NodeKind.Identifier && ob.name === themeName) { tok = fv.property; }
			}
			fields.push(fv);
			names.push(name);
			locs.push(v.keyLocations[i]);
			tokens.push(tok);
		}
		if (overlay !== null) {
			const ov = overlay as Node;
			for (let j = 0; j < ov.properties.length; j += 1) {
				const pv = ov.properties[j];
				const pname = ov.keys[j];
				if (pv.kind === NodeKind.CallExpr) {
					error("a style field cannot call a function — a signal read here would be a frozen snapshot, not reactive (put reactive fields on the element: style={{ width: w() }})", pv);
				}
				let ptok = "";
				if (themeName !== "" && pv.kind === NodeKind.MemberExpr) {
					const pob = pv.object;
					if (pob.kind === NodeKind.Identifier && pob.name === themeName) { ptok = pv.property; }
				}
				let replaced = false;
				for (let b = 0; b < names.length; b += 1) {
					if (names[b] === pname) {
						fields[b] = pv;
						tokens[b] = ptok;
						replaced = true;
					}
				}
				if (!replaced) {
					fields.push(pv);
					names.push(pname);
					locs.push(ov.keyLocations[j]);
					tokens.push(ptok);
				}
			}
		}
		// A sheet entry is shared by every element that references it, so on a
		// host with a stylesheet it becomes one rule plus a class instead of a
		// field-by-field write per node. The rule text is baked here; the id is
		// content-hashed, so an unchanged entry keeps its name across builds and
		// an edited one lands under a new name (which is what lets a hot reload
		// swap rules without a frame of wrong styling).
		if (emitCss && fields.length > 0) {
			let decls = "";
			for (let b = 0; b < names.length; b += 1) {
				decls = decls + cssDecl(names[b], fields[b], tokens[b]);
			}
			if (decls !== "") {
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
		entries.push({
			kind: NodeKind.CallExpr, line: v.line, column: v.column,
			callee: { kind: NodeKind.Identifier, line: v.line, column: v.column, name: "styleOf" },
			arguments: [merged],
		});
	}
	return {
		kind: NodeKind.ObjectLiteral, line: node.line, column: node.column,
		properties: entries, keys: sheet.keys, keyLocations: sheet.keyLocations,
	};
}
