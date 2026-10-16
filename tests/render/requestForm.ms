import { Host, HostNode, NeonNode } from "../../src/render/hostTypes";
import { bindText } from "../../src/render/bind";
import { createUniqueId } from "../../src/core/owner";
import { createRenderEffect } from "../../src/core/effect";

function labelled(label: string): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const id = createUniqueId();
		const text = host.createElement("label");
		host.setAttr(text, "for", id);
		const caption = host.createText("");
		bindText(host, caption, (): string => label);
		host.append(text, caption);
		const input = host.createElement("input");
		host.setAttr(input, "id", id);
		host.insertBefore(parent, text, before);
		host.insertBefore(parent, input, before);
	};
}

export function form(): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		labelled("name")(host, parent, before);
		createRenderEffect(() => { labelled("mail")(host, parent, before); });
	};
}
