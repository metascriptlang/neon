import { mountGuest } from "../../../src/platform/raiser/guest";
import { Card, Ticker, cleanupCount } from "./views";
import { NeonNode } from "../../../src/render/hostTypes";

export { raiserDispatch, raiserDispose } from "../../../src/platform/raiser/guest";

export function card(root: int32, title: string): void {
	mountGuest(root, (): NeonNode => Card(title));
}

export function ticker(root: int32): void {
	mountGuest(root, Ticker);
}

export function cleanups(): int32 {
	return cleanupCount();
}
