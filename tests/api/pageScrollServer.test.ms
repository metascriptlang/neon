when (js) {
	import { accessor, Accessor } from "../../src/core/signal";
	import { renderToString } from "../../src/render/ssr";
	import { ScrollPosition, useWindowScrollPosition, useWindowScrollRange } from "../../src/api/pageScroll";

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
}
