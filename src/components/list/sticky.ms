export function stickyTranslation(layoutY: float64, height: float64, nextHeaderY: float64 | null, scrollOffset: float64, viewport: float64, inverted: boolean): float64 {
	if (scrollOffset < 0.0) { return 0.0; }
	if (inverted) {
		const start = layoutY + height - viewport;
		if (start <= 0.0) { return 0.0; }
		const translation = Math.max(0.0, scrollOffset - start);
		if (nextHeaderY !== null) {
			const collision = nextHeaderY - height - viewport;
			if (collision > start) { return Math.min(translation, collision - start); }
		}
		return translation;
	}
	const translation = Math.max(0.0, scrollOffset - layoutY);
	if (nextHeaderY !== null) {
		const collision = nextHeaderY - height;
		if (collision >= layoutY) { return Math.min(translation, collision - layoutY); }
	}
	return translation;
}
