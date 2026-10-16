import { NeonNode, el, text } from "../../src/render/node";
import { Host, HostNode } from "../../src/render/hostTypes";
import { createUniqueId } from "../../src/core/owner";
import { Loading } from "../../src/macros/ui/flow";

export function loadingApp(): NeonNode {
	return el("div", [], [], Loading({ children: el("p", [], [], text("hi")), fallback: el("b", [], [], text("wait")) }));
}

export const loadingHtml: string = "<div><p>hi</p><!----></div>";

function drawsId(): NeonNode {
	return (h: Host, p: HostNode, b: HostNode | null): void => { el("p", [], [], text(createUniqueId()))(h, p, b); };
}

function drawsIdAfter(boundary: NeonNode): NeonNode {
	return (h: Host, p: HostNode, b: HostNode | null): void => {
		boundary(h, p, b);
		el("i", [], [], text(createUniqueId()))(h, p, b);
	};
}

export function loadingIdsApp(): NeonNode {
	return drawsIdAfter(Loading({ children: drawsId(), fallback: el("b", [], [], text("wait")) }));
}

export const loadingIdsMarkup: string = "<p>0000</p><!----><i>4</i>";
export const loadingIdsClient: string = "<div><p>0000</p><i>4</i></div>";
