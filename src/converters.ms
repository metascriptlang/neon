// Prelude surface for build.ms globalImports — makes bare JSX work in any
// Neon file with zero imports:
//
//   render(<App/>, host, parent);        // converter fires at the parameter boundary
//
// Which emission a bare <jsx/> lowers to is decided HERE, once, per target. A
// converter is selected by the EXPECTED TYPE at the boundary, so `NeonView` — the
// parameter type of the entry point — is what picks the macro. User source is
// byte-identical on every target; only the `when` branch below differs.
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

when (js) {
	// Direct emission: the macro emits the mount code itself, so a view IS the mount
	// closure and rendering it is calling it. NeonView itself lives in render/host
	// beside mountView — flow.ms needs it and must not depend on this surface.
	export converter jsxToView(n: Node): NeonView {
		return { kind: NodeKind.MacroInvocation, line: n.line, column: n.column, macroName: "direct", macroArgs: [n] };
	}

	// Components keep the NeonNode contract (createComponent), so on js a bare
	// JSX at a NeonNode boundary — a component's return, an annotated const —
	// lowers through the tree macro. On native NeonView IS NeonNode; here the
	// two targets need their own converter each.
	export converter jsxToNode(n: Node): NeonNode {
		return { kind: NodeKind.MacroInvocation, line: n.line, column: n.column, macroName: "element", macroArgs: [n] };
	}

	export function render(view: NeonView, host: Host, parent: HostNode): void {
		host.append(parent, view(host));
	}
} else {
	// Tree emission: the macro emits a description tree that the shared walker mounts.
	export converter jsxToView(n: Node): NeonView {
		return { kind: NodeKind.MacroInvocation, line: n.line, column: n.column, macroName: "element", macroArgs: [n] };
	}

	export function render(view: NeonView, host: Host, parent: HostNode): void {
		renderToHost(view, host, parent);
	}
}
