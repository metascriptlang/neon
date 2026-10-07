import { createSignal } from "../../src/core/signal";
import { Dispose } from "../../src/core/types";
import { element } from "../../src/macros/ui/element";
import { neonEvent } from "../../src/render/event";
import { NeonNode } from "../../src/render/node";
import { Style } from "../../src/render/style";
import { HostNode, MockNode, mockNode, mockHost, render, fireEvent, fireEventWith } from "../../src/render/host";
import { Text, View } from "../../src/components/primitives";
import { useManualFrames, setFrameDriver } from "../../src/animation/frame";
import { Accordion, Collapsible, ExpansionTile } from "../../src/components/collapsible";
import { Accessor } from "../../src/core/signal";

let disposeLast: Dispose | null = null;

function mount(app: () => NeonNode): MockNode {
	const root = mockNode("root");
	disposeLast = render(app(), mockHost(), root as unknown as HostNode);
	return root;
}

function unmount(): void {
	if (disposeLast !== null) { (disposeLast as Dispose)(); }
	disposeLast = null;
	setFrameDriver(null);
}

function attrOf(n: MockNode, name: string): string {
	for (const a of n.attrs) {
		if (a.name === name) { return a.value ?? ""; }
	}
	return "";
}

function collect(n: MockNode, test: (m: MockNode) => boolean, out: MockNode[]): MockNode[] {
	if (test(n)) { out.push(n); }
	for (const k of n.children) { collect(k, test, out); }
	return out;
}

function styleOf(n: MockNode): Style {
	return n.style === null ? {} : n.style as Style;
}

function laidOut(n: MockNode, height: number): void {
	const e = neonEvent("layout");
	e.width = 300;
	e.height = height;
	fireEventWith(n, "onLayout", e);
}

function buttons(root: MockNode): MockNode[] {
	return collect(root, (m: MockNode): boolean => attrOf(m, "accessibilityRole") === "button", []);
}

test "a Collapsible animates from zero to its measured height and then lets it size itself" {
	const clock = useManualFrames();
	const [collapsed, setCollapsed] = createSignal(true);
	let ended = 0;
	const root = mount((): NeonNode => element(<Collapsible collapsed={collapsed()} duration={160}
		onAnimationEnd={(): void => { ended += 1; }}>
		<View style={{ height: 120 }}><Text>details</Text></View>
	</Collapsible>));
	const outer = root.children[0];
	const inner = outer.children[0];
	assert styleOf(outer).height === 0 && styleOf(inner).display === "none", "starts closed and hidden";
	setCollapsed(false);
	assert styleOf(inner).display === "flex", "shown to be measured";
	laidOut(inner, 120);
	clock.step(5);
	const half = styleOf(outer).height as number;
	assert half > 0 && half < 120, "on its way: " + half.toString();
	clock.runAll();
	assert styleOf(outer).height === null && ended === 1, "open at rest has no fixed height";
	setCollapsed(true);
	clock.step(2);
	assert (styleOf(outer).height as number) < 120, "closing";
	clock.runAll();
	assert styleOf(outer).height === 0 && styleOf(inner).display === "none" && ended === 2, "closed and hidden again";
	unmount();
}

test "a collapsed height keeps a peek of the content visible" {
	const clock = useManualFrames();
	const root = mount((): NeonNode => element(<Collapsible collapsed={true} collapsedHeight={30}>
		<View style={{ height: 120 }} />
	</Collapsible>));
	const outer = root.children[0];
	assert styleOf(outer).height === 30 && styleOf(outer.children[0]).display === "flex", "a 30 pt peek";
	unmount();
}

test "an ExpansionTile toggles, turns its icon and reports its state" {
	const clock = useManualFrames();
	const changes: boolean[] = [];
	const root = mount((): NeonNode => element(<ExpansionTile title="Shipping" subtitle="3 options"
		onExpansionChanged={(x: boolean): void => { changes.push(x); }}>
		<Text>Standard</Text>
	</ExpansionTile>));
	const header = buttons(root)[0];
	assert attrOf(header, "accessibilityState") === "collapsed" && attrOf(header, "accessibilityLabel") === "Shipping";
	const icon = collect(root, (m: MockNode): boolean => m.style !== null && ((m.style as Style).transform ?? "").indexOf("rotate") === 0, [])[0];
	assert styleOf(icon).transform === "rotate(0deg)", styleOf(icon).transform as string;
	fireEvent(header, "onPress");
	const body = collect(root, (m: MockNode): boolean => m.style !== null && (m.style as Style).flexShrink === 0, [])[0];
	laidOut(body, 48);
	clock.runAll();
	assert changes.join(",") === "true" && attrOf(header, "accessibilityState") === "expanded", changes.join(",");
	assert styleOf(icon).transform === "rotate(180deg)", styleOf(icon).transform as string;
	fireEvent(header, "onPress");
	clock.runAll();
	assert changes.join(",") === "true,false" && styleOf(icon).transform === "rotate(0deg)";
	unmount();
}

interface Faq {
	question: string;
	answer: string;
}

function faqs(): Faq[] {
	return [{ question: "Q1", answer: "A1" }, { question: "Q2", answer: "A2" }, { question: "Q3", answer: "A3" }];
}

function accordion(active: Accessor<number[]>, change: (next: number[]) => void, multiple: boolean): NeonNode {
	return element(<Accordion sections={faqs()} activeSections={active()} expandMultiple={multiple} onChange={change}
		renderHeader={(s: Faq, i: number, open: Accessor<boolean>): NeonNode => <Text>{s.question + (open() ? " -" : " +")}</Text>}
		renderContent={(s: Faq, i: number, open: Accessor<boolean>): NeonNode => <Text>{s.answer}</Text>} />);
}

test "an Accordion opens one section at a time unless it expands several" {
	const clock = useManualFrames();
	const [active, setActive] = createSignal<number[]>([]);
	const seen: string[] = [];
	const root = mount((): NeonNode => accordion(active, (next: number[]): void => { seen.push(next.join("|")); setActive(next); }, false));
	const headers = buttons(root);
	assert headers.length === 3, "three headers";
	fireEvent(headers[0], "onPress");
	fireEvent(headers[2], "onPress");
	fireEvent(headers[2], "onPress");
	assert seen.join(",") === "0,2,", "single: " + seen.join(",");
	assert attrOf(headers[0], "accessibilityState") === "collapsed";
	(disposeLast as Dispose)();
	const [many, setMany] = createSignal<number[]>([]);
	const seenMany: string[] = [];
	const again = mount((): NeonNode => accordion(many, (next: number[]): void => { seenMany.push(next.join("|")); setMany(next); }, true));
	const more = buttons(again);
	fireEvent(more[0], "onPress");
	fireEvent(more[2], "onPress");
	fireEvent(more[0], "onPress");
	assert seenMany.join(",") === "0,0|2,2", "multiple: " + seenMany.join(",");
	assert attrOf(more[2], "accessibilityState") === "expanded";
	unmount();
}
