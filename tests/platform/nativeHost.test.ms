import { runApp } from "../../src/platform/native/host";
import { createSignal, Accessor } from "../../src/core/signal";
import { For } from "../../src/macros/ui/flow";
import { View, Pressable } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";

import { nmViewsCreated, nmReleaseCalls, nmTouch, nmTeardown, nmMount } from "./nativeBridgeMock.h";

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

