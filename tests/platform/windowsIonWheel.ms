when (windows && !js) {
	import { runNativeWindow, nativeWindowOptions } from "../../src/platform/windows/ion";
	import { closeWindow, onPointer, PointerKind, PointerEvent, Window } from "../../../ion/src/index";
	import { requestFrame } from "../../src/animation/frame";
	import { View, ScrollView } from "../../src/components/primitives";
	import { NeonNode } from "../../src/render/node";
	import { NeonEvent } from "../../src/render/event";
	import { element } from "../../src/macros/ui/element";
	import { nwiQueueWheelFrame } from "./windowsIonWheel.h";
	@compile("./windowsIonWheel.c");

	test "Ion queued wheel reports before its first native motion frame" {
		let reported = -1.0;
		let firstMotionReport = -1.0;
		let sampled = false;
		let timedOut = false;
		let queued: int32 = 0;
		let watchdog: number = 0;
		const app = (): NeonNode => element(<ScrollView style={{ width: 180, height: 180 }}
			onScroll={(e: NeonEvent): void => { reported = e.y; }}>
			<View style={{ height: 600 }} />
		</ScrollView>);
		const result = runNativeWindow(nativeWindowOptions("Neon queued wheel pin", 220, 220), app, (win: Window): void => {
			onPointer((e: PointerEvent): void => {
				if (e.window !== win.id || e.kind !== PointerKind.Wheel || sampled) { return; }
				requestFrame((time: number): void => {
					firstMotionReport = reported;
					sampled = true;
					clearTimeout(watchdog);
					setTimeout((): void => { closeWindow(win); }, 0);
				});
			});
			watchdog = setTimeout((): void => {
				timedOut = true;
				closeWindow(win);
			}, 2000);
			queued = nwiQueueWheelFrame(win.id);
			if (queued !== 2) { closeWindow(win); }
		});
		clearTimeout(watchdog);
		assert result === 0, `native window setup: ${result}`;
		assert queued === 2, `wheel/frame queue insertion: ${queued}`;
		assert !timedOut && sampled, "the queued frame reaches the app callback";
		assert firstMotionReport === 120, `scroll report at first motion: ${firstMotionReport}`;
	}
}
