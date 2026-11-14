import { mountGuest } from "../../../src/platform/raiser/guest";
import { Card } from "./views";
import { Host, HostNode, NeonNode } from "../../../src/render/hostTypes";

export { raiserDispatch, raiserDispose } from "../../../src/platform/raiser/guest";

export function card(root: int32, title: string): void {
	mountGuest(root, (): NeonNode => (host: Host, parent: HostNode, before: HostNode | null): void => {
		Card(title)(host, parent, before);
		throw new Error("this edit fails at mount");
	});
}
