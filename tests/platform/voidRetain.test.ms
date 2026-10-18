import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { View, Text } from "../../src/components/primitives";
import { Accessor } from "../../src/core/signal";
import { createList, List } from "../../src/core/list";
import { ForList } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";
import { TextSpan } from "../../src/render/hostTypes";
import { Style } from "../../src/render/style";
import { createVoidHostWith, VoidHost } from "../../src/platform/void/host";
import { Scene2D } from "../../../void/src/void2d/node";
import { create, paint } from "../../../void/src/void2d/scene";
import { rgba } from "../../../void/src/void2d/types";
import { addFont, registerFace, FontStyle } from "../../../void/src/void2d/font";
import { frameEnd } from "../../../void/src/void2d/draw";
import {
	uiInstanceCount, uploaded, commandCount, commandField, uiInstanceField,
	CMD_KIND, CMD_PIPELINE, CMD_INSTANCE_OFFSET, CMD_INSTANCE_COUNT, CMD_EFFECT,
} from "../../../void/src/void2d/displayList";
import { REC_UI_FLOATS, REC_UI_PARAMS0, REC_UI_ORIGIN_SIZE } from "../../../void/src/void2d/instanceLayout";

const FONT_PATH = "../void/assets/font.ttf";
const FAMILY = "Neon Retain Mono";
const W: float32 = 400.0;
const H: float32 = 200.0;

struct GridRow { spans: TextSpan[]; }

function capture(): string {
	let out = `cmds=${commandCount()} inst=${uiInstanceCount()}`;
	for (let i: int32 = 0; i < commandCount(); i++) {
		out += ` | k${commandField(i, CMD_KIND)} p${commandField(i, CMD_PIPELINE)} @${commandField(i, CMD_INSTANCE_OFFSET)}+${commandField(i, CMD_INSTANCE_COUNT)} e${commandField(i, CMD_EFFECT)}`;
	}
	for (let i: int32 = 0; i < uiInstanceCount(); i++) {
		if (uiInstanceField(i, REC_UI_PARAMS0) === 4.0) { out += ` deco@${uiInstanceField(i, REC_UI_ORIGIN_SIZE)},${uiInstanceField(i, REC_UI_ORIGIN_SIZE + 1)}w${uiInstanceField(i, REC_UI_ORIGIN_SIZE + 2)}`; }
	}
	let sum = 0.0;
	for (let i: int32 = 0; i < uiInstanceCount(); i++) {
		for (let f: int32 = 0; f < REC_UI_FLOATS; f++) { sum += (uiInstanceField(i, f) as number) * ((i * 37 + f) % 11 + 1); }
	}
	return out + ` sum=${Math.round(sum * 10)}`;
}

function frame(vh: VoidHost, full: boolean): string {
	vh.layout(W, H);
	const s = vh.scene;
	if (full) {
		s.context.painted = false;
		s.viewInit = false;
	}
	s.paint(W, H, 1.0);
	const out = capture();
	uploaded();
	frameEnd();
	s.clearChanges();
	s.retryRefused();
	return out;
}

const plain: Style = { color: "#ffffff", textDecorationLine: "none", textDecorationStyle: "solid", fontWeight: "normal", fontStyle: "normal" };
const bold: Style = { color: "#ffffff", textDecorationLine: "none", textDecorationStyle: "solid", fontWeight: "bold", fontStyle: "normal" };
const curly: Style = { color: "#ffffff", textDecorationLine: "underline", textDecorationStyle: "wavy", fontWeight: "normal", fontStyle: "normal" };

function mount(vh: VoidHost, grid: List<GridRow>): void {
	const row = (item: Accessor<GridRow>): NeonNode => element(<Text style={{ fontSize: 14, height: 18 }} cellWidth={8.4} spans={item().spans} />);
	render(element(<View style={{ width: 400 }}>{ForList<GridRow>({ each: grid, children: row })}</View>), vh.host, vh.root);
}

test "rows pushed and set across retained frames record what a full repaint records" {
	const font = addFont(FONT_PATH);
	if (!font.ok) { throw new Error("font"); }
	registerFace(FONT_PATH, FAMILY, 400, FontStyle.Normal);
	registerFace(FONT_PATH, FAMILY, 700, FontStyle.Normal);
	const a = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), font.value, FAMILY);
	const b = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), font.value, FAMILY);
	const ga = createList<GridRow>([]);
	const gb = createList<GridRow>([]);
	mount(a, ga);
	mount(b, gb);
	const bad: string[] = [];
	const both = (f: (g: List<GridRow>) => void): void => { f(ga); f(gb); };
	const step = (label: string): void => {
		const ra = frame(a, false);
		const rb = frame(b, true);
		if (ra !== rb) { bad.push(label); }
	};
	both((g: List<GridRow>): void => { g.push({ spans: [{ text: "PS> ", style: plain }] }); });
	step("f1 prompt");
	both((g: List<GridRow>): void => { g.set(0, { spans: [{ text: "PS> ", style: plain }, { text: "bold", style: bold }, { text: " ", style: plain }, { text: "curly", style: curly }, { text: " plain", style: plain }] }); });
	both((g: List<GridRow>): void => { g.push({ spans: [{ text: "next line", style: plain }] }); });
	step("f2 styled row + pushed row");
	both((g: List<GridRow>): void => { g.push({ spans: [{ text: "PS> ", style: plain }] }); });
	step("f3 new prompt");
	both((g: List<GridRow>): void => { g.set(2, { spans: [{ text: "PS> ", style: plain }, { text: "ls", style: bold }] }); });
	step("f4 typed bold");
	both((g: List<GridRow>): void => { g.set(1, { spans: [{ text: "next linf", style: plain }] }); });
	step("f5 row1 same length");
	assert bad.length === 0, "retained differs from full at: " + bad.join(", ");
}
