import { runApp } from "../../src/platform/native/host";
import { createSignal } from "../../src/core/signal";
import { View } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { Svg, Circle, Rect } from "../../src/components/svg/elements";
import { SvgXml } from "../../src/components/svg/xml";
import { nmTeardown, nmDisplayList, nmLastControlTag, nmLayoutWidth, nmLayoutHeight, nmProp } from "./nativeBridgeMock.h";

const SVG_KIND: int32 = 9;

test "an Svg is one native view laid out by its size, holding the display list" {
	const [r, setR] = createSignal<float64>(10);
	let laidOut = "";
	const app = (): NeonNode => <View>
		<Svg width={120} height={60} accessibilityLabel="chart" onLayout={(e: NeonEvent): void => { laidOut = `${e.width}x${e.height}`; }}>
			<Rect width={120} height={60} fill="#eeeeee" />
			<Circle cx={30} cy={30} r={r()} fill="#ff0000" />
		</Svg>
	</View>;
	runApp(app);
	const tag = nmLastControlTag(SVG_KIND);
	assert laidOut === "120x60" && nmLayoutWidth(tag) === 120 && nmLayoutHeight(tag) === 60, "layout " + laidOut;
	const label: string = nmProp(tag, "accessibilityLabel");
	assert label === "chart", "label " + label;
	const first: string = nmDisplayList(tag);
	assert first.startsWith("M 0 0 L 120 0 L 120 60 L 0 60 Z F c 238 238 238 1 S n E 0 O M 40 30 C 40 35.5228"), first;
	setR(20);
	const second: string = nmDisplayList(tag);
	assert second.indexOf("M 50 30 C 50 41.0457") > 0, second;
	nmTeardown();
}

test "an Svg without a size takes the size layout gives it" {
	const app = (): NeonNode => <View style={{ width: 200, height: 100 }}>
		<Svg viewBox="0 0 10 10" style={{ flex: 1 }} onLayout={(e: NeonEvent): void => {}}>
			<Rect width={10} height={10} />
		</Svg>
	</View>;
	runApp(app);
	const tag = nmLastControlTag(SVG_KIND);
	assert nmLayoutWidth(tag) === 200 && nmLayoutHeight(tag) === 100, `${nmLayoutWidth(tag)}x${nmLayoutHeight(tag)}`;
	const list: string = nmDisplayList(tag);
	assert list.startsWith("V 0 0 10 10 5 0 M 0 0"), list;
	nmTeardown();
}

test "SvgXml reaches the native view through the same channel" {
	const app = (): NeonNode => <SvgXml width={32} height={32} xml={"<svg viewBox='0 0 2 2'><circle cx='1' cy='1' r='1' fill='#00f'/></svg>"} />;
	runApp(app);
	const list: string = nmDisplayList(0);
	assert list.startsWith("V 0 0 2 2 5 0 M 2 1 C") && list.endsWith("F c 0 0 255 1 S n E 0 O"), list;
	nmTeardown();
}
