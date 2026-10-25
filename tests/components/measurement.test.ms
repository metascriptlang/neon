import { ElementHandle, MeasureRect, MeasureError } from "../../src/index";
import { HostNode, MockNode, mockHost, mockNode, render } from "../../src/render/host";
import { View, ViewHandle, Text, Pressable, ScrollView, ScrollViewHandle, TextInput, TextInputHandle } from "../../src/components/primitives";
import { element } from "../../src/macros/ui/element";
import { Image } from "../../src/components/image";
import { Switch } from "../../src/components/switch";

test "primitive refs expose portable handles without changing node identity" {
	const host = mockHost();
	host.measureInWindow = (node: HostNode): Result<MeasureRect, MeasureError> => Result.ok({ x: 1, y: 2, width: 3, height: 4 });
	const handles: ElementHandle[] = [];
	const grab = (h: ElementHandle): void => { handles.push(h); };
	const root = mockNode("root");
	const dispose = render(element(<View ref={grab}>
		<Text ref={(h: ElementHandle): void => { handles.push(h); }}>hello</Text>
		<Pressable ref={(h: ElementHandle): void => { handles.push(h); }}>press</Pressable>
	</View>), host, root as unknown as HostNode);
	assert handles.length === 3;
	assert handles[0].node === root.children[0].children[0] as unknown as HostNode;
	assert handles[2].node === root.children[0] as unknown as HostNode;
	let got = "";
	handles[2].measureInWindow((x: number, y: number, width: number, height: number): void => { got += `${x},${y},${width},${height};`; });
	dispose();
	handles[2].measureInWindow((x: number, y: number, width: number, height: number): void => { got += `${x},${y},${width},${height};`; });
	assert got === "1,2,3,4;0,0,0,0;", "measured before the call returns, zeros after unmount: " + got;
}

test "Image and Switch refs share the portable measurement handle" {
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
		handle.measureInWindow((x: number, y: number, width: number, height: number): void => { assert width === 20; calls += 1; });
	}
	assert calls === 2;
	dispose();
}

test "specialized input and scroll handles also support measurement" {
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
	inputs[0].measureInWindow((x: number, y: number, width: number, height: number): void => { calls += 1; });
	scrolls[0].measureInWindow((x: number, y: number, width: number, height: number): void => { calls += 1; });
	assert calls === 2;
	dispose();
}

test "one ViewHandle keeps focus and both measurements under the same lifetime" {
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
	handles[0].measureInWindow((x: number, y: number, width: number, height: number): void => {
		assert x === 10 && y === 20 && width === 30 && height === 40;
		measured += 1;
	});
	handles[0].measureLayout(handles[1], (left: number, top: number, width: number, height: number): void => {
		assert left === 4 && top === 5 && width === 30 && height === 40;
		measured += 1;
	});
	assert measured === 2;
	dispose();
	let failed = false;
	handles[0].measureLayout(handles[1], (left: number, top: number, width: number, height: number): void => { measured += 1; }, (): void => { failed = true; });
	assert measured === 2 && failed, "measureLayout after unmount calls onFail";
	handles[0].focus();
	assert log === "focus;blur;", "focus after unmount does nothing: " + log;
}

test "Text, Pressable, Image and Switch hand their ref a View's handle that knows when it unmounts" {
	const host = mockHost();
	host.measureInWindow = (node: HostNode): Result<MeasureRect, MeasureError> => Result.ok({ x: 1, y: 2, width: 3, height: 4 });
	const handles: ViewHandle[] = [];
	const keep = (h: ViewHandle): void => { handles.push(h); };
	const root = mockNode("root");
	const dispose = render(element(<View>
		<Text ref={keep}>a</Text>
		<Text ref={keep} numberOfLines={1}>b</Text>
		<Text ref={keep} onPress={(): void => {}}>c</Text>
		<Pressable ref={keep} />
		<Image ref={keep} source={{ uri: "a.png" }} />
		<Switch ref={keep} />
	</View>), host, root as unknown as HostNode);
	const frames = (): string => {
		let out = "";
		for (const h of handles) { out += `${(h.node as unknown as MockNode).tag}:${h.getBoundingClientRect().bottom} `; }
		return out;
	};
	assert frames() === "text:6 text:6 text:6 pressable:6 image:6 switch:6 ", frames();
	dispose();
	assert frames() === "text:0 text:0 text:0 pressable:0 image:0 switch:0 ", "unmounted: " + frames();
}
