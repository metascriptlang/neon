import { el, text, NeonNode } from "../../../src/render/node";

export function Page(props: {}): NeonNode {
	return el("p", [], [], text("fetched page"));
}
