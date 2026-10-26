import { runApp } from "../../src/platform/native/host";
import { View, Pressable } from "../../src/components/primitives";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { I18nManager } from "../../src/api/i18nManager";
import { nmTeardown, nmPaintTag, nmLayoutX } from "./nativeBridgeMock.h";

function mountRow(): int32 {
	const app = (): NeonNode => <View style={{ width: 300, height: 40, flexDirection: "row" }} onLayout={(e: NeonEvent): void => {}}>
		<Pressable style={{ width: 100, height: 40 }} onPress={() => {}} />
		<Pressable style={{ width: 100, height: 40 }} onPress={() => {}} />
	</View>;
	runApp(app);
	return nmPaintTag(0, 0);
}

test "a row lays out left to right at the root's default direction" {
	const row = mountRow();
	assert nmLayoutX(nmPaintTag(row, 0)) === 0 && nmLayoutX(nmPaintTag(row, 1)) === 100, "ltr cells";
	nmTeardown();
}

test "forceRTL mirrors the row: the first child sits at the right edge" {
	I18nManager.forceRTL(true);
	const row = mountRow();
	assert nmLayoutX(nmPaintTag(row, 0)) === 200, "first cell at the right edge";
	assert nmLayoutX(nmPaintTag(row, 1)) === 100, "second cell to its left";
	nmTeardown();
	I18nManager.forceRTL(false);
}
