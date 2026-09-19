// Prelude surface for build.ms globalImports — makes bare JSX work in any
// Neon file with zero imports:
//
//   render(<App/>, host, parent);        // converter fires at the parameter boundary
//
// A bare <jsx/> lowers wherever a NeonNode is expected — a component's return, an
// annotated const, a render call — because the converter is selected by that type.
//
// The emitted code calls its runtime helpers BY NAME, which is why this module
// re-exports them: prelude injection puts them in scope of every file.

import { Node, NodeKind } from "std/meta";
import { NeonNode } from "./render/hostTypes";

export { element } from "./macros/ui/element";
export { direct } from "./macros/ui/direct";
export { VAttr, VEvent, RegionFn, ComponentFn, RefFn, attr, dynAttr, evt, el, hostElement, text, dynText, mountChild, regionNode } from "./render/node";
export { renderToString } from "./render/ssr";
export { createComponent } from "./render/component";
export { Accessor, accessor } from "./core/signal";
export { Template, createTemplate, instantiate, mountTemplate, childOf, siblingOf } from "./render/template";
export { render, bindText, bindAttr, writeAttr, bindStyleAll, bindStyleProp, applyStaticStyle, applyRef } from "./render/host";
export { Row, makeRow, rowOf, place, mountAt, moveRow, removeRow, reconcileArrays } from "./render/reconcile";
export { Host, HostNode, NeonNode } from "./render/hostTypes";
export { Style, StyleValue, emptyStyle, mergeStyle, layerStyles } from "./render/style";

export converter jsxToNode(n: Node): NeonNode {
	return { kind: NodeKind.MacroInvocation, line: n.line, column: n.column, macroName: "element", macroArgs: [n] };
}
