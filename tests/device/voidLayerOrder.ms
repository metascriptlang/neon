// Layers of one Ion window's <Void> drawn in the content's paint order, on the GPU.
//   msc build tests/device/voidLayerOrder.ms --output=out/voidLayerOrder && out/voidLayerOrder
// Exits 0 once the probes drew in the order each stage expects; the window then shows a yellow
// Scene2D over the red View and under the green one.

import { createSignal } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { Host, HostNode, NeonNode, VoidArea } from "../../src/render/hostTypes";
import { useContext } from "../../src/render/context";
import { getVoidAreaContext } from "../../src/render/voidScope";
import { layerAnchor } from "../../src/render/voidLayer";
import { Void, View, Text } from "../../src/components/primitives";
import { Scene2D, Rect } from "../../src/components/scene2d";
import { Scene3D } from "../../src/components/scene3d";
import { runWindow, DesktopOptions, desktopOptions } from "../../src/platform/ion/window";
import { rgba } from "../../../void/src/void2d/types";
import { exit, env } from "std/process";

const drawn: string[] = [];

function Probe(name: string): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const area = useContext(getVoidAreaContext()) as VoidArea;
		const anchor = layerAnchor(area, host, parent, before);
		onCleanup(area.hub.addLayer({
			anchor,
			layout: (pixelWidth: int32, pixelHeight: int32): void => {},
			prepare: (pixelWidth: int32, pixelHeight: int32): void => {},
			draw: (): void => { drawn.push(name); },
		}));
	};
}

interface Stage {
	want: string;
	next: () => void;
}

function App(): NeonNode {
	const [last, setLast] = createSignal(true);
	const [raised, setRaised] = createSignal(0);
	const stages: Stage[] = [
		{ want: "z,a,t,s", next: (): void => { setLast(false); } },
		{ want: "z,a,t", next: (): void => { setRaised(-2); } },
		{ want: "a,z,t", next: (): void => {} },
	];
	let stage = 0;
	const check = (): void => {
		const want = stages[stage].want;
		const count = want.split(",").length;
		const got = drawn.slice(drawn.length - count).join(",");
		const ok = drawn.length >= count && got === want;
		console.log(`${ok ? "ok  " : "FAIL"} stage ${stage}: drew ${got}, want ${want}`);
		if (!ok) { exit(1); }
		stages[stage].next();
		stage += 1;
		if (stage === stages.length) {
			if (env.get("NEON_LAYER_ORDER_HOLD").equals("1")) { return; }
			exit(0);
		}
		setTimeout(check, 400);
	};
	setTimeout(check, 800);
	return element(
		<Void style={{ backgroundColor: "#1e1e2e" }}>
			<View style={{ position: "absolute", left: 20, top: 20, width: 200, height: 120, backgroundColor: "#ff0000" }} />
			<Scene2D>
				<Rect width={160.0} height={80.0} color={rgba(1.0, 1.0, 0.0, 1.0)} local={{ x: 60.0, y: 50.0, scaleX: 1.0, scaleY: 1.0, rotation: 0.0, pivotX: 0.0, pivotY: 0.0 }} />
			</Scene2D>
			<View style={{ position: "absolute", left: 120, top: 90, width: 200, height: 120, backgroundColor: "#00ff00" }} />
			<View style={{ zIndex: raised() }}>{Probe("a")}</View>
			<View style={{ zIndex: -1 }}>{Probe("z")}</View>
			<Text style={{ color: "#ffffff" }}>trail{Probe("t")}</Text>
			<Scene3D />
			{element(<Show when={last}>{Probe("s")}</Show>)}
		</Void>
	);
}

const opts: DesktopOptions = { ...desktopOptions("Neon layer order", 360, 240), font: "../void/assets/font.ttf" };
exit(runWindow(opts, App));
