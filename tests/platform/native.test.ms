import { NativeElementKind, createNativeEventRegistry, nativeElementKind, nativeFlexStyle, nativeTransform } from "../../src/platform/native/contract";
import { Style } from "../../src/render/style";
import { NeonEvent } from "../../src/render/event";

test "native tags select view-backed element kinds" {
	assert nativeElementKind("text") === NativeElementKind.Text, "text uses a label view";
	assert nativeElementKind("view") === NativeElementKind.View, "view uses a view";
	assert nativeElementKind("pressable") === NativeElementKind.View, "pressable uses a touch-routed view";
	assert nativeElementKind("custom") === NativeElementKind.View, "unknown tags use the view escape hatch";
	assert nativeElementKind("scrollview") === NativeElementKind.Scroll, "scrollview uses the platform scroll container";
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
