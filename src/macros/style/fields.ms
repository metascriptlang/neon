import { Node, NodeKind, DeclKind, NodeFlag } from "std/meta";

export const STYLE_TABLE: string[][] = [
	["flexDirection",       "FlexDirection",     "word", "enum",   "ignore"],
	["justifyContent",      "Justify",           "word", "enum",   "ignore"],
	["alignItems",          "Align",             "word", "enum",   "ignore"],
	["alignSelf",           "Align",             "word", "enum",   "ignore"],
	["alignContent",        "Align",             "word", "enum",   "ignore"],
	["position",            "PositionType",      "word", "enum",   "ignore"],
	["flexWrap",            "Wrap",              "word", "enum",   "ignore"],
	["display",             "Display",           "word", "enum",   "ignore"],
	["flex",                "number",            "num",  "num",    "ignore"],
	["flexGrow",            "number",            "num",  "num",    "ignore"],
	["flexShrink",          "number",            "num",  "num",    "ignore"],
	["flexBasis",           "number | string",   "len",  "dim",    "ignore"],
	["width",               "number | string",   "len",  "dim",    "ignore"],
	["height",              "number | string",   "len",  "dim",    "ignore"],
	["minWidth",            "number | string",   "len",  "dim",    "ignore"],
	["minHeight",           "number | string",   "len",  "dim",    "ignore"],
	["maxWidth",            "number | string",   "len",  "dim",    "ignore"],
	["maxHeight",           "number | string",   "len",  "dim",    "ignore"],
	["aspectRatio",         "number",            "num",  "num",    "ignore"],
	["margin",              "number | string",   "len",  "dim",    "ignore"],
	["marginTop",           "number | string",   "len",  "dim",    "ignore"],
	["marginBottom",        "number | string",   "len",  "dim",    "ignore"],
	["marginLeft",          "number | string",   "len",  "dim",    "ignore"],
	["marginRight",         "number | string",   "len",  "dim",    "ignore"],
	["padding",             "number | string",   "len",  "dim",    "ignore"],
	["paddingTop",          "number | string",   "len",  "dim",    "ignore"],
	["paddingBottom",       "number | string",   "len",  "dim",    "ignore"],
	["paddingLeft",         "number | string",   "len",  "dim",    "ignore"],
	["paddingRight",        "number | string",   "len",  "dim",    "ignore"],
	["top",                 "number | string",   "len",  "dim",    "ignore"],
	["left",                "number | string",   "len",  "dim",    "ignore"],
	["right",               "number | string",   "len",  "dim",    "ignore"],
	["bottom",              "number | string",   "len",  "dim",    "ignore"],
	["gap",                 "number | string",   "len",  "dim",    "ignore"],
	["rowGap",              "number | string",   "len",  "dim",    "ignore"],
	["columnGap",           "number | string",   "len",  "dim",    "ignore"],
	["backgroundColor",     "string",            "word", "paint",  "paint"],
	["borderWidth",         "number",            "len",  "num",    "ignore"],
	["borderColor",         "string",            "word", "ignore", "ignore"],
	["borderRadius",        "number",            "len",  "ignore", "ignore"],
	["opacity",             "number",            "num",  "paint",  "paint"],
	["color",               "string",            "word", "paint",  "paint"],
	["fontSize",            "number",            "len",  "paint",  "ignore"],
	["fontWeight",          "FontWeight",        "word", "ignore", "paint"],
	["textAlign",           "TextAlign",         "word", "ignore", "ignore"],
	["overflow",            "Overflow",          "word", "enum",   "ignore"],
	["zIndex",              "number",            "num",  "paint",  "ignore"],
	["fontFamily",          "string",            "word", "ignore", "ignore"],
	["transform",           "string",            "word", "ignore", "ignore"],
	["cursor",              "string",            "word", "ignore", "ignore"],
	["boxShadow",           "string",            "word", "ignore", "ignore"],
	["fontStyle",           "FontStyle",         "word", "ignore", "paint"],
	["textDecorationLine",  "TextDecorationLine", "word", "ignore", "paint"],
];

export const STYLE_CLASS_FIELDS: string[][] = [
	["cssId", "string"],
	["css",   "string"],
];

const COL_TYPE = 1;
const COL_BROWSER = 2;
const COL_VOID = 3;
const COL_TERMINAL = 4;

export macro applyCssPropBody(node: Node): Node {
	const L = node.line;
	const C = node.column;
	const cases: Node[] = [];
	for (let i = 0; i < STYLE_TABLE.length; i = i + 1) {
		const row = STYLE_TABLE[i];
		if (row.length !== 5) { error("style table row " + row[0] + " must carry a type and every host", node); }
		const fieldName = row[0];
		const proj = row[COL_BROWSER];
		if (proj !== "word" && proj !== "num" && proj !== "len") { error("browser projection for " + fieldName + " must be word, num or len", node); }
		const castType = proj === "word" ? "string | null" : (proj === "num" ? "number | null" : "");
		const vRef: Node = { kind: NodeKind.Identifier, line: L, column: C, name: "v" };
		const arg: Node = castType === "" ? vRef
			: { kind: NodeKind.TypeAssertion, line: L, column: C, asExpr: vRef, asType: castType };
		cases.push({
			kind: NodeKind.MatchCase, line: L, column: C,
			casePatterns: [{ kind: NodeKind.StringLiteral, line: L, column: C, value: fieldName }],
			caseGuard: null,
			caseBody: {
				kind: NodeKind.BlockStmt, line: L, column: C,
				statements: [{
					kind: NodeKind.ExprStmt, line: L, column: C,
					expr: {
						kind: NodeKind.BinaryExpr, line: L, column: C, operator: "=",
						left: {
							kind: NodeKind.MemberExpr, line: L, column: C,
							object: { kind: NodeKind.Identifier, line: L, column: C, name: "css" },
							property: fieldName, isOptional: false,
						},
						right: {
							kind: NodeKind.CallExpr, line: L, column: C,
							callee: { kind: NodeKind.Identifier, line: L, column: C, name: proj },
							arguments: [arg], isDirectCall: false, resolvedOverloadIdx: -1,
						},
					},
				}],
			},
		});
	}
	cases.push({
		kind: NodeKind.MatchCase, line: L, column: C,
		casePatterns: [{ kind: NodeKind.Identifier, line: L, column: C, name: "_" }],
		caseGuard: null,
		caseBody: {
			kind: NodeKind.BlockStmt, line: L, column: C,
			statements: [{
				kind: NodeKind.ThrowStmt, line: L, column: C,
				throwArg: {
					kind: NodeKind.NewExpr, line: L, column: C,
					newCallee: { kind: NodeKind.Identifier, line: L, column: C, name: "Error" },
					newArguments: [{
						kind: NodeKind.BinaryExpr, line: L, column: C, operator: "+",
						left: { kind: NodeKind.StringLiteral, line: L, column: C, value: "no browser projection for style field " },
						right: { kind: NodeKind.Identifier, line: L, column: C, name: "name" },
					}],
				},
			}],
		},
	});
	return {
		kind: NodeKind.SpliceMany, line: L, column: C,
		spliceNodes: [{
			kind: NodeKind.ExportDecl, line: L, column: C,
			exportedDecl: {
				kind: NodeKind.FunctionDecl, line: L, column: C,
				fnName: "applyCssProp",
				params: ["css", "name", "v"],
				fnParamTypes: ["CssStyle", "string", "StyleValue"],
				fnBody: {
					kind: NodeKind.BlockStmt, line: L, column: C,
					statements: [{
						kind: NodeKind.MatchStmt, line: L, column: C,
						matchStmtDisc: { kind: NodeKind.Identifier, line: L, column: C, name: "name" },
						matchStmtCases: cases,
					}],
				},
				fnFlags: "", fnReturnType: "void", fnDefaults: [], nativeName: "",
				nameLocation: { line: L, column: C },
			},
		}],
	};
}

export macro applyCssBody(node: Node): Node {
	const L = node.line;
	const C = node.column;
	const stmts: Node[] = [{
		kind: NodeKind.ExprStmt, line: L, column: C,
		expr: {
			kind: NodeKind.BinaryExpr, line: L, column: C, operator: "=",
			left: {
				kind: NodeKind.MemberExpr, line: L, column: C,
				object: { kind: NodeKind.Identifier, line: L, column: C, name: "css" },
				property: "cssText", isOptional: false,
			},
			right: { kind: NodeKind.StringLiteral, line: L, column: C, value: "" },
		},
	}];
	for (let i = 0; i < STYLE_TABLE.length; i = i + 1) {
		const fieldName = STYLE_TABLE[i][0];
		const read: Node = {
			kind: NodeKind.MemberExpr, line: L, column: C,
			object: { kind: NodeKind.Identifier, line: L, column: C, name: "s" },
			property: fieldName, isOptional: false,
		};
		stmts.push({
			kind: NodeKind.IfStmt, line: L, column: C,
			condition: {
				kind: NodeKind.BinaryExpr, line: L, column: C, operator: "!==",
				left: read,
				right: { kind: NodeKind.NullLiteral, line: L, column: C },
			},
			consequent: {
				kind: NodeKind.BlockStmt, line: L, column: C,
				statements: [{
					kind: NodeKind.ExprStmt, line: L, column: C,
					expr: {
						kind: NodeKind.CallExpr, line: L, column: C,
						callee: { kind: NodeKind.Identifier, line: L, column: C, name: "applyCssProp" },
						arguments: [
							{ kind: NodeKind.Identifier, line: L, column: C, name: "css" },
							{ kind: NodeKind.StringLiteral, line: L, column: C, value: fieldName },
							{
								kind: NodeKind.TypeAssertion, line: L, column: C, asType: "StyleValue",
								asExpr: { kind: NodeKind.TypeAssertion, line: L, column: C, asType: "unknown", asExpr: read },
							},
						],
						isDirectCall: false, resolvedOverloadIdx: -1,
					},
				}],
			},
			alternate: { kind: NodeKind.BlockStmt, line: L, column: C, statements: [] },
		});
	}
	return {
		kind: NodeKind.SpliceMany, line: L, column: C,
		spliceNodes: [{
			kind: NodeKind.ExportDecl, line: L, column: C,
			exportedDecl: {
				kind: NodeKind.FunctionDecl, line: L, column: C,
				fnName: "applyCss",
				params: ["css", "s"],
				fnParamTypes: ["CssStyle", "Style"],
				fnBody: { kind: NodeKind.BlockStmt, line: L, column: C, statements: stmts },
				fnFlags: "", fnReturnType: "void", fnDefaults: [], nativeName: "",
				nameLocation: { line: L, column: C },
			},
		}],
	};
}

export macro asFlexStyleBody(node: Node): Node {
	const L = node.line;
	const C = node.column;
	const stmts: Node[] = [{
		kind: NodeKind.VariableDecl, line: L, column: C,
		declName: "st", declType: "FlexStyle", declKind: DeclKind.Const,
		initializer: { kind: NodeKind.ObjectLiteral, line: L, column: C, properties: [], keys: [], keyLocations: [] },
	}];
	for (let i = 0; i < STYLE_TABLE.length; i = i + 1) {
		const row = STYLE_TABLE[i];
		if (row.length !== 5) { error("style table row " + row[0] + " must carry a type and every host", node); }
		const fieldName = row[0];
		const how = row[COL_VOID];
		if (how === "paint" || how === "ignore") { continue; }
		if (how !== "enum" && how !== "num" && how !== "dim") { error("void projection for " + fieldName + " must be enum, num, dim, paint or ignore", node); }
		const read: Node = {
			kind: NodeKind.MemberExpr, line: L, column: C,
			object: { kind: NodeKind.Identifier, line: L, column: C, name: "s" },
			property: fieldName, isOptional: false,
		};
		// Enum rows cross from the Style union (render/style.ms) into the
		// target FlexStyle union (yoga's enums) — same members, distinct
		// nominal types. The checker takes the raw copy, but the C backend
		// lowers the two unions to different Maybe_T structs and clang
		// rejects the assignment. An explicit cast to the target union name
		// makes codegen build the TARGET field field-wise (probed with a
		// two-module cast probe during the ios-host arc). The caller of
		// asFlexStyleBody must therefore have the table's type names in
		// scope (yoga re-exports them from src/index).
		const value: Node = how === "enum" ? {
			kind: NodeKind.TypeAssertion, line: L, column: C,
			asExpr: read,
			asType: row[COL_TYPE],
		} : {
			kind: NodeKind.CallExpr, line: L, column: C,
			callee: { kind: NodeKind.Identifier, line: L, column: C, name: how },
			arguments: how === "dim" ? [read, { kind: NodeKind.StringLiteral, line: L, column: C, value: fieldName }] : [read],
			isDirectCall: false, resolvedOverloadIdx: -1,
		};
		// Null-guard every projection: an unset Style field must stay UNSET on
		// the FlexStyle, never become a boxed null. applyStyle (yoga/src/style.ms)
		// reads `field !== null`; a boxed null passes that check and reaches the
		// setter as garbage — on the C backend a style whose maxWidth arrived
		// boxed-null clamped every node to 0x0 (found by the ios-host arc's
		// walk probe; applyCssBody below has guarded the same way from the
		// start). The guard is why enum rows never cast null either.
		stmts.push({
			kind: NodeKind.IfStmt, line: L, column: C,
			condition: {
				kind: NodeKind.BinaryExpr, line: L, column: C, operator: "!==",
				left: read,
				right: { kind: NodeKind.NullLiteral, line: L, column: C },
			},
			consequent: {
				kind: NodeKind.BlockStmt, line: L, column: C,
				statements: [{
					kind: NodeKind.ExprStmt, line: L, column: C,
					expr: {
						kind: NodeKind.BinaryExpr, line: L, column: C, operator: "=",
						left: {
							kind: NodeKind.MemberExpr, line: L, column: C,
							object: { kind: NodeKind.Identifier, line: L, column: C, name: "st" },
							property: fieldName, isOptional: false,
						},
						right: value,
					},
				}],
			},
			alternate: { kind: NodeKind.BlockStmt, line: L, column: C, statements: [] },
		});
	}
	stmts.push({
		kind: NodeKind.ReturnStmt, line: L, column: C,
		argument: { kind: NodeKind.Identifier, line: L, column: C, name: "st" },
	});
	return {
		kind: NodeKind.SpliceMany, line: L, column: C,
		spliceNodes: [{
			kind: NodeKind.ExportDecl, line: L, column: C,
			exportedDecl: {
				kind: NodeKind.FunctionDecl, line: L, column: C,
				fnName: "asFlexStyle",
				params: ["s"],
				fnParamTypes: ["Style"],
				fnBody: { kind: NodeKind.BlockStmt, line: L, column: C, statements: stmts },
				fnFlags: "", fnReturnType: "FlexStyle", fnDefaults: [], nativeName: "",
				nameLocation: { line: L, column: C },
			},
		}],
	};
}

export macro terminalStyleCoverage(node: Node): Node {
	for (let i = 0; i < STYLE_TABLE.length; i = i + 1) {
		const row = STYLE_TABLE[i];
		if (row.length !== 5) { error("style table row " + row[0] + " must carry a type and every host", node); }
		const how = row[COL_TERMINAL];
		if (how !== "paint" && how !== "ignore") { error("terminal projection for " + row[0] + " must be paint or ignore", node); }
	}
	return { kind: NodeKind.SpliceMany, line: node.line, column: node.column, spliceNodes: [] };
}

export macro styleInterfaceBody(node: Node): Node {
	const L = node.line;
	const C = node.column;
	const names: string[] = [];
	const types: string[] = [];
	for (let i = 0; i < STYLE_TABLE.length; i = i + 1) {
		const row = STYLE_TABLE[i];
		if (row.length !== 5) { error("style table row " + row[0] + " must carry a type and every host", node); }
		names.push(row[0]);
		types.push(row[COL_TYPE] + " | null");
	}
	for (let i = 0; i < STYLE_CLASS_FIELDS.length; i = i + 1) {
		names.push(STYLE_CLASS_FIELDS[i][0]);
		types.push(STYLE_CLASS_FIELDS[i][1] + " | null");
	}
	return {
		kind: NodeKind.SpliceMany, line: L, column: C,
		spliceNodes: [{
			kind: NodeKind.ExportDecl, line: L, column: C,
			exportedDecl: {
				kind: NodeKind.InterfaceDecl, line: L, column: C,
				interfaceName: "Style", interfaceFields: names, interfaceFieldTypes: types, interfaceExtends: [],
				nameLocation: { line: L, column: C },
			},
		}],
	};
}

export macro setStyleFieldBody(node: Node): Node {
	const L = node.line;
	const C = node.column;
	const cases: Node[] = [];
	for (let i = 0; i < STYLE_TABLE.length; i = i + 1) {
		const row = STYLE_TABLE[i];
		if (row.length !== 5) { error("style table row " + row[0] + " must carry a type and every host", node); }
		const fieldName = row[0];
		cases.push({
			kind: NodeKind.MatchCase, line: L, column: C,
			casePatterns: [{ kind: NodeKind.StringLiteral, line: L, column: C, value: fieldName }],
			caseGuard: null,
			caseBody: {
				kind: NodeKind.BlockStmt, line: L, column: C,
				statements: [{
					kind: NodeKind.ExprStmt, line: L, column: C,
					expr: {
						kind: NodeKind.BinaryExpr, line: L, column: C, operator: "=",
						left: { kind: NodeKind.MemberExpr, line: L, column: C, object: { kind: NodeKind.Identifier, line: L, column: C, name: "s" }, property: fieldName, isOptional: false },
						right: {
							kind: NodeKind.TypeAssertion, line: L, column: C,
							asExpr: { kind: NodeKind.TypeAssertion, line: L, column: C, asExpr: { kind: NodeKind.Identifier, line: L, column: C, name: "v" }, asType: "unknown" },
							asType: row[COL_TYPE] + " | null",
						},
					},
				}],
			},
		});
	}
	cases.push({
		kind: NodeKind.MatchCase, line: L, column: C,
		casePatterns: [{ kind: NodeKind.Identifier, line: L, column: C, name: "_" }],
		caseGuard: null,
		caseBody: {
			kind: NodeKind.BlockStmt, line: L, column: C,
			statements: [{
				kind: NodeKind.ThrowStmt, line: L, column: C,
				throwArg: {
					kind: NodeKind.NewExpr, line: L, column: C,
					newCallee: { kind: NodeKind.Identifier, line: L, column: C, name: "Error" },
					newArguments: [{
						kind: NodeKind.BinaryExpr, line: L, column: C, operator: "+",
						left: { kind: NodeKind.StringLiteral, line: L, column: C, value: "no Style field named " },
						right: { kind: NodeKind.Identifier, line: L, column: C, name: "name" },
					}],
				},
			}],
		},
	});
	return {
		kind: NodeKind.SpliceMany, line: L, column: C,
		spliceNodes: [{
			kind: NodeKind.ExportDecl, line: L, column: C,
			exportedDecl: {
				kind: NodeKind.FunctionDecl, line: L, column: C,
				fnName: "setStyleField", params: ["s", "name", "v"], fnParamTypes: ["Style", "string", "StyleValue"],
				fnBody: { kind: NodeKind.BlockStmt, line: L, column: C, statements: [{
			kind: NodeKind.MatchStmt, line: L, column: C,
			matchStmtDisc: { kind: NodeKind.Identifier, line: L, column: C, name: "name" },
			matchStmtCases: cases,
		}] },
				fnFlags: "", fnReturnType: "void", fnDefaults: [], nativeName: "",
				nameLocation: { line: L, column: C },
			},
		}],
	};
}

export macro mergeStyleBody(node: Node): Node {
	const L = node.line;
	const C = node.column;
	const props: Node[] = [];
	const keys: string[] = [];
	for (let i = 0; i < STYLE_TABLE.length; i = i + 1) {
		const row = STYLE_TABLE[i];
		if (row.length !== 5) { error("style table row " + row[0] + " must carry a type and every host", node); }
		const fieldName = row[0];
		keys.push(fieldName);
		props.push({
			kind: NodeKind.ConditionalExpr, line: L, column: C,
			ternaryCondition: {
				kind: NodeKind.BinaryExpr, line: L, column: C, operator: "!==",
				left: { kind: NodeKind.MemberExpr, line: L, column: C, object: { kind: NodeKind.Identifier, line: L, column: C, name: "over" }, property: fieldName, isOptional: false },
				right: { kind: NodeKind.NullLiteral, line: L, column: C },
			},
			ternaryConsequent: { kind: NodeKind.MemberExpr, line: L, column: C, object: { kind: NodeKind.Identifier, line: L, column: C, name: "over" }, property: fieldName, isOptional: false },
			ternaryAlternate: { kind: NodeKind.MemberExpr, line: L, column: C, object: { kind: NodeKind.Identifier, line: L, column: C, name: "base" }, property: fieldName, isOptional: false },
		});
	}
	return {
		kind: NodeKind.SpliceMany, line: L, column: C,
		spliceNodes: [{
			kind: NodeKind.ExportDecl, line: L, column: C,
			exportedDecl: {
				kind: NodeKind.FunctionDecl, line: L, column: C,
				fnName: "mergeStyle", params: ["base", "over"], fnParamTypes: ["Style", "Style"],
				fnBody: { kind: NodeKind.BlockStmt, line: L, column: C, statements: [{
			kind: NodeKind.ReturnStmt, line: L, column: C,
			argument: { kind: NodeKind.ObjectLiteral, line: L, column: C, properties: props, keys: keys, keyLocations: [] },
		}] },
				fnFlags: "", fnReturnType: "Style", fnDefaults: [], nativeName: "",
				nameLocation: { line: L, column: C },
			},
		}],
	};
}

export macro styleToCssBody(node: Node): Node {
	const L = node.line;
	const C = node.column;
	const stmts: Node[] = [{
		kind: NodeKind.VariableDecl, line: L, column: C,
		declName: "out", declType: "string", declKind: DeclKind.Let,
		initializer: { kind: NodeKind.StringLiteral, line: L, column: C, value: "" },
	}];
	for (let i = 0; i < STYLE_TABLE.length; i = i + 1) {
		const row = STYLE_TABLE[i];
		if (row.length !== 5) { error("style table row " + row[0] + " must carry a type and every host", node); }
		const fieldName = row[0];
		const ty = row[COL_TYPE];
		const proj = row[COL_BROWSER];
		let emitter = "";
		if (proj === "word") { emitter = "cssWord"; }
		else if (proj === "num") { emitter = "cssRatio"; }
		else if (proj === "len" && ty === "number") { emitter = "cssPx"; }
		else if (proj === "len" && ty === "number | string") { emitter = "cssLen"; }
		else { error("no CSS emitter for " + fieldName + " (" + proj + " / " + ty + ")", node); }
		const read: Node = { kind: NodeKind.MemberExpr, line: L, column: C, object: { kind: NodeKind.Identifier, line: L, column: C, name: "s" }, property: fieldName, isOptional: false };
		const arg: Node = proj === "word" ? { kind: NodeKind.TypeAssertion, line: L, column: C, asExpr: read, asType: "string | null" } : read;
		stmts.push({
			kind: NodeKind.ExprStmt, line: L, column: C,
			expr: {
				kind: NodeKind.BinaryExpr, line: L, column: C, operator: "=",
				left: { kind: NodeKind.Identifier, line: L, column: C, name: "out" },
				right: {
					kind: NodeKind.BinaryExpr, line: L, column: C, operator: "+",
					left: { kind: NodeKind.Identifier, line: L, column: C, name: "out" },
					right: {
						kind: NodeKind.CallExpr, line: L, column: C,
						callee: { kind: NodeKind.Identifier, line: L, column: C, name: emitter },
						arguments: [{ kind: NodeKind.StringLiteral, line: L, column: C, value: fieldName }, arg],
						isDirectCall: false, resolvedOverloadIdx: -1,
					},
				},
			},
		});
	}
	stmts.push({ kind: NodeKind.ReturnStmt, line: L, column: C, argument: { kind: NodeKind.Identifier, line: L, column: C, name: "out" } });
	return {
		kind: NodeKind.SpliceMany, line: L, column: C,
		spliceNodes: [{
			kind: NodeKind.ExportDecl, line: L, column: C,
			exportedDecl: {
				kind: NodeKind.FunctionDecl, line: L, column: C,
				fnName: "styleToCss", params: ["s"], fnParamTypes: ["Style"],
				fnBody: { kind: NodeKind.BlockStmt, line: L, column: C, statements: stmts },
				fnFlags: "", fnReturnType: "string", fnDefaults: [], nativeName: "",
				nameLocation: { line: L, column: C },
			},
		}],
	};
}

export macro cssStyleExternBody(node: Node): Node {
	const L = node.line;
	const C = node.column;
	const body: Node[] = [];
	for (let i = 0; i < STYLE_TABLE.length; i = i + 1) {
		const row = STYLE_TABLE[i];
		if (row.length !== 5) { error("style table row " + row[0] + " must carry a type and every host", node); }
		body.push({ kind: NodeKind.PropertyDecl, line: L, column: C, propName: row[0], propType: "cstring", propIsStatic: false, propIsReadonly: false, propVisibility: "", propInitializer: null as unknown as Node });
	}
	body.push({ kind: NodeKind.PropertyDecl, line: L, column: C, propName: "cssText", propType: "cstring", propIsStatic: false, propIsReadonly: false, propVisibility: "", propInitializer: null as unknown as Node });
	const cls: Node = { kind: NodeKind.ClassDecl, line: L, column: C, className: "CssStyle", classExtends: "", classBody: body, nameLocation: { line: L, column: C } };
	cls.flags = cls.flags.incl(NodeFlag.ExternC);
	return { kind: NodeKind.SpliceMany, line: L, column: C, spliceNodes: [cls] };
}
