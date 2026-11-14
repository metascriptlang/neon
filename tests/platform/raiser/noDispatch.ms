import { mountGuest } from "../../../src/platform/raiser/guest";
import { Card } from "./views";
import { NeonNode } from "../../../src/render/hostTypes";

export function card(root: int32, title: string): void {
	mountGuest(root, (): NeonNode => Card(title));
}
