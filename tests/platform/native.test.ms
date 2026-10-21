import { NativeElementKind, createNativeEventRegistry, nativeComponentOf, nativeElementKind, nativeFlexStyle, nativeTransform } from "../../src/platform/native/contract";
import { nativeElement, registerNativeElement } from "../../src/platform/native/elements";
import { Style } from "../../src/render/style";
import { NeonEvent } from "../../src/render/event";

test "native tags select view-backed element kinds" {
	assert nativeElementKind("text") === NativeElementKind.Text, "text uses a label view";
	assert nativeElementKind("view") === NativeElementKind.View, "view uses a view";
	assert nativeElementKind("pressable") === NativeElementKind.View, "pressable uses a touch-routed view";
	assert nativeElementKind("custom") === NativeElementKind.View, "unknown tags use the view escape hatch";
	assert nativeElementKind("scrollview") === NativeElementKind.Scroll, "scrollview uses the platform scroll container";
	assert nativeElementKind("image") === NativeElementKind.Image, "image is a primitive the host core creates";
	for (const tag of ["switch", "activityindicator", "modal", "webview", "video", "camera", "svg"]) {
		assert nativeElementKind(tag) === NativeElementKind.Component, `${tag} is rendered by its component's module`;
	}
}

test "a component tag no module registered names the component to import" {
	let message = "";
	try {
		nativeElement("video", nativeComponentOf("video"));
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "native host: <video> has no renderer on this host; import Video from src/components/video, on a platform that renders it", message;
}

test "a registered component tag creates through its module and refuses a second registration" {
	registerNativeElement("probe", { create: (): Ptr<void> | null => null, sizesItself: true });
	assert nativeElement("probe", "Probe").sizesItself, "the registered entry comes back";
	let message = "";
	try {
		registerNativeElement("probe", { create: (): Ptr<void> | null => null, sizesItself: false });
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "registerNativeElement: <probe> is registered twice", message;
}

test "native styles project onto FlexStyle without filling absent fields" {
	const projected = nativeFlexStyle({
		width: 320,
		flexGrow: 1,
		flexDirection: "row",
		alignItems: "center",
		marginTop: 8,
		paddingLeft: 4,
		overflow: "hidden",
	} as Style, NativeElementKind.View);
	assert projected.width === 320, "width reaches flex";
	assert projected.flexGrow === 1, "flexGrow reaches flex";
	assert projected.flexDirection === "row", "flexDirection reaches flex";
	assert projected.alignItems === "center", "alignItems reaches flex";
	assert projected.marginTop === 8, "marginTop reaches flex";
	assert projected.paddingLeft === 4, "paddingLeft reaches flex";
	assert projected.overflow === "hidden", "overflow reaches flex";
	assert projected.maxWidth === null, "absent maxWidth stays absent";

	const container = nativeFlexStyle({} as Style, NativeElementKind.View);
	const text = nativeFlexStyle({} as Style, NativeElementKind.Text);
	const scroll = nativeFlexStyle({ overflow: "hidden" } as Style, NativeElementKind.Scroll);
	assert container.flexDirection === "column", "containers default to columns";
	assert text.flexDirection === null, "text keeps Yoga's direction default";
	assert scroll.flexDirection === "column" && scroll.overflow === "scroll", "a scroll container lays out its content unshrunk";
}

test "native event capture retains actual legs and scalar samples across removal and replacement" {
	for (const throwing of [false, true]) {
		const registry = createNativeEventRegistry();
		let log = "";
		registry.addPhases(7, "onTouchEnd", (e: NeonEvent): void => {
			log += `life:${e.x},${e.timeStamp};`;
			e.x = 99;
			if (throwing) { throw "capture stop"; }
		}, (e: NeonEvent): void => { log += `old:${e.x},${e.timeStamp};`; });
		const packet = registry.capture(7, 1, 5, 6, 160020, true);
		registry.remove(7);
		registry.add(7, "onTouchEnd", (): void => { log += "new;"; });
		let error = "";
		try {
			for (const delivery of packet.lifecycle) { delivery.handler(delivery.event); }
			for (const delivery of packet.listeners) { delivery.handler(delivery.event); }
		} catch (e) { error = e.toString(); }
		assert log === (throwing ? "life:5,160020;" : "life:5,160020;old:5,160020;"), log;
		assert throwing ? error.includes("capture stop") : error === "", error;
		registry.touch(7, 1, 5, 6, 160040);
		assert log.endsWith("new;"), log;
	}
}

test "native phased layout and control registrations keep lifecycle before listener" {
	const registry = createNativeEventRegistry();
	let log = "";
	registry.addPhases(9, "onLayout", (): void => { log += "layout-life;"; },
		(): void => { log += "layout-user;"; });
	registry.addPhases(9, "onValueChange", (): void => { log += "control-life;"; },
		(): void => { log += "control-user;"; });
	registry.layout(9, 0, 0, 10, 20);
	registry.control(9, 4, "true", 0, 0);
	assert log === "layout-life;layout-user;control-life;control-user;", log;
}

test "native cancellation capture retains both public cancel and leave channels" {
	const registry = createNativeEventRegistry();
	let log = "";
	registry.add(8, "onPointerCancel", (): void => { log += "cancel;"; });
	registry.add(8, "onPointerLeave", (): void => { log += "leave;"; });
	const packet = registry.capture(8, 3, 1, 2, 3, false);
	registry.remove(8);
	for (const delivery of packet.listeners) { delivery.handler(delivery.event); }
	assert log === "cancel;leave;", log;
}

test "native event registry routes native tags and touch phases" {
	const registry = createNativeEventRegistry();
	let got = "";
	let downX: number = 0;
	let downY: number = 0;
	registry.add(7, "onPointerDown", (e: NeonEvent): void => {
		got += e.type + ";";
		downX = e.x;
		downY = e.y;
	});
	registry.add(7, "onPress", (e: NeonEvent): void => { got += e.type + ";"; });

	assert registry.dispatch(99, 2, 0, 0, 0) === false, "unknown tags are ignored";
	assert registry.dispatch(7, 0, 12, 9, 0), "known pointer-down dispatches";
	assert registry.dispatch(7, 2, 0, 0, 0), "known press dispatches";
	assert got === "pointerdown;press;", got;
	assert downX === 12 && downY === 9, "pointer coordinates reach the handler";
	registry.remove(7);
	assert registry.dispatch(7, 2, 0, 0, 0) === false, "removed tags no longer dispatch";
}

test "native event registry routes a scroll with React Native's payload" {
	const registry = createNativeEventRegistry();
	let got = "";
	registry.add(5, "onScroll", (e: NeonEvent): void => {
		got = `${e.type} ${e.x} ${e.y} ${e.width} ${e.height} ${e.contentWidth} ${e.contentHeight}`;
	});
	assert registry.scroll(99, 0, 0, 0, 0, 0, 0) === false, "unknown tags are ignored";
	assert registry.scroll(5, 0, 40, 320, 480, 320, 1200), "a known scroll dispatches";
	assert got === "scroll 0 40 320 480 320 1200", "payload: " + got;
}

test "native event registry routes a layout with the frame" {
	const registry = createNativeEventRegistry();
	let got = "";
	registry.add(4, "onLayout", (e: NeonEvent): void => { got = `${e.type} ${e.x} ${e.y} ${e.width} ${e.height}`; });
	assert registry.layout(99, 0, 0, 1, 1) === false, "unknown tags are ignored";
	assert registry.layout(4, 8, 16, 320, 48), "a known layout dispatches";
	assert got === "layout 8 16 320 48", "frame: " + got;
}

test "native transform reset and RN inversion coefficients" {
	const absent = nativeTransform(null);
	const none = nativeTransform(" \tnone\n");
	assert absent.scaleX === 1 && absent.scaleY === 1 && absent.translateX === 0 && absent.translateY === 0, "null is identity";
	assert none.scaleX === 1 && none.scaleY === 1 && none.translateX === 0 && none.translateY === 0, "none is the same identity";
	const vertical = nativeTransform("scaleY(-1)");
	const horizontal = nativeTransform("scaleX(-1)");
	const both = nativeTransform("scale(-1)");
	assert vertical.scaleX === 1 && vertical.scaleY === -1, "vertical inversion";
	assert horizontal.scaleX === -1 && horizontal.scaleY === 1, "horizontal inversion";
	assert both.scaleX === -1 && both.scaleY === -1, "RN Android uniform inversion";
}

test "native transform composes CSS order instead of adding raw translations" {
	const scaleFirst = nativeTransform("scale(2, 3) translate(10px, -4px)");
	const translateFirst = nativeTransform("translate(10px, -4px) scale(2, 3)");
	assert scaleFirst.scaleX === 2 && scaleFirst.scaleY === 3, "nonuniform scale";
	assert scaleFirst.translateX === 20 && scaleFirst.translateY === -12, "scale before translate scales the translation";
	assert translateFirst.translateX === 10 && translateFirst.translateY === -4, "translate before scale stays unscaled";
	const sequence = nativeTransform("translateY(5px) scaleY(-1) translateY(12px) scaleX(-1) translateX(3px)");
	assert sequence.scaleX === -1 && sequence.scaleY === -1 && sequence.translateX === -3 && sequence.translateY === -7, "each translation uses the preceding scale";
}

test "native transform parses signed fractional and exponent CSS numbers without losing the axis" {
	const value = nativeTransform("scale(+2e0 -3) translate(.5px -2.5e1px) translateX(0) translateY(0px)");
	assert value.scaleX === 2 && value.scaleY === -3, "space-separated scale arguments";
	assert value.translateX === 1 && value.translateY === 75, "fractional px and negative exponent-form translation";
	const single = nativeTransform("translate(7px)");
	assert single.translateX === 7 && single.translateY === 0, "one argument translates x only";
}

test "native transform rotates in deg, rad and turn, and rotates later translations" {
	const deg = nativeTransform("rotate(45deg)");
	assert deg.rotate === 45 && deg.scaleX === 1 && deg.translateX === 0, "degrees";
	const rad = nativeTransform("rotateZ(3.141592653589793rad)");
	assert Math.abs(rad.rotate - 180) < 0.001, "radians " + rad.rotate.toString();
	const turn = nativeTransform("rotate(0.25turn) rotate(-10deg)");
	assert Math.abs(turn.rotate - 80) < 0.001, "turns add up " + turn.rotate.toString();
	const zero = nativeTransform("rotate(0)");
	assert zero.rotate === 0, "a bare zero";
	const before = nativeTransform("translateX(10px) rotate(90deg)");
	assert before.translateX === 10 && Math.abs(before.translateY) < 0.001, "translate then rotate keeps the offset";
	const after = nativeTransform("rotate(90deg) translateX(10px)");
	assert Math.abs(after.translateX) < 0.001 && Math.abs(after.translateY - 10) < 0.001, "rotate then translate moves along the turned axis";
}

test "native transform refuses unsupported functions, units, junk and non-finite coefficients" {
	const invalid = [
		"", " ", "none scaleY(-1)", "rotate(1)", "rotate(1px)", "skewX(1deg)", "matrix(1,0,0,1,0,0)",
		"scale()", "scale(1,)", "scaleX(1,2)", "scale(1px)", "scale(NaN)", "scale(Infinity)",
		"translateY(2)", "translateX(2%)", "translate(1px,,2px)", "scale(-1", "scale(1) junk",
		"scale(1e)", "scale(1e400)", "scale(1e30) scale(1e30)", "translateY(1e40px)",
	];
	for (const css of invalid) {
		let caught = "";
		try { nativeTransform(css); } catch (e) { caught = e.toString(); }
		assert caught.includes("native host:") && caught.includes("transform"), "must fail loudly: " + css;
	}
}

test "native physical phases and touch routes carry pointer provenance and disappear on removal" {
	const registry = createNativeEventRegistry();
	let log = "";
	for (const name of ["onPointerDown", "onPointerUp", "onPress", "onPointerCancel",
		"onPointerLeave", "onPointerMove", "onTouchStart", "onTouchEnd", "onTouchCancel",
		"onTouchMove"]) {
		registry.add(17, name, (e: NeonEvent): void => {
			assert e.pointerOrigin, e.type + " has physical provenance";
			log += e.type + ";";
		});
	}
	for (const phase of [0, 1, 2, 3, 4]) {
		assert registry.dispatch(17, phase, 0, 0, 0), "zero coordinates do not erase provenance";
		registry.touch(17, phase, 0, 0, 0);
	}
	assert log === "pointerdown;touchstart;pointerup;touchend;press;" +
		"pointercancel;pointerleave;touchcancel;pointermove;touchmove;", log;
	registry.remove(17);
	assert !registry.dispatch(17, 2, 0, 0, 0) && !registry.touch(17, 0, 0, 0, 0),
		"teardown removes both routes";
}
