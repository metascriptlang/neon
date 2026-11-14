import { mountGuest } from "../../../src/platform/raiser/guest";
import { Card } from "./views";
import { NeonNode } from "../../../src/render/hostTypes";

export { raiserDispatch, raiserDispose } from "../../../src/platform/raiser/guest";

export function card(root: int32, title: string): void {
	const count: int32 = title;
	mountGuest(root, (): NeonNode => Card(title));
}
