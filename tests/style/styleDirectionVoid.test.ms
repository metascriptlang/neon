import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { createVoidHost, layoutPass, VoidNode } from "../../src/platform/void/host";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { Style } from "../../src/render/style";
import { I18nManager } from "../../src/api/i18nManager";

const sheet = createStyles({
	row: { flexDirection: "row", width: 200, height: 40 },
	rtl: { flexDirection: "row", direction: "rtl", width: 200, height: 40 },
	cell: { width: 50, height: 40 },
});

function firstCellX(box: Style, rootRtl: boolean): float32 {
	I18nManager.forceRTL(rootRtl);
	const app = element(
		<div style={box}>
			<p style={sheet.cell}>a</p>
			<p style={sheet.cell}>b</p>
		</div>
	);
	const vh = createVoidHost();
	I18nManager.forceRTL(false);
	render(app, vh.host, vh.root);
	vh.layout(200.0, 40.0);
	return (vh.root as VoidNode).children[0].children[0].ref.local().x;
}

test "a row with direction rtl lays its first child at the right edge" {
	assert firstCellX(sheet.rtl, false) === 150.0, "style direction mirrors the cells";
}

test "a row keeps its first child at the left edge under the default root direction" {
	assert firstCellX(sheet.row, false) === 0.0, "ltr cells";
}

test "forceRTL gives the host's root layout direction rtl, which a row inherits" {
	assert firstCellX(sheet.row, true) === 150.0, "root rtl mirrors an inheriting row";
}
