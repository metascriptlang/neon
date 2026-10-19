import { domHost } from "../../src/platform/browser/dom";
import { HostNode, NeonNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { ScrollView, Text, TextInput, View } from "../../src/components/primitives";
import { refreshBoundary0, refreshComponent0, refreshModule, refreshReset } from "../../src/render/refresh";
import { sleepAsync } from "std/core/promise";

extern function js(code: cstring): string from "String((0, eval)(#))";
extern class Container {
	id: string;
}
extern function freshContainer(id: cstring): Container from "document.body.appendChild(Object.assign(document.createElement('div'), { id: # }))";

const FILE = "tests/browser/refresh.test.ms";

function rows(): NeonNode {
	return element(<View>
		<View style={{ height: 50 }} /><View style={{ height: 50 }} /><View style={{ height: 50 }} /><View style={{ height: 50 }} />
		<View style={{ height: 50 }} /><View style={{ height: 50 }} /><View style={{ height: 50 }} /><View style={{ height: 50 }} />
	</View>);
}

function feedV1(): NeonNode {
	return element(<View>
		<ScrollView style={{ height: 100 }}>{rows()}</ScrollView>
		<TextInput placeholder="v1" />
	</View>);
}

function feedV2(): NeonNode {
	return element(<View>
		<ScrollView style={{ height: 120 }}>{rows()}</ScrollView>
		<TextInput placeholder="v2" />
		<Text>v2</Text>
	</View>);
}

test "a refresh remount keeps the scroll offset, the typed text and the focus of the nodes it still renders" {
	refreshReset();
	const dispose = render(refreshBoundary0(FILE, "Feed", feedV1, (): string => "v1"), domHost(), freshContainer("neon-refresh") as unknown as HostNode);
	js("const root = document.getElementById('neon-refresh'); window.neonScroller = root.querySelector(':scope > div > div'); window.neonField = root.querySelector('input'); neonScroller.scrollTop = 80; neonField.value = 'typed'; neonField.focus()");
	assert js("neonScroller.scrollTop") === "80", "the scroller scrolls before the edit: " + js("neonScroller.scrollTop");
	refreshComponent0(FILE, "Feed", feedV2, (): string => "v2");
	const summary = refreshModule(FILE);
	assert summary.remounted === 1, "the component remounts: " + summary.remounted.toString();
	await sleepAsync(0);
	assert js("document.getElementById('neon-refresh').querySelector(':scope > div > div') === neonScroller") === "true", "the scroller is the same element";
	assert js("neonScroller.clientHeight") === "120", "it carries the new style: " + js("neonScroller.clientHeight");
	assert js("neonScroller.scrollTop") === "80", "and the old offset: " + js("neonScroller.scrollTop");
	assert js("document.getElementById('neon-refresh').querySelector('input') === neonField") === "true", "the field is the same element";
	assert js("neonField.value + ' ' + neonField.placeholder") === "typed v2", "with the typed text and the new placeholder: " + js("neonField.value + ' ' + neonField.placeholder");
	assert js("document.activeElement === neonField") === "true", "and the focus";
	assert js("document.getElementById('neon-refresh').textContent") === "v2", "the new text is mounted";
	dispose();
	js("document.getElementById('neon-refresh').remove(); delete window.neonScroller; delete window.neonField");
}
