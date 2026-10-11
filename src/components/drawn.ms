// Helpers shared by the Neon-drawn Material controls (checkbox, radio, chip, card, …).

import { Style, layerStyles } from "../render/style";
import { Accessor, accessor } from "../core/signal";
import { VAttr, dynAttr } from "../render/node";

// The control's own look under the caller's `style`, both read inside one reactive thunk.
export function layered(base: () => Style, user: Accessor<Style> | null): () => Style {
	const style = accessor((): Style => {
		if (user === null) { return base(); }
		return layerStyles([base(), (user as () => Style)()]);
	});
	return style as () => Style;
}

// RN components default their role; an explicit `accessibilityRole` prop replaces it.
export function defaultRole(attrs: VAttr[], undeclared: boolean, role: string): void {
	if (!undeclared) { return; }
	attrs.push(dynAttr("accessibilityRole", (): string | null => role));
}
