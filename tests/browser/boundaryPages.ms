import { NeonNode, el, text } from "../../src/render/node";
import { Loading } from "../../src/macros/ui/flow";

export function loadingApp(): NeonNode {
	return el("div", [], [], Loading({ children: el("p", [], [], text("hi")), fallback: el("b", [], [], text("wait")) }));
}

export const loadingHtml: string = "<div><p>hi</p><!----></div>";
