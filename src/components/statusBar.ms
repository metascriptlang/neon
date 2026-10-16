import { Style } from "../render/style";
import { Accessor, createSignal, untrack } from "../core/signal";
import { createRenderEffect } from "../core/effect";
import { Cleanup } from "../core/types";
import { onCleanup } from "../core/cleanup";
import { NeonNode, hostElement } from "../render/node";
import { Host, HostNode } from "../render/hostTypes";

export type StatusBarStyle = "default" | "light-content" | "dark-content";

interface StatusBarProps {
	barStyle?: Accessor<StatusBarStyle> | null;
	backgroundColor?: Accessor<string> | null;
	hidden?: Accessor<boolean> | null;
	translucent?: Accessor<boolean> | null;
	animated?: Accessor<boolean> | null;
}

class StatusBarEntry {
	host: Host;
	node: HostNode;
	props: StatusBarProps;

	constructor(host: Host, node: HostNode, props: StatusBarProps) {
		this.host = host;
		this.node = node;
		this.props = props;
	}
}

// RN StatusBar.js keeps a stack of mounted StatusBars and applies, per prop,
// the value of the most recently mounted one that sets it; RN's defaults fill
// the rest. The status bar itself is one per app, so the top entry's hidden
// node carries the merged values to the host.
const stack: StatusBarEntry[] = [];
const [revision, setRevision] = createSignal<number>(0, { ownedWrite: true });

function bump(): void {
	setRevision(untrack((): number => revision()) + 1);
}

function mergedStyle(): string {
	for (let i = stack.length - 1; i >= 0; i -= 1) {
		const read = stack[i].props.barStyle;
		if (read !== null) { const v: StatusBarStyle = (read as Accessor<StatusBarStyle>)(); return v; }
	}
	return "default";
}

function mergedColor(): string {
	for (let i = stack.length - 1; i >= 0; i -= 1) {
		const read = stack[i].props.backgroundColor;
		if (read !== null) { return (read as Accessor<string>)(); }
	}
	return "#000000";
}

function mergedFlag(pick: (p: StatusBarProps) => Accessor<boolean> | null): string {
	for (let i = stack.length - 1; i >= 0; i -= 1) {
		const read = pick(stack[i].props);
		if (read !== null) { return (read as Accessor<boolean>)() ? "true" : "false"; }
	}
	return "false";
}

function merged(): string[] {
	return [
		mergedStyle(),
		mergedColor(),
		mergedFlag((p: StatusBarProps): Accessor<boolean> | null => p.hidden),
		mergedFlag((p: StatusBarProps): Accessor<boolean> | null => p.translucent),
	];
}

function writeMerged(top: StatusBarEntry, values: string[]): void {
	top.host.setAttr(top.node, "statusBarStyle", values[0]);
	top.host.setAttr(top.node, "statusBarBackgroundColor", values[1]);
	top.host.setAttr(top.node, "statusBarHidden", values[2]);
	top.host.setAttr(top.node, "statusBarTranslucent", values[3]);
}

const HIDDEN: Style = { display: "none" };

export function StatusBar(props: StatusBarProps): NeonNode {
	const grab = (host: Host): (node: HostNode) => void => (node: HostNode): void => {
		const entry = new StatusBarEntry(host, node, props);
		stack.push(entry);
		bump();
		createRenderEffect<string[]>(
			(prev: string[] | null): string[] => {
				revision();
				return stack.length > 0 && stack[stack.length - 1] === entry ? merged() : [];
			},
			(values: string[], prev: string[] | null): Cleanup | null => {
				if (values.length > 0) { writeMerged(entry, values); }
				return null;
			},
		);
		onCleanup((): void => {
			const at = stack.indexOf(entry);
			if (at >= 0) { stack.splice(at, 1); }
			if (stack.length === 0) { writeMerged(entry, merged()); }
			bump();
		});
	};
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		hostElement("statusbar", [], [], null, (): Style => HIDDEN, grab(host))(host, parent, before);
	};
}
