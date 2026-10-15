when (js) {
	import { accessor, Accessor } from "../../src/core/signal";
	import { renderToString } from "../../src/render/ssr";
	import {
		publishPageScroll,
		ScrollPosition,
		useWindowScrollPosition,
		useWindowScrollRange,
	} from "../../src/api/pageScroll";

	extern function documentIsAbsent(): boolean from "(typeof document === 'undefined')";

	function shareOf(): Accessor<number> {
		const position = useWindowScrollPosition();
		const range = useWindowScrollRange();
		return accessor((): number => range().y > 0 ? position().y / range().y : 0);
	}

	function pair(at: ScrollPosition): string {
		return at.x.toString() + "," + at.y.toString();
	}

	test "server rendering reads zero and nothing has touched a document or window" {
		assert documentIsAbsent(), "this lane runs without a document";
		const position = useWindowScrollPosition();
		const range = useWindowScrollRange();
		const share = shareOf();
		const line = pair(position()) + " of " + pair(range()) + " = " + share().toString();
		const html = renderToString(<p>{line}</p>);
		assert html === "<p>0,0 of 0,0 = 0</p>", "markup: " + html;
	}

	test "the published offset and range reach the accessors and a derived share" {
		const position = useWindowScrollPosition();
		const range = useWindowScrollRange();
		const share = shareOf();
		publishPageScroll(10, 300, 40, 1200);
		assert pair(position()) === "10,300", "offset: " + pair(position());
		assert pair(range()) === "40,1200", "range: " + pair(range());
		assert share() === 0.25, "share: " + share().toString();
		publishPageScroll(0, 0, 0, 0);
		assert share() === 0, "no range reads as zero, not NaN";
	}
}
