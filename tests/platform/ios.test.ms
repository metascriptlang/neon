import { IosElementKind, createIosEventRegistry, iosElementKind, iosFlexStyle } from "../../src/platform/ios/contract";
import { Style } from "../../src/render/style";
import { NeonEvent } from "../../src/render/event";

test "iOS tags select UIKit-backed element kinds" {
	assert iosElementKind("text") === IosElementKind.Text, "text uses a label";
	assert iosElementKind("view") === IosElementKind.View, "view uses a view";
	assert iosElementKind("pressable") === IosElementKind.View, "pressable uses a touch view";
	assert iosElementKind("custom") === IosElementKind.View, "unknown tags use the view escape hatch";
}

test "iOS styles project onto FlexStyle without filling absent fields" {
	const projected = iosFlexStyle({
		width: 320,
		flexGrow: 1,
		flexDirection: "row",
		alignItems: "center",
		marginTop: 8,
		paddingLeft: 4,
		overflow: "hidden",
	} as Style, false);
	assert projected.width === 320, "width reaches flex";
	assert projected.flexGrow === 1, "flexGrow reaches flex";
	assert projected.flexDirection === "row", "flexDirection reaches flex";
	assert projected.alignItems === "center", "alignItems reaches flex";
	assert projected.marginTop === 8, "marginTop reaches flex";
	assert projected.paddingLeft === 4, "paddingLeft reaches flex";
	assert projected.overflow === "hidden", "overflow reaches flex";
	assert projected.maxWidth === null, "absent maxWidth stays absent";

	const container = iosFlexStyle({} as Style, false);
	const text = iosFlexStyle({} as Style, true);
	assert container.flexDirection === "column", "containers default to columns";
	assert text.flexDirection === null, "text keeps Yoga's direction default";
}

test "iOS event registry routes native tags and touch phases" {
	const registry = createIosEventRegistry();
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
