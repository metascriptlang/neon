import { Node, NodeKind, SourceLocation } from "std/meta";

export const STYLE_FIELDS: string[] = [
	"flexDirection", "justifyContent", "alignItems", "alignSelf", "alignContent", "position",
	"flexWrap", "display", "flex", "flexGrow", "flexShrink", "flexBasis", "width", "height",
	"minWidth", "minHeight", "maxWidth", "maxHeight", "aspectRatio", "margin", "marginTop",
	"marginBottom", "marginLeft", "marginRight", "padding", "paddingTop", "paddingBottom",
	"paddingLeft", "paddingRight", "top", "left", "right", "bottom", "gap", "rowGap", "columnGap",
	"backgroundColor", "borderWidth", "borderColor", "borderRadius", "opacity", "color",
	"fontSize", "fontWeight", "textAlign",
];

export const STYLE_PROJECTIONS: string[] = [
	"word", "word", "word", "word", "word", "word", "word", "word", "num", "num", "num", "len",
	"len", "len", "len", "len", "len", "len", "num", "len", "len", "len", "len", "len", "len",
	"len", "len", "len", "len", "len", "len", "len", "len", "len", "len", "len", "word", "len",
	"word", "len", "num", "word", "len", "word", "word",
];

export macro applyCssPropBody(node: Node): Node {
	const L = node.line;
	const C = node.column;
	const cases: Node[] = [];
	for (let i = 0; i < STYLE_FIELDS.length; i = i + 1) {
		const fieldName = STYLE_FIELDS[i];
		const proj = STYLE_PROJECTIONS[i];
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
	for (let i = 0; i < STYLE_FIELDS.length; i = i + 1) {
		const fieldName = STYLE_FIELDS[i];
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
