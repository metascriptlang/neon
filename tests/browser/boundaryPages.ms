import { NeonNode, el, text } from "../../src/render/node";
import { Host, HostNode } from "../../src/render/hostTypes";
import { Accessor } from "../../src/core/signal";
import { createUniqueId } from "../../src/core/owner";
import { Errored, Loading } from "../../src/macros/ui/flow";

export function loadingApp(): NeonNode {
	return el("div", [], [], Loading({ children: el("p", [], [], text("hi")), fallback: el("b", [], [], text("wait")) }));
}

export function erroringApp(): NeonNode {
	return el("div", [], [], Errored({
		children: (h: Host, p: HostNode, b: HostNode | null): void => { throw new Error("boom"); },
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => el("em", [], [], text("sorry")),
	}));
}

export function erroringChildApp(attempts: int32[], resets: (() => void)[]): NeonNode {
	const boom: NeonNode = (h: Host, p: HostNode, b: HostNode | null): void => {
		attempts[0] = attempts[0] + 1;
		if (attempts[0] === 1) { throw new Error("boom"); }
		text("fine")(h, p, b);
	};
	return el("div", [], [], Errored({
		children: (h: Host, p: HostNode, b: HostNode | null): void => {
			el("i", [], [], text("lead"))(h, p, b);
			el("section", [], [], boom)(h, p, b);
		},
		fallback: (err: Accessor<Error>, again: () => void): NeonNode => {
			resets.push(again);
			return (h: Host, p: HostNode, b: HostNode | null): void => {
				el("i", [], [], text("sorry"))(h, p, b);
				el("section", [], [], text("sorry"))(h, p, b);
			};
		},
	}));
}

export const loadingHtml: string = "<div><p>hi</p><!----></div>";
export const erroringHtml: string = "<div><em>sorry</em><!----></div>";
export const erroringChildHtml: string = "<div><i>sorry</i><section>sorry</section><!----></div>";

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

export function erroringIdsApp(): NeonNode {
	return drawsIdAfter(Errored({
		children: drawsId(),
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => el("em", [], [], text("sorry")),
	}));
}

export const loadingIdsMarkup: string = "<p>0000</p><!----><i>4</i>";
export const erroringIdsMarkup: string = "<p>010</p><!----><i>4</i>";
export const loadingIdsClient: string = "<div><p>0000</p><i>4</i></div>";
export const erroringIdsClient: string = "<div><p>010</p><i>4</i></div>";
