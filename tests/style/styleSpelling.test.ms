import { createStyles, styleOf } from "../../src/macros/ui/style";
import { Style } from "../../src/render/style";
import { styleToCss } from "../../src/render/css";
import { STYLE_TABLE } from "../../src/macros/style/fields";

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
		textDecorationColor: "#444",
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
	assert declarations(styleToCss(sheet.every)).length === STYLE_TABLE.length, styleToCss(sheet.every);
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
