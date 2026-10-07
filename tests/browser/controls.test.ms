import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { NeonEvent } from "../../src/render/event";

extern class ProbeAccent {
	accentColor: string;
}

extern class Node {
	tagName: string;
	value: string;
	selectedIndex: number;
	textContent: string;
	style: ProbeAccent;
	extern getAttribute(name: cstring): string | null;
	extern remove(): void;
}

extern class window {
	static extern eval(code: cstring): void;
}

function probe(n: HostNode): Node {
	return n as unknown as Node;
}

function mount(tag: string): HostNode {
	const h = domHost();
	const el = h.createElement(tag);
	h.insertBefore(documentBody(), el, null);
	return el;
}

test "Slider is a range input whose input events are value changes and whose change is the completion" {
	const h = domHost();
	const el = mount("slider");
	h.setAttr(el, "id", "neon-slider-probe");
	h.setAttr(el, "minimumValue", "1");
	h.setAttr(el, "maximumValue", "8");
	h.setAttr(el, "step", "1");
	h.setAttr(el, "value", "2");
	h.setAttr(el, "minimumTrackTintColor", "#ff0000");
	h.setAttr(el, "accessibilityRole", "adjustable");
	let seen = "";
	h.addEvent(el, "onValueChange", (e: NeonEvent): void => { seen += `${e.type} ${e.value};`; });
	h.addEvent(el, "onSlidingComplete", (e: NeonEvent): void => { seen += `${e.type} ${e.value};`; });
	const shape = `${probe(el).tagName} ${probe(el).getAttribute("type")} ${probe(el).getAttribute("min")}-${probe(el).getAttribute("max")} ${probe(el).value} ${probe(el).getAttribute("role")}`;
	assert shape === "INPUT range 1-8 2 slider", "shape: " + shape;
	assert probe(el).style.accentColor === "rgb(255, 0, 0)", "accent: " + probe(el).style.accentColor;
	window.eval("{ const s = document.getElementById('neon-slider-probe'); s.value = '5'; s.dispatchEvent(new Event('input')); s.dispatchEvent(new Event('change')); }");
	assert seen === "valuechange 5;slidingcomplete 5;", "events: " + seen;
	probe(el).remove();
}

test "Picker is a select whose options are the labels and whose change reports the chosen index" {
	const h = domHost();
	const el = mount("picker");
	h.setAttr(el, "id", "neon-picker-probe");
	h.setAttr(el, "items", "Standard\x1fstd\x1eDeluxe\x1fdlx\x1eSuite\x1fste");
	h.setAttr(el, "selectedIndex", "1");
	h.setAttr(el, "accessibilityState", "disabled");
	let seen = "";
	h.addEvent(el, "onValueChange", (e: NeonEvent): void => { seen += `${e.type} ${e.value};`; });
	assert `${probe(el).tagName} ${probe(el).textContent} ${probe(el).selectedIndex}` === "SELECT StandardDeluxeSuite 1", "shape: " + `${probe(el).tagName} ${probe(el).textContent} ${probe(el).selectedIndex}`;
	assert probe(el).getAttribute("aria-disabled") === "true", "state";
	h.setAttr(el, "items", "Standard\x1fstd\x1eDeluxe\x1fdlx\x1eSuite\x1fste\x1ePenthouse\x1fph");
	assert probe(el).selectedIndex === 1, "new items keep the selection";
	window.eval("{ const s = document.getElementById('neon-picker-probe'); s.selectedIndex = 3; s.dispatchEvent(new Event('change')); }");
	assert seen === "valuechange 3;", "events: " + seen;
	probe(el).remove();
}

test "DateTimePicker is a date, time or datetime-local input that reports its ISO value" {
	const h = domHost();
	const el = mount("datetimepicker");
	h.setAttr(el, "id", "neon-date-probe");
	h.setAttr(el, "mode", "date");
	h.setAttr(el, "minimumDate", "2026-10-01");
	h.setAttr(el, "value", "2026-10-07");
	let seen = "";
	h.addEvent(el, "onValueChange", (e: NeonEvent): void => { seen += `${e.type} ${e.value};`; });
	assert `${probe(el).getAttribute("type")} ${probe(el).getAttribute("min")} ${probe(el).value}` === "date 2026-10-01 2026-10-07", "date: " + `${probe(el).getAttribute("type")} ${probe(el).value}`;
	window.eval("{ const s = document.getElementById('neon-date-probe'); s.value = '2026-12-24'; s.dispatchEvent(new Event('change')); }");
	h.setAttr(el, "mode", "time");
	h.setAttr(el, "value", "18:30");
	assert `${probe(el).getAttribute("type")} ${probe(el).value}` === "time 18:30", "time: " + `${probe(el).getAttribute("type")} ${probe(el).value}`;
	h.setAttr(el, "mode", "datetime");
	assert probe(el).getAttribute("type") === "datetime-local", "datetime";
	assert seen === "valuechange 2026-12-24;", "events: " + seen;
	probe(el).remove();
}

test "accessibilityState maps onto aria-checked, aria-selected and aria-disabled and clears what it drops" {
	const h = domHost();
	const el = mount("pressable");
	h.setAttr(el, "accessibilityState", "checked,selected,disabled");
	const first = `${probe(el).getAttribute("aria-checked")} ${probe(el).getAttribute("aria-selected")} ${probe(el).getAttribute("aria-disabled")}`;
	assert first === "true true true", "first: " + first;
	h.setAttr(el, "accessibilityState", "mixed");
	const second = `${probe(el).getAttribute("aria-checked")} ${probe(el).getAttribute("aria-selected")} ${probe(el).getAttribute("aria-disabled")}`;
	assert second === "mixed null null", "second: " + second;
	probe(el).remove();
}
