// Prelude surface for build.ms globalImports — makes bare JSX work in any
// Neon file with zero imports:
//
//   render(<App/>, host, parent);        // converter fires at the parameter boundary
//
// Which emission a bare <jsx/> lowers to is decided by the BOUNDARY it crosses: a
// converter is selected by the expected type, so `NeonView` (the entry point's
// parameter) picks direct emission and `NeonNode` (a component's return, a server
// render) picks the tree macro. Same on every target — the tier within direct
// emission is then the per-site choice `direct.ms` makes.
//
// The emitted code calls its runtime helpers BY NAME, which is why this module
// re-exports them: prelude injection puts them in scope of every file.

import { Node, NodeKind } from "std/meta";
import { Host, HostNode } from "./render/hostTypes";
import { NeonNode } from "./render/node";
import { renderToHost } from "./render/host";

export { element } from "./macros/ui/element";
export { direct } from "./macros/ui/direct";
export { VAttr, VEvent, RegionFn, ComponentFn, ComponentProducer, NeonNode, VDynStyle, attr, dynAttr, evt, el, withStyle, withDynStyle, withDynStyleAll, text, dynText, insChild, regionNode, componentNode, renderToString } from "./render/node";
export { createComponent } from "./render/component";
export { Template, createTemplate, instantiate, mountTemplate, childOf, siblingOf } from "./render/template";
export { renderNode, renderToHost, bindText, bindAttr, NeonView, mountView, viewOf } from "./render/host";
export { Host, HostNode } from "./render/hostTypes";
export { Style, StyleValue, mergeStyle, layerStyles } from "./render/style";

// Direct emission: the macro emits the mount code itself, so a view IS the mount
// closure and rendering it is calling it. NeonView itself lives in render/host
// beside mountView — flow.ms needs it and must not depend on this surface.
export converter jsxToView(n: Node): NeonView {
	return { kind: NodeKind.MacroInvocation, line: n.line, column: n.column, macroName: "direct", macroArgs: [n] };
}

// Components keep the NeonNode contract (createComponent), and renderToString
// consumes a description, so a bare JSX at a NeonNode boundary — a component's
// return, an annotated const, a server render — lowers through the tree macro.
export converter jsxToNode(n: Node): NeonNode {
	return { kind: NodeKind.MacroInvocation, line: n.line, column: n.column, macroName: "element", macroArgs: [n] };
}

export function render(view: NeonView, host: Host, parent: HostNode): void {
	host.append(parent, view(host));
}
