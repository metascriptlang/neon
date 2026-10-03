import { NativeElementKind, createNativeEventRegistry, nativeElementKind, nativeFlexStyle } from "../../src/platform/native/contract";
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

	assert registry.dispatch(99, 2, 0, 0) === false, "unknown tags are ignored";
	assert registry.dispatch(7, 0, 12, 9), "known pointer-down dispatches";
	assert registry.dispatch(7, 2, 0, 0), "known press dispatches";
	assert got === "pointerdown;press;", got;
	assert downX === 12 && downY === 9, "pointer coordinates reach the handler";
	registry.remove(7);
	assert registry.dispatch(7, 2, 0, 0) === false, "removed tags no longer dispatch";
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
