// Prelude surface for build.ms globalImports — makes bare JSX work in any
// Neon file with zero imports:
//
//   const v: VNode = <div/>;          // converter fires at the annotated decl
//
// The converter delegates to the same transform the element macro uses, so
// element(<jsx/>) and bare <jsx/> emit identical VNode trees. The emitted code
// calls el/attr/evt/text/dynText/withStyle by NAME, which is why this module
// re-exports them: prelude injection puts them in scope of every file.

import { Node, NodeKind } from "std/meta";
export { element } from "./macros/ui/element";
export { VNode, VAttr, VEvent, el, attr, evt, text, dynText, withStyle, regionNode, componentNode, renderToString } from "./render/node";

export converter jsxToVNode(n: Node): VNode {
	return { kind: NodeKind.MacroInvocation, line: n.line, column: n.column, macroName: "element", macroArgs: [n] };
}
