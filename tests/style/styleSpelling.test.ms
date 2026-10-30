import { createStyles, styleOf } from "../../src/macros/ui/style";
import { Style } from "../../src/render/style";
import { styleToCss } from "../../src/render/css";
import { styleTable } from "../../src/macros/style/fields";

const sheet = createStyles({
	every: {
		flexDirection: "row", justifyContent: "center", alignItems: "center", alignSelf: "auto",
		alignContent: "stretch", position: "relative", flexWrap: "wrap", display: "flex",
		flex: 1, flexGrow: 2, flexShrink: 0, flexBasis: 10,
		width: 11, height: 12, minWidth: 13, minHeight: 14, maxWidth: 15, maxHeight: 16, aspectRatio: 1.5,
		margin: 1, marginTop: 2, marginBottom: 3, marginLeft: 4, marginRight: 5,
		padding: 6, paddingTop: 7, paddingBottom: 8, paddingLeft: 9, paddingRight: 10,
		top: 17, left: 18, right: 19, bottom: 20, gap: 21, rowGap: 22, columnGap: 23,
		backgroundColor: "#111", backgroundImage: "none", borderWidth: 1, borderColor: "#222", borderRadius: 4,
		opacity: 0.5, color: "#333", fontSize: 12, fontWeight: "bold", letterSpacing: 0.5, lineHeight: 18,
		textAlign: "left", overflow: "hidden", zIndex: 3, fontFamily: "serif", transform: "rotate(1deg)",
		cursor: "pointer", boxShadow: "none", clipPath: "none", transition: "none", filter: "none",
		pointerEvents: "none", fontStyle: "italic", textDecorationLine: "underline", textDecorationStyle: "wavy",
		textDecorationColor: "#444", direction: "rtl", writingDirection: "auto",
		marginHorizontal: 24, marginVertical: 25, marginStart: 26, marginEnd: 27,
		paddingHorizontal: 28, paddingVertical: 29, paddingStart: 30, paddingEnd: 31, inset: 32, start: 33, end: 34,
		backgroundSize: "cover", backgroundPosition: "center", backgroundRepeat: "no-repeat",
		borderTopWidth: 1, borderRightWidth: 2, borderBottomWidth: 3, borderLeftWidth: 4, borderStartWidth: 5, borderEndWidth: 6,
		borderTopColor: "#501", borderRightColor: "#502", borderBottomColor: "#503", borderLeftColor: "#504",
		borderStartColor: "#505", borderEndColor: "#506",
		borderTopLeftRadius: 1, borderTopRightRadius: 2, borderBottomRightRadius: 3, borderBottomLeftRadius: 4,
		borderTopStartRadius: 5, borderTopEndRadius: 6, borderBottomStartRadius: 7, borderBottomEndRadius: 8,
		borderStyle: "dashed", outlineWidth: 2, outlineColor: "#600", outlineStyle: "dotted", outlineOffset: 3, boxSizing: "border-box",
		backdropFilter: "blur(4px)", mixBlendMode: "multiply", isolation: "isolate", backfaceVisibility: "hidden",
		transformOrigin: "top left", userSelect: "none", textTransform: "uppercase", whiteSpace: "nowrap",
		textDecorationThickness: 2, textUnderlineOffset: "0.2em", objectFit: "cover", listStyleType: "disc",
		borderCollapse: "collapse", borderSpacing: 4, overflowX: "clip", overflowY: "auto",
		fontSizeAdjust: "ic-width from-font",
	},
	lengthsAsText: { flexBasis: "auto", width: "50%", margin: "auto", top: "10%" },
	emptyValues: { color: "", width: "", opacity: 0.5 },
	longhandFirst: { paddingLeft: 24, padding: 8, flexGrow: 0, flex: 1, rowGap: 4, gap: 2, marginTop: 3, margin: 1 },
	shorthandFirst: { padding: 8, paddingLeft: 24, flex: 1, flexGrow: 0, gap: 2, rowGap: 4, margin: 1, marginTop: 3 },
});

function declarations(body: string): string[] {
	const out: string[] = [];
	let start = 0;
	for (let i = 0; i < body.length; i += 1) {
		if (body.charAt(i) === ";") {
			out.push(body.substring(start, i + 1));
			start = i + 1;
		}
	}
	return out;
}

function bakedBody(s: Style): string {
	if (s.css === null || s.cssId === null) { return "<inline>"; }
	const css = s.css as string;
	const head = "." + (s.cssId as string) + "{";
	return css.substring(head.length, css.length - 1);
}

function sameDeclarations(s: Style): string {
	const baked = bakedBody(s);
	const runtime = styleToCss(s);
	const b = declarations(baked);
	const r = declarations(runtime);
	if (b.length !== r.length) { return "baked " + baked + " vs runtime " + runtime; }
	for (const d of b) {
		if ((";" + runtime).indexOf(";" + d) < 0) { return "baked " + d + " missing from runtime " + runtime; }
	}
	return "";
}

test "the sweep entry sets every row of the style table" {
	assert declarations(styleToCss(sheet.every)).length === styleTable().length, styleToCss(sheet.every);
}

test "fontSizeAdjust reaches CSS as font-size-adjust, its value unchanged" {
	assert styleToCss(sheet.every).indexOf("font-size-adjust:ic-width from-font;") >= 0, styleToCss(sheet.every);
}

test "the baked rule spells every table field as the runtime does" {
	when (js) {
		assert sameDeclarations(sheet.every) === "", sameDeclarations(sheet.every);
		assert sameDeclarations(sheet.lengthsAsText) === "", sameDeclarations(sheet.lengthsAsText);
	}
}

test "an empty value bakes no declaration, as the runtime writes none" {
	when (js) {
		assert sameDeclarations(sheet.emptyValues) === "", sameDeclarations(sheet.emptyValues);
	}
}

test "a longhand wins over its shorthand in the baked rule whatever the source order, as inline" {
	when (js) {
		const inline = "flex:1;flex-grow:0;margin:1px;margin-top:3px;padding:8px;padding-left:24px;gap:2px;row-gap:4px;";
		assert styleToCss(sheet.longhandFirst) === inline && styleToCss(sheet.shorthandFirst) === inline, styleToCss(sheet.longhandFirst);
		assert bakedBody(sheet.longhandFirst) === inline, bakedBody(sheet.longhandFirst);
		assert bakedBody(sheet.shorthandFirst) === inline, bakedBody(sheet.shorthandFirst);
	}
}
