import { el, text, renderToString } from "../src/render/node";

test "static only" {
	const v = el("div", [], [], [el("p", [], [], [text("hi")])]);
	assert renderToString(v) === "<div><p>hi</p></div>", "static serialize";
}
