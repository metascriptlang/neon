import { runApp } from "../../src/platform/native/host";
import { createSignal, Accessor } from "../../src/core/signal";
import { For } from "../../src/macros/ui/flow";
import { View, Pressable, ScrollView, ScrollViewHandle } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";

import {
	nmViewsCreated, nmReleaseCalls, nmTouch, nmTeardown, nmMount, nmResize, nmScroll, nmLastScrollTag,
	nmContentWidth, nmContentHeight, nmScrolledX, nmScrolledY, nmScrolledAnimated,
} from "./nativeBridgeMock.h";

const PRESS: int32 = 2;

test "removed rows and a torn-down app release native views and routes exactly once" {
	const [rows, setRows] = createSignal<number[]>([1, 2, 3]);
	let pressed = "";
	const app = (): NeonNode => <View>
		<For each={rows()}>{(row: number, i: Accessor<number>): NeonNode =>
			<Pressable onPress={() => { pressed += row.toString() + ";"; }}>row</Pressable>}</For>
	</View>;

	runApp(app);
	const created = nmViewsCreated();
	const released = nmReleaseCalls();
	nmTouch(2, PRESS);
	assert pressed === "2;", "the second row's tag routes before removal: " + pressed;

	setRows([1, 3]);
	assert nmViewsCreated() === created, "keyed rows 1 and 3 are not recreated";
	assert nmReleaseCalls() - released === 2, "the removed row releases its pressable and its label: " + (nmReleaseCalls() - released).toString();
	nmTouch(2, PRESS);
	nmTouch(1, PRESS);
	nmTouch(3, PRESS);
	assert pressed === "2;1;3;", "the removed tag is inert, the others still route: " + pressed;

	nmTeardown();
	assert nmReleaseCalls() === nmViewsCreated(), "every created view is released after teardown";
	nmTouch(1, PRESS);
	assert pressed === "2;1;3;", "no route survives teardown: " + pressed;

	nmMount();
	assert nmViewsCreated() > nmReleaseCalls(), "the remount creates fresh views";
	nmTeardown();
	assert nmReleaseCalls() === nmViewsCreated(), "a second teardown releases the remount";
}


test "a ScrollView's native content size follows its laid-out content, also after a rotation" {
	const app = (): NeonNode => <ScrollView style={{ height: 200 }}>
		<View style={{ height: 300 }} />
		<View style={{ height: 300 }} />
	</ScrollView>;
	runApp(app);
	assert `${nmContentWidth()} ${nmContentHeight()}` === "400 600", "portrait: " + `${nmContentWidth()} ${nmContentHeight()}`;
	nmResize(800, 400);
	assert `${nmContentWidth()} ${nmContentHeight()}` === "800 600", "landscape: " + `${nmContentWidth()} ${nmContentHeight()}`;
	nmResize(400, 800);
	nmTeardown();
	assert nmReleaseCalls() === nmViewsCreated(), "the scroll view is released with the rest";
}

test "onScroll on a native ScrollView carries the native offset, viewport and content size" {
	let got = "";
	const app = (): NeonNode => <ScrollView onScroll={(e: NeonEvent): void => {
		got = `${e.type} ${e.x} ${e.y} ${e.width} ${e.height} ${e.contentWidth} ${e.contentHeight}`;
	}}>
		<View style={{ height: 900 }} />
	</ScrollView>;
	runApp(app);
	nmScroll(nmLastScrollTag(), 0, 120, 400, 800, 400, 900);
	assert got === "scroll 0 120 400 800 400 900", "payload: " + got;
	nmTeardown();
}

test "scrollTo on a native ScrollView reaches the native scroll view" {
	const handles: ScrollViewHandle[] = [];
	const app = (): NeonNode => <ScrollView ref={(h: ScrollViewHandle): void => { handles.push(h); }}>
		<View style={{ height: 900 }} />
	</ScrollView>;
	runApp(app);
	handles[0].scrollTo({ y: 120, animated: false });
	assert `${nmScrolledX()} ${nmScrolledY()} ${nmScrolledAnimated()}` === "0 120 0", "scrolled " + `${nmScrolledX()} ${nmScrolledY()} ${nmScrolledAnimated()}`;
	nmTeardown();
}

test "onLayout reports a native view's frame after mount and again when a rotation changes it" {
	let got = "";
	const app = (): NeonNode => <View style={{ height: 100 }} onLayout={(e: NeonEvent): void => {
		got += `${e.type} ${e.x} ${e.y} ${e.width} ${e.height};`;
	}} />;
	runApp(app);
	assert got === "layout 0 0 400 100;", "after mount: " + got;
	nmResize(800, 400);
	assert got === "layout 0 0 400 100;layout 0 0 800 100;", "after a rotation: " + got;
	nmResize(800, 400);
	assert got === "layout 0 0 400 100;layout 0 0 800 100;", "an unchanged frame does not fire again: " + got;
	nmResize(400, 800);
	nmTeardown();
}
