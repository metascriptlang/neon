import { el, text, NeonNode } from "../../../src/render/node";

export function Page(props: { label: string }): NeonNode {
	return el("p", [], [], text("page " + props.label));
}
