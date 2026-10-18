import { ElementHandle, ElementRef, MeasureRect, MeasureError } from "../../src/index";
import { HostNode, mockHost, mockNode, render } from "../../src/render/host";
import { View, ViewHandle, Text, Pressable, ScrollView, ScrollViewHandle, TextInput, TextInputHandle } from "../../src/components/primitives";
import { element } from "../../src/macros/ui/element";
import { useManualFrames, setFrameDriver } from "../../src/animation/frame";
import { Image } from "../../src/components/image";
import { Switch } from "../../src/components/switch";

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

test "Image and Switch refs share the portable measurement handle" {
	const frames = useManualFrames();
	const host = mockHost();
	host.measureInWindow = (node: HostNode): Result<MeasureRect, MeasureError> => Result.ok({ x: 0, y: 0, width: 20, height: 30 });
	const handles: ElementHandle[] = [];
	const root = mockNode("root");
	const dispose = render(element(<View>
		<Image ref={(h: ElementHandle): void => { handles.push(h); }} />
		<Switch ref={(h: ElementHandle): void => { handles.push(h); }} />
	</View>), host, root as unknown as HostNode);
	assert handles.length === 2;
	let calls: int32 = 0;
	for (const handle of handles) {
		handle.measureInWindow((rect: MeasureRect): void => { assert rect.width === 20; calls += 1; });
	}
	frames.step(1);
	assert calls === 2;
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

test "one ViewHandle keeps focus and both measurements under the same lifetime" {
	const frames = useManualFrames();
	const host = mockHost();
	const handles: ViewHandle[] = [];
	let log = "";
	let measured = 0;
	host.measureInWindow = (node: HostNode): Result<MeasureRect, MeasureError> => {
		assert node === handles[0].node;
		return Result.ok({ x: 10, y: 20, width: 30, height: 40 });
	};
	host.measureLayout = (node: HostNode, ancestor: HostNode): Result<MeasureRect, MeasureError> => {
		assert node === handles[0].node && ancestor === handles[1].node;
		return Result.ok({ x: 4, y: 5, width: 30, height: 40 });
	};
	const root = mockNode("root");
	const grab = (h: ViewHandle): void => { handles.push(h); };
	const dispose = render(element(<View ref={grab}>
		<View ref={grab} focusable={true}
			onFocus={(): void => { log += "focus;"; }}
			onBlur={(): void => { log += "blur;"; }} />
	</View>), host, root as unknown as HostNode);
	assert handles.length === 2;
	assert handles[0].node === root.children[0].children[0] as unknown as HostNode;
	handles[0].focus();
	handles[0].blur();
	assert log === "focus;blur;";
	handles[0].measureInWindow((rect: MeasureRect): void => {
		assert rect.x === 10 && rect.y === 20 && rect.width === 30 && rect.height === 40;
		measured += 1;
	});
	handles[0].measureLayout(handles[1], (rect: MeasureRect): void => {
		assert rect.x === 4 && rect.y === 5 && rect.width === 30 && rect.height === 40;
		measured += 1;
	});
	frames.step(1);
	assert measured === 2;
	handles[0].measureInWindow((rect: MeasureRect): void => { measured += 1; });
	handles[0].measureLayout(handles[1], (rect: MeasureRect): void => { measured += 1; });
	dispose();
	frames.step(1);
	assert measured === 2;
	let focusError = "";
	let measureError = "";
	try { handles[0].focus(); } catch (e) { focusError = e.toString(); }
	try {
		handles[0].measureInWindow((rect: MeasureRect): void => { measured += 1; });
	} catch (e) { measureError = e.toString(); }
	assert focusError.indexOf("after the View unmounted") >= 0;
	assert measureError.indexOf("after unmount") >= 0;
	setFrameDriver(null);
}
