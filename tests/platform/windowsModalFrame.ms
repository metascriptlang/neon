when (windows && !js) {
	import { runNativeWindow, nativeWindowOptions } from "../../src/platform/windows/ion";
	import { closeWindow, onFrame, Window } from "../../../ion/src/index";
	import { View } from "../../src/components/primitives";
	import { Modal, ModalAnimationType } from "../../src/components/modal";
	import "../../src/platform/native/modal";
	import { createSignal } from "../../src/core/signal";
	import { requestFrame, cancelFrame } from "../../src/animation/frame";
	import { NeonNode } from "../../src/render/node";
	import { element } from "../../src/macros/ui/element";
	import { nmfPrepareWindow, nmfQueueFrame, nmfSampleFrame } from "./windowsModalFrame.h";
	@compile("./windowsModalFrame.c");
	@passL("-ldwmapi");
	@passL("-lgdi32");

	when (modalSlide) {
		const animationType: ModalAnimationType = "slide";
	} else {
		const animationType: ModalAnimationType = "fade";
	}

	function checkModalTarget(): void {
		if (nmfPrepareWindow() !== (0 as int32)) {
			throw new Error("native window pre-show hook setup");
		}
		const title = "Neon modal target pin";
		let mountStart = 0.0;
		let elapsed = 0.0;
		let target = -1.0;
		let marker: int32 = 0;
		let markerColor = "#000000";
		const [receipt, setReceipt] = createSignal<string>("#000000");
		let stampRequest: int32 = 0;
		let pixels: int32 = -1;
		let sampled = false;
		let timedOut = false;
		let receiptTimedOut = false;
		let captureFailed = false;
		let watchdog: number = 0;
		let receiptTimer: number = 0;
		function stamp(time: number): void {
			if (time === target) { setReceipt(markerColor); }
			else { stampRequest = requestFrame(stamp); }
		}
		const app = (): NeonNode => {
			mountStart = performance.now();
			return element(<View style={{ width: 220, height: 220, backgroundColor: "#000000" }}>
				<Modal animationType={animationType}>
					<View style={{ width: 180, height: 180, backgroundColor: "#00ff00" }} />
				</Modal>
				<Modal animationType="none" transparent={true}>
					<View style={{ position: "absolute", left: 200, top: 200, width: 8, height: 8, backgroundColor: receipt() }} />
				</Modal>
			</View>);
		};
		const result = runNativeWindow(nativeWindowOptions(title, 220, 220), app, (win: Window): void => {
			function sampleReceipt(): void {
				elapsed = performance.now() - mountStart;
				if (elapsed >= 200) {
					receiptTimedOut = true;
					closeWindow(win);
					return;
				}
				const status = nmfSampleFrame(win.id, marker);
				if (status === (0 as int32)) {
					receiptTimer = setTimeout(sampleReceipt, 1);
					return;
				}
				captureFailed = status !== (1 as int32) && status !== (2 as int32);
				pixels = status === (1 as int32) ? 0 : 1;
				elapsed = performance.now() - mountStart;
				clearTimeout(watchdog);
				closeWindow(win);
			}
			onFrame((id: int32, time: float64): void => {
				if (id !== win.id || time !== target || sampled) { return; }
				sampled = true;
				receiptTimer = setTimeout(sampleReceipt, 0);
			});
			watchdog = setTimeout((): void => { timedOut = true; closeWindow(win); }, 2000);
			target = nmfQueueFrame(win.id);
			if (target <= 0) { closeWindow(win); return; }
			marker = ((target as int64) % (0xfffffe as int64)) as int32 + 1;
			markerColor = "#" + marker.toString(16).padStart(6, "0");
			stampRequest = requestFrame(stamp);
		});
		cancelFrame(stampRequest);
		clearTimeout(watchdog);
		clearTimeout(receiptTimer);
		if (result !== 0 || target <= 0) {
			throw new Error("native window and synthetic frame setup");
		}
		if (!sampled || timedOut) {
			throw new Error("the target frame did not reach the app");
		}
		if (captureFailed) { throw new Error("frame capture ownership or device failure"); }
		if (receiptTimedOut) { throw new Error("target frame marker was not observed before 200ms"); }
		if (elapsed >= 200) {
			throw new Error(`sample must precede wall-time completion: ${elapsed}ms`);
		}
		if (pixels !== 0) {
			throw new Error("the supplied target did not finish the modal transition");
		}
		console.log("modal frame target PASS", animationType, elapsed);
	}

	when (testBuild) {
		test "Windows modal transitions sample the frame target rather than callback time" {
			checkModalTarget();
		}
	} else {
		checkModalTarget();
	}
}
