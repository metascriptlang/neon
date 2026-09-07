import { Node, NodeKind, SourceLocation, createNodeAt } from "std/meta";

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
	const loc: SourceLocation = { line: L, column: C };
	const stmts: Node[] = [];
	for (let i = 0; i < STYLE_FIELDS.length; i = i + 1) {
		const fieldName = STYLE_FIELDS[i];
		const assign: Node = {
			kind: NodeKind.BinaryExpr, line: L, column: C, operator: "=",
			left: {
				kind: NodeKind.MemberExpr, line: L, column: C,
				object: { kind: NodeKind.Identifier, line: L, column: C, name: "css" }, property: fieldName, isOptional: false,
			},
			right: {
				kind: NodeKind.CallExpr, line: L, column: C,
				callee: { kind: NodeKind.Identifier, line: L, column: C, name: STYLE_PROJECTIONS[i] },
				arguments: [{ kind: NodeKind.Identifier, line: L, column: C, name: "v" }],
				isDirectCall: false, resolvedOverloadIdx: -1,
			},
		};
		stmts.push({
			kind: NodeKind.IfStmt, line: L, column: C,
			condition: {
				kind: NodeKind.BinaryExpr, line: L, column: C, operator: "===",
				left: { kind: NodeKind.Identifier, line: L, column: C, name: "name" },
				right: { kind: NodeKind.StringLiteral, line: L, column: C, value: fieldName },
			},
			consequent: {
				kind: NodeKind.BlockStmt, line: L, column: C,
				statements: [
					{ kind: NodeKind.ExprStmt, line: L, column: C, expr: assign },
					{ kind: NodeKind.ReturnStmt, line: L, column: C, argument: null },
				],
			},
			alternate: createNodeAt(NodeKind.BlockStmt, { statements: [] }, loc),
		});
	}
	stmts.push({
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
	});
	return {
		kind: NodeKind.SpliceMany, line: L, column: C,
		spliceNodes: [{
			kind: NodeKind.FunctionDecl, line: L, column: C,
			fnName: "applyCssProp",
			params: ["css", "name", "v"],
			fnParamTypes: ["CssStyle", "string", "StyleValue"],
			fnBody: { kind: NodeKind.BlockStmt, line: L, column: C, statements: stmts },
			fnFlags: "", fnReturnType: "void", fnDefaults: [], nativeName: "",
			nameLocation: { line: L, column: C },
		}],
	};
}
