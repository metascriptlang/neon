import { element } from "../../src/macros/ui/element";
import { el, NeonNode } from "../../src/render/node";
import { mockHost, mockNode, render, HostNode, MockNode } from "../../src/render/host";
import { Style, mergeStyle } from "../../src/render/style";
import { resolveMedia } from "../../src/render/breakpoints";
import { publishWindow } from "../../src/render/environment";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { screen } from "./styleBreakpointsTable";

const FRAME: Style = { position: "relative", borderWidth: 1, boxShadow: "4px 4px 0 #ff6b35" };

const sheet = createStyles({
	framed: { ...FRAME, borderWidth: 2, when: { [screen.wide]: { boxShadow: "6px 6px 0 #00d4ff" } } },
	sidebar: {
		width: "100%",
		when: {
			[screen.xl]: { width: 400 },
			[screen.wide]: { width: 280, padding: 8 },
		},
	},
	plain: { width: 10 },
});

when (js) {
	const onWeb = true;
} else {
	const onWeb = false;
}

function mounted(n: NeonNode): MockNode {
	const root = mockNode("root");
	render(n, mockHost(), root as unknown as HostNode);
	return root.children[0];
}

test "a breakpoint reads as its number" {
	assert screen.wide === 900 && screen.xl === 1200, "the table keeps its values";
}

test "the blocks are kept in ascending order whatever the source order" {
	const m = sheet.sidebar.media;
	assert m !== null && m.length === 2, "two blocks";
	assert m[0].fromWidth === 900 && m[1].fromWidth === 1200, "ascending";
	assert m[0].width === 280 && m[1].width === 400, "each block keeps its fields";
	assert sheet.plain.media === null, "an entry without a breakpoint carries none";
}

test "the base fields stay unconditional" {
	assert sheet.sidebar.width === "100%", "base width";
	assert sheet.sidebar.padding === null, "a block field is not in the base";
}

test "the web rule bakes every block as a min-width media query" {
	if (!onWeb) { return; }
	const id = sheet.sidebar.cssId as string;
	const want = "." + id + "{width:100%;}"
		+ "@media (min-width:900px){." + id + "{width:280px;padding:8px;}}"
		+ "@media (min-width:1200px){." + id + "{width:400px;}}";
	assert sheet.sidebar.css === want, "got " + (sheet.sidebar.css as string);
}

test "a spread base reaches the entry and its class rule, a later field overrides it" {
	assert sheet.framed.position === "relative" && sheet.framed.borderWidth === 2, "the base fields and the override";
	if (!onWeb) { return; }
	const id = sheet.framed.cssId as string;
	const want = "." + id + "{position:relative;border-width:2px;box-shadow:4px 4px 0 #ff6b35;}"
		+ "@media (min-width:900px){." + id + "{box-shadow:6px 6px 0 #00d4ff;}}";
	assert sheet.framed.css === want, "got " + (sheet.framed.css as string);
}

test "resolving picks every block the width reaches, wider last" {
	assert resolveMedia(sheet.sidebar, 500).width === "100%", "below the first breakpoint";
	assert resolveMedia(sheet.sidebar, 900).width === 280, "at the breakpoint";
	assert resolveMedia(sheet.sidebar, 1300).width === 400, "the wider block wins";
	assert resolveMedia(sheet.sidebar, 1300).padding === 8, "a narrower block's other field survives";
	assert resolveMedia(sheet.sidebar, 1300).media === null, "the resolved style carries no blocks";
}

test "a later layer outranks the blocks of an earlier one" {
	const merged = mergeStyle(sheet.sidebar, styleOf({ width: 50, opacity: 0.5 }));
	assert resolveMedia(merged, 1300).width === 50, "the over layer wins at every width";
	assert resolveMedia(merged, 1300).padding === 8, "a block field the over layer leaves unset applies";
	assert resolveMedia(merged, 500).opacity === 0.5, "the over field applies below the breakpoint";
}

test "a later layer's own blocks apply after the earlier layer's" {
	const merged = mergeStyle(styleOf({ width: 1 }), sheet.sidebar);
	assert resolveMedia(merged, 500).width === "100%", "the later base wins";
	assert resolveMedia(merged, 1000).width === 280, "the later layer's block applies";
}

test "a host without a stylesheet follows the window width" {
	publishWindow(500, 800);
	const n = mounted(element(<div style={sheet.sidebar}></div>));
	assert (n.style as Style).width === "100%", "narrow window";
	publishWindow(1000, 800);
	assert (n.style as Style).width === 280, "wide window";
	publishWindow(1300, 800);
	assert (n.style as Style).width === 400, "wider window";
	publishWindow(0, 0);
}

test "a layered sheet entry follows the window width too" {
	publishWindow(500, 800);
	const n = mounted(element(<div style={[sheet.sidebar, { opacity: 0.5 }]}></div>));
	assert (n.style as Style).width === "100%", "narrow window";
	publishWindow(1000, 800);
	assert (n.style as Style).width === 280 && (n.style as Style).opacity === 0.5, "wide window keeps the layer";
	publishWindow(0, 0);
}
