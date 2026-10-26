import { NeonNode } from "../../src/render/node";
import { flush } from "../../src/core/runtime";
import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { HostNode, MockNode, mockNode, mockHost, render, fireEventWith } from "../../src/render/host";
import { Pressable, Text, TextInput, View, accessibilityActionsText } from "../../src/components/primitives";

function attrOf(n: MockNode, name: string): string {
	for (const a of n.attrs) {
		if (a.name === name) { return a.value ?? ""; }
	}
	return "<unset>";
}

function mounted(node: NeonNode): MockNode {
	const root: MockNode = mockNode("root");
	render(node, mockHost(), root as unknown as HostNode);
	return root.children[0];
}

test "View sends every accessibility prop under its own attribute name" {
	const [now, setNow] = createSignal(30);
	const view = mounted(element(<View
		role="slider" accessibilityValue={{ min: 0, max: 100, now: now(), text: "thirty, of a hundred" }}
		accessibilityLiveRegion="polite" importantForAccessibility="no-hide-descendants"
		accessibilityElementsHidden={true} accessibilityViewIsModal={false}
		accessibilityLabelledBy="title,  hint" accessibilityActions={[{ name: "activate" }, { name: "magicTap", label: "Open it" }]}
	/>));
	assert attrOf(view, "role") === "slider", attrOf(view, "role");
	assert attrOf(view, "accessibilityValue") === "0,100,30,thirty, of a hundred", attrOf(view, "accessibilityValue");
	assert attrOf(view, "accessibilityLiveRegion") === "polite";
	assert attrOf(view, "importantForAccessibility") === "no-hide-descendants";
	assert attrOf(view, "accessibilityElementsHidden") === "true";
	assert attrOf(view, "accessibilityViewIsModal") === "false";
	assert attrOf(view, "accessibilityLabelledBy") === "title,hint", attrOf(view, "accessibilityLabelledBy");
	assert attrOf(view, "accessibilityActions") === "activate\nmagicTap\tOpen it", attrOf(view, "accessibilityActions");
	setNow(55);
	flush();
	assert attrOf(view, "accessibilityValue") === "0,100,55,thirty, of a hundred", attrOf(view, "accessibilityValue");
}

test "an accessibilityValue with only a text leaves the numbers empty" {
	const view = mounted(element(<View accessibilityValue={{ text: "half" }} />));
	assert attrOf(view, "accessibilityValue") === ",,,half", attrOf(view, "accessibilityValue");
}

test "Text, Pressable and TextInput send the same attributes" {
	const text = mounted(element(<Text role="heading" accessibilityLiveRegion="assertive" accessibilityValue={{ now: 2 }}>t</Text>));
	assert attrOf(text, "role") === "heading" && attrOf(text, "accessibilityLiveRegion") === "assertive", mockAttrs(text);
	assert attrOf(text, "accessibilityValue") === ",,2,", attrOf(text, "accessibilityValue");
	const press = mounted(element(<Pressable role="button" accessibilityViewIsModal={true} accessibilityElementsHidden={false}
		accessibilityActions={[{ name: "longpress" }]} accessibilityLabelledBy="a" onPress={(e: NeonEvent): void => {}}><Text>p</Text></Pressable>));
	assert attrOf(press, "role") === "button" && attrOf(press, "accessibilityViewIsModal") === "true", mockAttrs(press);
	assert attrOf(press, "accessibilityElementsHidden") === "false" && attrOf(press, "accessibilityActions") === "longpress", mockAttrs(press);
	assert attrOf(press, "accessibilityLabelledBy") === "a", mockAttrs(press);
	const input = mounted(element(<TextInput role="searchbox" importantForAccessibility="no" accessibilityLabelledBy="x,y"
		accessibilityValue={{ min: 1, max: 9 }} />));
	assert attrOf(input, "role") === "searchbox" && attrOf(input, "importantForAccessibility") === "no", mockAttrs(input);
	assert attrOf(input, "accessibilityLabelledBy") === "x,y" && attrOf(input, "accessibilityValue") === "1,9,,", mockAttrs(input);
}

function mockAttrs(n: MockNode): string {
	let out = "";
	for (const a of n.attrs) { out = out + a.name + "=" + (a.value ?? "") + ";"; }
	return out;
}

test "a prop that is not given writes no attribute" {
	const view = mounted(element(<View accessibilityLabel="plain" />));
	assert attrOf(view, "role") === "<unset>" && attrOf(view, "accessibilityValue") === "<unset>" && attrOf(view, "accessibilityActions") === "<unset>", mockAttrs(view);
	assert attrOf(view, "focusable") === "<unset>", mockAttrs(view);
}

test "tabIndex lowers to focusable = !tabIndex and wins over focusable" {
	const [tab, setTab] = createSignal(0);
	const view = mounted(element(<View tabIndex={tab()} focusable={false} />));
	assert attrOf(view, "focusable") === "true", mockAttrs(view);
	setTab(-1);
	flush();
	assert attrOf(view, "focusable") === "false", mockAttrs(view);
	const only = mounted(element(<View focusable={false} />));
	assert attrOf(only, "focusable") === "false", mockAttrs(only);
	const input = mounted(element(<TextInput tabIndex={-1} />));
	assert attrOf(input, "focusable") === "false", mockAttrs(input);
	const press = mounted(element(<Pressable tabIndex={0} onPress={(e: NeonEvent): void => {}}><Text>p</Text></Pressable>));
	assert attrOf(press, "focusable") === "true", mockAttrs(press);
}

test "onAccessibilityAction receives the action name in NeonEvent.value on every primitive" {
	let seen = "";
	const handler = (e: NeonEvent): void => { seen = seen + e.value + ";"; };
	const nodes: MockNode[] = [
		mounted(element(<View accessibilityActions={[{ name: "activate" }]} onAccessibilityAction={handler} />)),
		mounted(element(<Text onAccessibilityAction={handler}>t</Text>)),
		mounted(element(<Pressable onAccessibilityAction={handler} onPress={(e: NeonEvent): void => {}}><Text>p</Text></Pressable>)),
		mounted(element(<TextInput onAccessibilityAction={handler} />)),
	];
	const names = ["activate", "increment", "decrement", "magicTap"];
	for (let i = 0; i < nodes.length; i++) {
		const e = neonEvent("accessibilityaction");
		e.value = names[i];
		fireEventWith(nodes[i], "onAccessibilityAction", e);
	}
	assert seen === "activate;increment;decrement;magicTap;", seen;
}

test "an action name holding a tab is refused" {
	let threw = false;
	try {
		accessibilityActionsText([{ name: "a\tb" }]);
	} catch (e) {
		threw = true;
	}
	assert threw, "a tab would split the host's record";
}
