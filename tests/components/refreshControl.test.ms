import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/hostTypes";
import { HostNode, MockNode, mockNode, mockHost, render, fireEvent } from "../../src/render/host";
import { ScrollView, Text, View } from "../../src/components/primitives";
import { RefreshControl } from "../../src/components/refreshControl";
import { FlatList, ListRenderItemInfo } from "../../src/components/flatList";

interface Entry {
	id: string;
}

function attrOf(n: MockNode, name: string): string {
	for (const a of n.attrs) {
		if (a.name === name) { return a.value ?? ""; }
	}
	return "<unset>";
}

test "a RefreshControl configures its ScrollView's refresh options and routes its refresh" {
	const [busy, setBusy] = createSignal(false);
	let pulls = 0;
	const root: MockNode = mockNode("root");
	render(element(<ScrollView refreshControl={<RefreshControl refreshing={busy()} tintColor="#ff0000" colors={["#00ff00", "#0000ff"]}
		onRefresh={(): void => { pulls += 1; setBusy(true); }} />}>
		<Text>content</Text>
	</ScrollView>), mockHost(), root as unknown as HostNode);
	const scroll = root.children[0];
	assert scroll.children.length === 1, "the control mounts no node: " + scroll.children.length.toString();
	assert attrOf(scroll, "refreshEnabled") === "true" && attrOf(scroll, "refreshing") === "false", "enabled, idle";
	assert attrOf(scroll, "refreshTintColor") === "#ff0000" && attrOf(scroll, "refreshColors") === "#00ff00,#0000ff", "colours";
	fireEvent(scroll, "onRefresh");
	assert pulls === 1 && attrOf(scroll, "refreshing") === "true", "the pull runs onRefresh and the controlled value follows";
	setBusy(false);
	assert attrOf(scroll, "refreshing") === "false", "the app closes the refresh";
}

test "RefreshControl enabled={false} turns the pull off" {
	const [on, setOn] = createSignal(false);
	const root: MockNode = mockNode("root");
	render(element(<ScrollView refreshControl={<RefreshControl refreshing={false} enabled={on()} />}><View /></ScrollView>), mockHost(), root as unknown as HostNode);
	assert attrOf(root.children[0], "refreshEnabled") === "false", "disabled";
	setOn(true);
	assert attrOf(root.children[0], "refreshEnabled") === "true", "enabled follows its signal";
}

test "a FlatList forwards refreshControl to its ScrollView" {
	let pulls = 0;
	const rows: Entry[] = [{ id: "a" }, { id: "b" }];
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={rows} updateCellsBatchingPeriod={0}
		refreshControl={<RefreshControl refreshing={false} onRefresh={(): void => { pulls += 1; }} />}
		renderItem={(info: ListRenderItemInfo<Entry>): NeonNode => <Text>{info.item.id}</Text>} />), mockHost(), root as unknown as HostNode);
	const scroll = root.children[0];
	assert attrOf(scroll, "refreshEnabled") === "true", "the list's scroll view has the control";
	fireEvent(scroll, "onRefresh");
	assert pulls === 1, "the pull reaches the author";
}
