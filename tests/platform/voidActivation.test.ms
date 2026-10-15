import { createVoidHostWith } from "../../src/platform/void/host";
import { Scene2D } from "../../../void/src/void2d/node";
import { create } from "../../../void/src/void2d/scene";
import { rgba } from "../../../void/src/void2d/types";
import { DEFAULT_FONT } from "../../../void/src/void2d/font";
import { createRoot } from "../../src/core/owner";
import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { Pressable } from "../../src/components/primitives";
import { NeonEvent } from "../../src/render/event";
import { sleepAsync } from "std/core/promise";

test "Void down clickAt up activates gesture only on release and keeps cheap clickAt" {
	const vh = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), DEFAULT_FONT);
	let hits = 0;
	const dispose = createRoot((end: () => void): () => void => {
		render(element(<Pressable style={{ width: 100, height: 50 }}
			onPressIn={(e: NeonEvent): void => {
				assert e.pointerOrigin, "Void pointerEvent tags down";
			}}
			onPress={(e: NeonEvent): void => {
				assert e.pointerOrigin, "Void pointerEvent tags up";
				hits += 1;
			}} />), vh.host, vh.root);
		return end;
	});
	vh.layout(200.0, 100.0);
	vh.pointerDown(10.0, 10.0, 1);
	vh.clickAt(10.0, 10.0);
	assert hits === 0, "physical down/clickAt must not activate prematurely";
	vh.pointerUp(10.0, 10.0, 1);
	assert hits === 1, "release activates once";
	vh.clickAt(10.0, 10.0);
	assert hits === 1, "additional physical click is not semantic activation";
	dispose();
	vh.clickAt(10.0, 10.0);
	assert hits === 1, "removed gesture routes stay inert";

	const control = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), DEFAULT_FONT);
	const cheap = render(element(<Pressable style={{ width: 100, height: 50 }}
		onPress={(e: NeonEvent): void => {
			assert e.pointerOrigin, "Void clickAt tags physical press";
			hits += 1;
		}} />), control.host, control.root);
	control.layout(200.0, 100.0);
	control.clickAt(10.0, 10.0);
	assert hits === 2, "cheap physical producer control";
	cheap();
}

test "Void long down clickAt up does not resurrect press" {
	const vh = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), DEFAULT_FONT);
	const [log, setLog] = createSignal("");
	const dispose = render(element(<Pressable style={{ width: 100, height: 50 }}
		delayLongPress={60}
		onLongPress={(): void => { setLog(log() + "long;"); }}
		onPress={(): void => { setLog(log() + "press;"); }} />), vh.host, vh.root);
	vh.layout(200.0, 100.0);
	vh.pointerDown(10.0, 10.0, 1);
	vh.clickAt(10.0, 10.0);
	await sleepAsync(180);
	vh.pointerUp(10.0, 10.0, 1);
	vh.clickAt(10.0, 10.0);
	assert log() === "long;", "long gesture stays suppressed: " + log();
	dispose();
}
