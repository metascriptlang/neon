import { createSignal } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { Host, HostNode, NeonNode } from "../../src/render/hostTypes";
import { MockNode, mockNode, mockHost, render, fireEvent, mockToString } from "../../src/render/host";
import { place } from "../../src/render/reconcile";
import { refreshTemplate, refreshRegion, refreshComponentDef, refreshBoundary, refreshModule, refreshReset } from "../../src/render/refresh";

interface CounterRegionProps {
	count: () => number;
	onInc: () => void;
}

function appendText(host: Host, parent: HostNode, before: HostNode | null, s: string): void {
	place(host, parent, host.createText(s), before);
}

function appendDyn(host: Host, parent: HostNode, before: HostNode | null, get: () => string): void {
	const t = host.createText("");
	place(host, parent, t, before);
	createEffect((): void => { host.setText(t, get()); });
}

function counterRegion(id: string, sig: string, label: string): void {
	refreshTemplate("app.ms", id, (): string => sig, (host: Host, parent: HostNode, before: HostNode | null, props: CounterRegionProps): void => {
		appendText(host, parent, before, label);
		appendDyn(host, parent, before, (): string => props.count().toString());
		const button = host.createElement("button");
		place(host, parent, button, before);
		host.addEvent(button, "onPress", (): void => { props.onInc(); });
	});
}

test "refresh: template rebuild keeps the owning signal at its live value" {
	refreshReset();
	const [count, setCount] = createSignal(0);
	const props: CounterRegionProps = {
		count: (): number => count(),
		onInc: (): void => { setCount(count() + 1); },
	};
	counterRegion("r0", "v1", "old:");
	const root: MockNode = mockNode("root");
	const dispose = render(refreshRegion("app.ms", "r0", props), mockHost(), root as unknown as HostNode);

	assert mockToString(root.children[0]) === "old:", "v1 label";
	assert mockToString(root.children[1]) === "0", "count 0";
	for (let i = 0; i < 8; i += 1) { fireEvent(root.children[2], "onPress"); }
	assert mockToString(root.children[1]) === "8", "count 8 after clicks";

	counterRegion("r0", "v2", "new:");
	const summary = refreshModule("app.ms");
	assert summary.rebuilt === 1 && summary.remounted === 0, "one region rebuilt";
	assert mockToString(root.children[0]) === "new:", "v2 label after rebuild";
	assert mockToString(root.children[1]) === "8", "count survives the rebuild";

	fireEvent(root.children[2], "onPress");
	assert mockToString(root.children[1]) === "9", "no duplicated subscription: one click is +1";
	dispose();
}

test "refresh: same signature re-registration keeps the mounted view" {
	refreshReset();
	const [count] = createSignal(3);
	counterRegion("r0", "v1", "old:");
	const root: MockNode = mockNode("root");
	const dispose = render(refreshRegion("app.ms", "r0", { count: (): number => count(), onInc: (): void => {} } as CounterRegionProps), mockHost(), root as unknown as HostNode);
	counterRegion("r0", "v1", "new:");
	const summary = refreshModule("app.ms");
	assert summary.rebuilt === 0, "same sig means no rebuild";
	assert mockToString(root.children[0]) === "old:", "mounted view keeps its generation";
	dispose();
}

test "refresh: component remount resets only that boundary's local state" {
	refreshReset();
	let version = 1;
	const makeComp = (): (props: unknown) => NeonNode => {
		return (props: unknown): NeonNode => {
			const [c, setC] = createSignal(0);
			return (host: Host, parent: HostNode, before: HostNode | null): void => {
				appendText(host, parent, before, "v" + version.toString() + ":");
				appendDyn(host, parent, before, (): string => c().toString());
				const button = host.createElement("button");
				place(host, parent, button, before);
				host.addEvent(button, "onPress", (): void => { setC(c() + 1); });
			};
		};
	};
	refreshComponentDef("app.ms", "Counter", (): string => "s" + version.toString(), makeComp());
	const [sibling] = createSignal(5);
	refreshTemplate("app.ms", "sib", (): string => "s1", (host: Host, parent: HostNode, before: HostNode | null, props: unknown): void => {
		appendText(host, parent, before, "sib:");
		appendDyn(host, parent, before, (): string => sibling().toString());
	});

	const root: MockNode = mockNode("root");
	const boundary = refreshBoundary("app.ms", "Counter");
	const dispose = render((host: Host, parent: HostNode, before: HostNode | null): void => {
		boundary(null)(host, parent, null);
		refreshRegion("app.ms", "sib", null)(host, parent, null);
	}, mockHost(), root as unknown as HostNode);

	assert mockToString(root.children[0]) === "v1:", "v1 component label";
	for (let i = 0; i < 4; i += 1) { fireEvent(root.children[2], "onPress"); }
	assert mockToString(root.children[1]) === "4", "local count 4";

	version = 2;
	refreshComponentDef("app.ms", "Counter", (): string => "s" + version.toString(), makeComp());
	const summary = refreshModule("app.ms");
	assert summary.remounted === 1 && summary.rebuilt === 0, "one boundary remounted";
	assert mockToString(root.children[0]) === "v2:", "new component code runs";
	assert mockToString(root.children[1]) === "0", "local state reset at the boundary";
	assert mockToString(root.children[4]) === "sib:" && mockToString(root.children[5]) === "5", "sibling state survives the remount";
	dispose();
}

test "refresh: another module's instances are untouched" {
	refreshReset();
	counterRegion("r0", "v1", "old:");
	const root: MockNode = mockNode("root");
	const dispose = render(refreshRegion("app.ms", "r0", { count: (): number => 1, onInc: (): void => {} } as CounterRegionProps), mockHost(), root as unknown as HostNode);
	const summary = refreshModule("other.ms");
	assert summary.rebuilt === 0 && summary.kept === 0, "only the named module patches";
	dispose();
}

test "refresh: disposal drops instance records" {
	refreshReset();
	counterRegion("r0", "v1", "old:");
	const root: MockNode = mockNode("root");
	const dispose = render(refreshRegion("app.ms", "r0", { count: (): number => 1, onInc: (): void => {} } as CounterRegionProps), mockHost(), root as unknown as HostNode);
	dispose();
	counterRegion("r0", "v2", "new:");
	const summary = refreshModule("app.ms");
	assert summary.rebuilt === 0 && summary.remounted === 0, "disposed regions are not patched";
}
