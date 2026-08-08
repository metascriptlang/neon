// Prelude surface for build.ms globalImports — makes bare JSX work in any
// Neon file with zero imports:
//
//   const v: NeonNode = <div/>;          // converter fires at the annotated decl
//
// The converter delegates to the same transform the element macro uses, so
// element(<jsx/>) and bare <jsx/> emit identical NeonNode trees. The emitted code
// calls el/attr/dynAttr/evt/text/dynText/withStyle by NAME, which is why this module
// re-exports them: prelude injection puts them in scope of every file.

import { Node, NodeKind } from "std/meta";
export { element } from "./macros/ui/element";
export { NeonNode, VAttr, VEvent, el, attr, dynAttr, evt, text, dynText, withStyle, regionNode, componentNode, renderToString } from "./render/node";
export { createComponent } from "./render/component";
// direct()'s template mode emits calls to these by NAME too (docs/RENDER-MODEL.md D4).
export { Template, createTemplate, instantiate, mountTemplate, childOf, siblingOf } from "./render/template";

export converter jsxToNeonNode(n: Node): NeonNode {
	return { kind: NodeKind.MacroInvocation, line: n.line, column: n.column, macroName: "element", macroArgs: [n] };
}
