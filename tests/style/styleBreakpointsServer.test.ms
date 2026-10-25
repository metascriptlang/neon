import { NeonNode } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { resetCss, mountSheet } from "../../src/render/sheet";
import { publishWindow } from "../../src/render/environment";
import { screen } from "./styleBreakpointsTable";

const sheet = createStyles({
	sidebar: { width: "100%", when: { [screen.wide]: { width: 280 } } },
});

function Narrow(): NeonNode {
	publishWindow(412, 800);
	return <div style={[sheet.sidebar, { opacity: 0.5 }]}></div>;
}

function Wide(): NeonNode {
	publishWindow(1440, 800);
	return <div style={[sheet.sidebar, { opacity: 0.5 }]}></div>;
}

test "the server registers each block inside the class rule as a media query" {
	resetCss();
	const html = renderToString(<div style={sheet.sidebar}></div>);
	const id = sheet.sidebar.cssId as string;
	assert html === "<div class=\"" + id + "\"></div>", html;
	const want = "<style>." + id + "{width:100%;}@media (min-width:900px){." + id + "{width:280px;}}</style>";
	assert mountSheet() === want, mountSheet();
}

test "an inline style with blocks resolves against the window its render publishes" {
	const narrow = renderToString(<Narrow />);
	assert narrow === "<div style=\"width:100%;opacity:0.5;\"></div>", narrow;
	const wide = renderToString(<Wide />);
	assert wide === "<div style=\"width:280px;opacity:0.5;\"></div>", wide;
}

test "an inline style with blocks renders its base when no window is published" {
	const html = renderToString(<div style={[sheet.sidebar, { opacity: 0.5 }]}></div>);
	assert html === "<div style=\"width:100%;opacity:0.5;\"></div>", html;
}
