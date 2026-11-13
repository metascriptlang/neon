import { runApp } from "../../src/platform/native/host";
import { setVoidAreaFont } from "../../src/platform/native/voidArea";
import { NeonNode } from "../../src/render/node";
import { View, Text, Void } from "../../src/components/primitives";
import { VoidAreaHandle, AreaPointerEvent } from "../../src/render/voidAreaHandle";
import { nmTeardown, nmVoidAreas, nmVoidAreaTouch, nmHasLabel } from "./nativeBridgeMock.h";

const TOUCH_BEGAN: int32 = 1;
const TOUCH_ENDED: int32 = 3;

test "a <Void> on the native host opens an area in its own native view, and a tap on that view reaches the area as a press" {
	setVoidAreaFont({ font: "../void/assets/font.ttf", fontFamily: null, fontBytes: null, defaultFontBytes: null });
	const presses: string[] = [];
	let handle: VoidAreaHandle | null = null;
	const app = (): NeonNode => <View>
		<Text>beside</Text>
		<Void style={{ height: 100 }} fallback={<Text>fallback</Text>}
			ref={(h: VoidAreaHandle): void => { handle = h; }}>
			<View />
		</Void>
	</View>;
	runApp(app);
	assert nmVoidAreas() === 1, `area views ${nmVoidAreas()}`;
	assert nmHasLabel("beside") === 1 && nmHasLabel("fallback") === 0, "the area mounts instead of its fallback";
	assert handle !== null, "the area's handle reaches its ref";
	(handle as VoidAreaHandle).onPointer((e: AreaPointerEvent): void => { presses.push(`${e.pressed} ${e.pixelX},${e.pixelY}`); });
	nmVoidAreaTouch(TOUCH_BEGAN, 30, 40);
	nmVoidAreaTouch(TOUCH_ENDED, 30, 40);
	assert presses.join("|") === "true 30,40|false 30,40", presses.join("|");
	nmTeardown();
	assert nmVoidAreas() === 0, "teardown releases the area's native view";
}
