import { Node, NodeKind, DeclKind } from "std/meta";

export const STYLE_TABLE: string[][] = [
	["flexDirection",   "word", "enum",   "ignore"],
	["justifyContent",  "word", "enum",   "ignore"],
	["alignItems",      "word", "enum",   "ignore"],
	["alignSelf",       "word", "enum",   "ignore"],
	["alignContent",    "word", "enum",   "ignore"],
	["position",        "word", "enum",   "ignore"],
	["flexWrap",        "word", "enum",   "ignore"],
	["display",         "word", "enum",   "ignore"],
	["flex",            "num",  "num",    "ignore"],
	["flexGrow",        "num",  "num",    "ignore"],
	["flexShrink",      "num",  "num",    "ignore"],
	["flexBasis",       "len",  "dim",    "ignore"],
	["width",           "len",  "dim",    "ignore"],
	["height",          "len",  "dim",    "ignore"],
	["minWidth",        "len",  "dim",    "ignore"],
	["minHeight",       "len",  "dim",    "ignore"],
	["maxWidth",        "len",  "dim",    "ignore"],
	["maxHeight",       "len",  "dim",    "ignore"],
	["aspectRatio",     "num",  "num",    "ignore"],
	["margin",          "len",  "dim",    "ignore"],
	["marginTop",       "len",  "dim",    "ignore"],
	["marginBottom",    "len",  "dim",    "ignore"],
	["marginLeft",      "len",  "dim",    "ignore"],
	["marginRight",     "len",  "dim",    "ignore"],
	["padding",         "len",  "dim",    "ignore"],
	["paddingTop",      "len",  "dim",    "ignore"],
	["paddingBottom",   "len",  "dim",    "ignore"],
	["paddingLeft",     "len",  "dim",    "ignore"],
	["paddingRight",    "len",  "dim",    "ignore"],
	["top",             "len",  "dim",    "ignore"],
	["left",            "len",  "dim",    "ignore"],
	["right",           "len",  "dim",    "ignore"],
	["bottom",          "len",  "dim",    "ignore"],
	["gap",             "len",  "dim",    "ignore"],
	["rowGap",          "len",  "dim",    "ignore"],
	["columnGap",       "len",  "dim",    "ignore"],
	["backgroundColor", "word", "paint",  "paint"],
	["borderWidth",     "len",  "num",    "ignore"],
	["borderColor",     "word", "ignore", "ignore"],
	["borderRadius",    "len",  "ignore", "ignore"],
	["opacity",         "num",  "paint",  "paint"],
	["color",           "word", "paint",  "paint"],
	["fontSize",        "len",  "paint",  "ignore"],
	["fontWeight",      "word", "ignore", "paint"],
	["textAlign",       "word", "ignore", "ignore"],
];

const COL_BROWSER = 1;
const COL_VOID = 2;
const COL_TERMINAL = 3;

export macro applyCssPropBody(node: Node): Node {
	const L = node.line;
	const C = node.column;
	const cases: Node[] = [];
	for (let i = 0; i < STYLE_TABLE.length; i = i + 1) {
		const row = STYLE_TABLE[i];
		if (row.length !== 4) { error("style table row " + row[0] + " must name every host", node); }
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
		if (row.length !== 4) { error("style table row " + row[0] + " must name every host", node); }
		const fieldName = row[0];
		const how = row[COL_VOID];
		if (how === "paint" || how === "ignore") { continue; }
		if (how !== "enum" && how !== "num" && how !== "dim") { error("void projection for " + fieldName + " must be enum, num, dim, paint or ignore", node); }
		const read: Node = {
			kind: NodeKind.MemberExpr, line: L, column: C,
			object: { kind: NodeKind.Identifier, line: L, column: C, name: "s" },
			property: fieldName, isOptional: false,
		};
		const value: Node = how === "enum" ? read : {
			kind: NodeKind.CallExpr, line: L, column: C,
			callee: { kind: NodeKind.Identifier, line: L, column: C, name: how },
			arguments: [read], isDirectCall: false, resolvedOverloadIdx: -1,
		};
		stmts.push({
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
		if (row.length !== 4) { error("style table row " + row[0] + " must name every host", node); }
		const how = row[COL_TERMINAL];
		if (how !== "paint" && how !== "ignore") { error("terminal projection for " + row[0] + " must be paint or ignore", node); }
	}
	return { kind: NodeKind.SpliceMany, line: node.line, column: node.column, spliceNodes: [] };
}
