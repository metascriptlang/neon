import { createStyles, styleOf } from "../../src/macros/ui/style";
import { styleToCss } from "../../src/render/css";

const sheet = createStyles({
	rtl: { flexDirection: "row", direction: "rtl", width: 200, height: 40 },
	para: { writingDirection: "rtl" },
});

test "direction and writingDirection both spell the CSS direction property" {
	assert styleToCss(sheet.rtl).indexOf("direction:rtl;") >= 0, styleToCss(sheet.rtl);
	assert styleToCss(sheet.para) === "direction:rtl;", styleToCss(sheet.para);
	when (js) {
		assert sheet.para.css !== null && (sheet.para.css as string).indexOf("{direction:rtl;}") >= 0, "baked rule";
	}
}
