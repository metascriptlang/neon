import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, Label } from "../../src/components/scene2d";
import { NodeRef } from "../../../void/src/void2d/node";
import { rgba } from "../../../void/src/void2d/types";
import { DEFAULT_FONT } from "../../../void/src/void2d/font";
import { TextRun, Truncate } from "../../../void/src/void2d/textLayout";
import { calcTextWidth } from "../../../void/src/void2d/render";
import { labelTexts, labelLines } from "../../../void/src/void2d/labelText";

function run(len: int32): TextRun {
	return { len: len, font: DEFAULT_FONT, color: rgba(1.0, 1.0, 1.0, 1.0),
		background: rgba(0.0, 0.0, 0.0, 0.0), underline: rgba(0.0, 0.0, 0.0, 0.0),
		wavy: false, strikethrough: rgba(0.0, 0.0, 0.0, 0.0) };
}

test "Label owns run and shaping-break snapshots and binds line options reactively" {
	const nodes: NodeRef[] = [];
	const initialRuns: TextRun[] = [run(2), run(2)];
	const initialBreaks: int32[] = [2];
	const [runs, setRuns] = createSignal<TextRun[]>(initialRuns);
	const [breaks, setBreaks] = createSignal<int32[]>(initialBreaks);
	const [truncate, setTruncate] = createSignal<Truncate>(Truncate.None);
	const [indent, setIndent] = createSignal<float32>(3.0);
	const [width, setWidth] = createSignal<float32>(8.0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Label text="abcd" size={13.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
			textRuns={runs()} shapingBreaks={breaks()} truncate={truncate()}
			hangingIndent={indent()} forceWidth={width()}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	const node = nodes[0];
	const row = node.scene.payloads[node.id.index];
	assert labelTexts[row].runs.length === 2 && labelTexts[row].runs[0].len === 2;
	assert labelTexts[row].shapingBreaks[0] === 2;
	assert labelLines(row).truncate === Truncate.None;
	assert labelLines(row).hangingIndent === 3.0 && labelLines(row).forceWidth === 8.0;
	assert node.calcTextWidth("abc") === 24.0;
	initialRuns[0].len = 1; initialBreaks[0] = 999;
	assert labelTexts[row].runs[0].len === 2 && labelTexts[row].shapingBreaks[0] === 2;
	setRuns([run(4)]); setBreaks([1, 3]); setTruncate(Truncate.End); setIndent(6.0); setWidth(10.0);
	assert node.scene.payloads[node.id.index] === row;
	assert labelTexts[row].runs.length === 1 && labelTexts[row].runs[0].len === 4;
	assert labelTexts[row].shapingBreaks.length === 2 && labelTexts[row].shapingBreaks[1] === 3;
	assert labelLines(row).truncate === Truncate.End;
	assert labelLines(row).hangingIndent === 6.0 && labelLines(row).forceWidth === 10.0;
	setRuns([]); setBreaks([]); setTruncate(Truncate.None);
	assert labelTexts[row].runs.length === 0 && labelTexts[row].shapingBreaks.length === 0;
	dispose(); setRuns([run(1)]); setWidth(4.0);
	assert !node.isLive() && node.scene.closed;
}

test "Label remount applies current runs and line options without changing omitted siblings" {
	const nodes: NodeRef[] = [];
	const [shown, setShown] = createSignal(true);
	const [runs, setRuns] = createSignal<TextRun[]>([run(2)]);
	const [width, setWidth] = createSignal<float32>(5.0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Label text="ab" size={13.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
		{Show({ when: () => shown(), children: element(
			<Label text="ab" size={13.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
				textRuns={runs()} forceWidth={width()}
				ref={(node: NodeRef): void => { nodes.push(node); }} />
		) })}
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	const siblingRow = nodes[0].scene.payloads[nodes[0].id.index];
	assert labelTexts[siblingRow].runs.length === 0 && labelTexts[siblingRow].shapingBreaks.length === 0;
	assert labelLines(siblingRow).truncate === Truncate.None && labelLines(siblingRow).forceWidth === 0.0;
	setShown(false); setRuns([run(1), run(1)]); setWidth(12.0); setShown(true);
	assert !nodes[1].isLive();
	const row = nodes[2].scene.payloads[nodes[2].id.index];
	assert labelTexts[row].runs.length === 2 && labelLines(row).forceWidth === 12.0;
	assert labelTexts[siblingRow].runs.length === 0 && labelLines(siblingRow).forceWidth === 0.0;
	dispose(); setShown(false); setWidth(2.0);
	assert !nodes[0].isLive() && !nodes[2].isLive() && nodes[0].scene.closed;
}

