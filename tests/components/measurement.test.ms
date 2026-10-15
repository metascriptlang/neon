import { ElementHandle, ElementRef, MeasureRect, MeasureError } from "../../src/index";
import { HostNode, mockHost, mockNode, render } from "../../src/render/host";
import { View, Text, Pressable, ScrollView, ScrollViewHandle, TextInput, TextInputHandle } from "../../src/components/primitives";
import { element } from "../../src/macros/ui/element";
import { useManualFrames, setFrameDriver } from "../../src/animation/frame";
import { Image } from "../../src/components/image";
import { Switch } from "../../src/components/switch";
import { Slider } from "../../src/components/slider";
import { Picker } from "../../src/components/picker";
import { DateTimePicker } from "../../src/components/dateTimePicker";

test "primitive refs expose portable handles without changing node identity" {
	const frames = useManualFrames();
	const host = mockHost();
	host.measureInWindow = (node: HostNode): Result<MeasureRect, MeasureError> => Result.ok({ x: 1, y: 2, width: 3, height: 4 });
	const handles: ElementHandle[] = [];
	const grab: ElementRef = (h: ElementHandle): void => { handles.push(h); };
	const root = mockNode("root");
	const dispose = render(element(<View ref={grab}>
		<Text ref={(h: ElementHandle): void => { handles.push(h); }}>hello</Text>
		<Pressable ref={(h: ElementHandle): void => { handles.push(h); }}>press</Pressable>
	</View>), host, root as unknown as HostNode);
	assert handles.length === 3;
	assert handles[0].node === root.children[0].children[0] as unknown as HostNode;
	assert handles[2].node === root.children[0] as unknown as HostNode;
	let calls: int32 = 0;
	handles[2].measureInWindow((rect: MeasureRect): void => { assert rect.width === 3; calls += 1; });
	frames.step(1);
	assert calls === 1;
	handles[2].measureInWindow((rect: MeasureRect): void => { calls += 1; });
	dispose();
	frames.step(1);
	assert calls === 1;
	let rejected = false;
	try { handles[2].measureInWindow((rect: MeasureRect): void => {}); } catch { rejected = true; }
	assert rejected;
	setFrameDriver(null);
}

test "native-mapped element refs share the portable measurement handle" {
	const frames = useManualFrames();
	const host = mockHost();
	host.measureInWindow = (node: HostNode): Result<MeasureRect, MeasureError> => Result.ok({ x: 0, y: 0, width: 20, height: 30 });
	const handles: ElementHandle[] = [];
	const root = mockNode("root");
	const dispose = render(element(<View>
		<Image ref={(h: ElementHandle): void => { handles.push(h); }} />
		<Switch ref={(h: ElementHandle): void => { handles.push(h); }} />
		<Slider ref={(h: ElementHandle): void => { handles.push(h); }} />
		<Picker items={[]} ref={(h: ElementHandle): void => { handles.push(h); }} />
		<DateTimePicker value="2026-10-15" ref={(h: ElementHandle): void => { handles.push(h); }} />
	</View>), host, root as unknown as HostNode);
	assert handles.length === 5;
	let calls: int32 = 0;
	for (const handle of handles) {
		handle.measureInWindow((rect: MeasureRect): void => { assert rect.width === 20; calls += 1; });
	}
	frames.step(1);
	assert calls === 5;
	dispose();
	setFrameDriver(null);
}

test "specialized input and scroll handles also support measurement" {
	const frames = useManualFrames();
	const host = mockHost();
	host.measureInWindow = (node: HostNode): Result<MeasureRect, MeasureError> => Result.ok({ x: 0, y: 0, width: 20, height: 30 });
	const inputs: TextInputHandle[] = [];
	const scrolls: ScrollViewHandle[] = [];
	const root = mockNode("root");
	const dispose = render(element(<View>
		<TextInput ref={(h: TextInputHandle): void => { inputs.push(h); }} />
		<ScrollView ref={(h: ScrollViewHandle): void => { scrolls.push(h); }} />
	</View>), host, root as unknown as HostNode);
	let calls: int32 = 0;
	inputs[0].focus();
	assert inputs[0].isFocused();
	scrolls[0].scrollTo({ y: 12, animated: false });
	inputs[0].measureInWindow((rect: MeasureRect): void => { calls += 1; });
	scrolls[0].measureInWindow((rect: MeasureRect): void => { calls += 1; });
	frames.step(1);
	assert calls === 2;
	dispose();
	setFrameDriver(null);
}
