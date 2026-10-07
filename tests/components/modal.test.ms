import { createSignal } from "../../src/core/signal";
import { createContext, useContext } from "../../src/render/context";
import { sleepAsync } from "std/core/promise";
import { element } from "../../src/macros/ui/element";

import { Style } from "../../src/render/style";
import { Host, HostNode, MockNode, mockNode, mockHost, render, fireEvent, mockToString } from "../../src/render/host";
import { Text, View } from "../../src/components/primitives";
import { Modal } from "../../src/components/modal";
import { Portal } from "../../src/render/portal";

function overlayOf(host: Host): MockNode {
	return (host.overlayRoot as (n: HostNode) => HostNode)(mockNode("any") as unknown as HostNode) as unknown as MockNode;
}

test "a visible Modal mounts its children into the overlay root above the app, and unmounts them when hidden" {
	const [open, setOpen] = createSignal(false);
	const host = mockHost();
	const root: MockNode = mockNode("root");
	render(element(<View><Text>app</Text><Modal visible={open()} animationType="fade"><Text>sheet</Text></Modal></View>), host, root as unknown as HostNode);
	const overlay = overlayOf(host);
	assert mockToString(overlay) === "<overlay></overlay>", "hidden: " + mockToString(overlay);
	setOpen(true);
	assert mockToString(overlay) === "<overlay><modal animationType=\"fade\"><text>sheet</text></modal></overlay>", "shown: " + mockToString(overlay);
	assert mockToString(root).indexOf("sheet") < 0, "nothing lands in the app tree: " + mockToString(root);
	const box = overlay.children[0].style as Style;
	assert box.position === "absolute" && box.top === 0 && box.bottom === 0 && box.zIndex === 1000 && box.backgroundColor !== "transparent", "fills, stacks above, opaque";
	setOpen(false);
	assert mockToString(overlay) === "<overlay></overlay>", "hidden again: " + mockToString(overlay);
}

test "a transparent Modal routes onRequestClose, and onShow and onDismiss follow the presentation" {
	const [open, setOpen] = createSignal(true);
	const [log, setLog] = createSignal("");
	const host = mockHost();
	const root: MockNode = mockNode("root");
	render(element(<Modal visible={open()} transparent={true}
		onShow={(): void => { setLog(log() + "show;"); }}
		onDismiss={(): void => { setLog(log() + "dismiss;"); }}
		onRequestClose={(): void => { setLog(log() + "close;"); setOpen(false); }}><Text>dialog</Text></Modal>), host, root as unknown as HostNode);
	const overlay = overlayOf(host);
	assert (overlay.children[0].style as Style).backgroundColor === "transparent", "transparent";
	await sleepAsync(20);
	fireEvent(overlay.children[0], "onRequestClose");
	await sleepAsync(20);
	assert log() === "show;close;dismiss;", "events: " + log();
	assert overlay.children.length === 0, "closed";
}

interface Tone {
	name: string;
}

test "a Portal keeps its owner's context and mounts into a named node" {
	const T = createContext<Tone>({ name: "plain" });
	const target = mockNode("target");
	const root: MockNode = mockNode("root");
	render(element(<T.Provider value={{ name: "dark" }}><View><Portal mount={target as unknown as HostNode}><Text>{useContext(T).name}</Text></Portal></View></T.Provider>), mockHost(), root as unknown as HostNode);
	assert mockToString(target) === "<target><view><text>dark</text></view></target>", "portal: " + mockToString(target);
	assert mockToString(root) === "<root><view></view></root>", "the app tree keeps no node: " + mockToString(root);
}
