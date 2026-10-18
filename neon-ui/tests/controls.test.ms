import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { Host, HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEvent, fireEventWith, fireTouch } from "../../src/render/host";
import { neonEvent } from "../../src/render/event";
import { Style } from "../../src/render/style";
import { View } from "../../src/components/primitives";
import { Slider, snapSliderValue } from "../src/slider";
import { Picker, PickerItem } from "../src/picker";
import { DateTimePicker, daysInMonth, isoDate, isoTime, weekdayOf } from "../src/dateTimePicker";

function overlayOf(host: Host): MockNode {
	return (host.overlayRoot as (n: HostNode) => HostNode)(mockNode("any") as unknown as HostNode) as unknown as MockNode;
}

function attr(n: MockNode, name: string): string {
	for (const a of n.attrs) {
		if (a.name === name) { return a.value ?? ""; }
	}
	return "";
}

function labelled(n: MockNode, label: string): MockNode | null {
	if (attr(n, "accessibilityLabel") === label) { return n; }
	for (const k of n.children) {
		const hit = labelled(k, label);
		if (hit !== null) { return hit; }
	}
	return null;
}

function press(n: MockNode, label: string): void {
	const hit = labelled(n, label);
	if (hit === null) { throw "nothing labelled " + label + " in " + mockToString(n); }
	fireEvent(hit as MockNode, "onPress");
}

function laidOut(n: MockNode, width: number): void {
	const e = neonEvent("layout");
	e.width = width;
	e.height = 40;
	fireEventWith(n, "onLayout", e);
}

function drag(target: MockNode, points: number[]): void {
	let t = 1000.0;
	fireTouch(target, "onTouchStart", points[0], 20, t);
	for (let i = 1; i < points.length; i += 1) {
		t += 16;
		fireTouch(target, "onTouchMove", points[i], 20, t);
	}
	fireTouch(target, "onTouchEnd", points[points.length - 1], 20, t + 16);
}

function thumbLeft(slider: MockNode): number {
	const thumb = slider.children[0].children[2];
	return (thumb.style as Style).left as number;
}

test "Slider moves by the drag distance over its track, snaps to the step and reports start, changes and completion" {
	const [guests, setGuests] = createSignal(2.0 as float64);
	let log = "";
	const root: MockNode = mockNode("root");
	render(element(<Slider value={guests()} minimumValue={0} maximumValue={8} step={1} accessibilityLabel="Guests"
		onSlidingStart={(v: float64): void => { log += `start ${v};`; }}
		onValueChange={(v: float64): void => { log += `change ${v};`; setGuests(v); }}
		onSlidingComplete={(v: float64): void => { log += `done ${v};`; }} />), mockHost(), root as unknown as HostNode);
	const slider = root.children[0];
	assert attr(slider, "accessibilityRole") === "adjustable" && attr(slider, "accessibilityLabel") === "Guests", "a11y: " + mockToString(root);
	laidOut(slider, 224);
	assert thumbLeft(slider) === 50, "2 of 0..8 sits a quarter along 200: " + thumbLeft(slider).toString();
	drag(slider.children[0], [100, 115, 130, 160, 400]);
	assert log === "start 2;change 3;change 4;change 8;done 8;", "events: " + log;
	assert guests() === 8 && thumbLeft(slider) === 200, "the thumb follows the value: " + thumbLeft(slider).toString();
	drag(slider.children[0], [100, 100]);
	assert log === "start 2;change 3;change 4;change 8;done 8;start 8;done 8;", "a tap reports no change: " + log;
}

test "Slider ignores a drag while disabled and flips direction when inverted" {
	const [off, setOff] = createSignal(true);
	let value: float64 = 0.5;
	const root: MockNode = mockNode("root");
	render(element(<Slider value={0.5} disabled={off()} inverted={true}
		onValueChange={(v: float64): void => { value = v; }} />), mockHost(), root as unknown as HostNode);
	const slider = root.children[0];
	laidOut(slider, 224);
	assert attr(slider, "accessibilityState") === "disabled", "disabled state: " + mockToString(slider);
	drag(slider.children[0], [100, 150]);
	assert value === 0.5, "no change while disabled";
	setOff(false);
	drag(slider.children[0], [100, 150]);
	assert value === 0.25, "a rightward drag lowers an inverted slider: " + value.toString();
}

test "snapSliderValue clamps to the range and snaps from the minimum, continuous without a step" {
	assert snapSliderValue(0.33, 0, 1, 0) === 0.33, "continuous";
	assert snapSliderValue(7.4, 1, 8, 2) === 7, "steps count from the minimum";
	assert snapSliderValue(-3, 1, 8, 1) === 1 && snapSliderValue(30, 1, 8, 1) === 8, "clamped";
}

test "Picker shows the selected label, lists the items in a dialog and reports the chosen item value" {
	const rooms: PickerItem[] = [{ label: "Standard", value: "std" }, { label: "Deluxe", value: "dlx" }, { label: "Suite", value: "ste" }];
	const [room, setRoom] = createSignal("dlx");
	let picked = "";
	const host = mockHost();
	const root: MockNode = mockNode("root");
	render(element(<Picker items={rooms} selectedValue={room()} prompt="Room" accessibilityLabel="Room type"
		onValueChange={(v: string, i: int32): void => { picked += `${v}@${i};`; setRoom(v); }} />), host, root as unknown as HostNode);
	const field = labelled(root, "Room type") as MockNode;
	assert attr(field, "accessibilityRole") === "combobox" && mockToString(field).indexOf("Deluxe") > 0, "field: " + mockToString(root);
	const overlay = overlayOf(host);
	assert overlay.children.length === 0, "closed";
	fireEvent(field, "onPress");
	assert mockToString(overlay).indexOf("Room") > 0 && attr(labelled(overlay, "Deluxe") as MockNode, "accessibilityState") === "selected", "open: " + mockToString(overlay);
	press(overlay, "Deluxe");
	assert picked === "" && overlay.children.length === 0, "the selected item closes without a report";
	fireEvent(field, "onPress");
	press(overlay, "Suite");
	assert picked === "ste@2;" && overlay.children.length === 0 && mockToString(field).indexOf("Suite") > 0, "picked: " + picked;
	fireEvent(field, "onPress");
	press(overlay, "Dismiss");
	assert picked === "ste@2;" && overlay.children.length === 0, "the scrim closes without a report";
}

test "Picker does not open while disabled" {
	const host = mockHost();
	const root: MockNode = mockNode("root");
	render(element(<Picker items={[{ label: "A", value: "a" }]} enabled={false} accessibilityLabel="Letter" />), host, root as unknown as HostNode);
	fireEvent(labelled(root, "Letter") as MockNode, "onPress");
	assert overlayOf(host).children.length === 0, "closed";
}

test "calendar arithmetic: month lengths with leap years and Sunday-based weekdays" {
	assert daysInMonth(2026, 2) === 28 && daysInMonth(2028, 2) === 29 && daysInMonth(2100, 2) === 28 && daysInMonth(2000, 2) === 29, "February";
	assert daysInMonth(2026, 4) === 30 && daysInMonth(2026, 12) === 31, "30 and 31";
	assert weekdayOf(2026, 10, 1) === 4 && weekdayOf(2026, 1, 1) === 4 && weekdayOf(2000, 1, 1) === 6, "weekdays";
	assert isoDate(2026, 3, 7) === "2026-03-07" && isoTime(9, 5) === "09:05", "ISO text";
}

test "DateTimePicker opens a calendar at the value's month, honours the bounds and reports the day on OK only" {
	const [day, setDay] = createSignal(isoDate(2026, 10, 7));
	let reports = 0;
	const host = mockHost();
	const root: MockNode = mockNode("root");
	render(element(<DateTimePicker value={day()} minimumDate="2026-10-05" accessibilityLabel="Check-in"
		onChange={(v: string): void => { reports += 1; setDay(v); }} />), host, root as unknown as HostNode);
	const field = labelled(root, "Check-in") as MockNode;
	assert mockToString(field).indexOf("2026-10-07") > 0, "field: " + mockToString(field);
	const overlay = overlayOf(host);
	fireEvent(field, "onPress");
	assert mockToString(overlay).indexOf("October 2026") > 0, "month: " + mockToString(overlay);
	assert attr(labelled(overlay, "October 7, 2026") as MockNode, "accessibilityState") === "selected", "the value is selected";
	assert attr(labelled(overlay, "October 4, 2026") as MockNode, "accessibilityState") === "disabled", "before the minimum";
	press(overlay, "October 4, 2026");
	press(overlay, "October 24, 2026");
	press(overlay, "Cancel");
	assert reports === 0 && day() === "2026-10-07" && overlay.children.length === 0, "Cancel reports nothing";
	fireEvent(field, "onPress");
	press(overlay, "Next month");
	assert mockToString(overlay).indexOf("November 2026") > 0, "next month";
	press(overlay, "November 2, 2026");
	press(overlay, "OK");
	assert reports === 1 && day() === "2026-11-02" && mockToString(field).indexOf("2026-11-02") > 0, "chosen: " + day();
}

test "DateTimePicker in time mode picks hour and minute on wheels, and inline reports each choice at once" {
	const [time, setTime] = createSignal(isoTime(9, 5));
	const [when, setWhen] = createSignal("2026-10-07T18:30");
	const host = mockHost();
	const root: MockNode = mockNode("root");
	render(element(<View>
		<DateTimePicker value={time()} mode="time" accessibilityLabel="Arrival" onChange={(v: string): void => { setTime(v); }} />
		<DateTimePicker value={when()} mode="datetime" display="inline" onChange={(v: string): void => { setWhen(v); }} />
	</View>), host, root as unknown as HostNode);
	const overlay = overlayOf(host);
	fireEvent(labelled(root, "Arrival") as MockNode, "onPress");
	const scrolls: MockNode[] = [];
	const collect = (n: MockNode): void => {
		if (n.tag === "scrollview") { scrolls.push(n); }
		for (const k of n.children) { collect(k); }
	};
	collect(overlay);
	assert scrolls.length === 2, "two wheels: " + mockToString(overlay);
	const scrollTo = (wheel: MockNode, y: number): void => {
		const e = neonEvent("scroll");
		e.y = y;
		e.height = 160;
		fireEventWith(wheel, "onScroll", e);
	};
	scrollTo(scrolls[0], 14 * 32);
	scrollTo(scrolls[1], 45 * 32);
	press(overlay, "OK");
	assert time() === "14:45", "time: " + time();
	press(root, "October 9, 2026");
	assert when() === "2026-10-09T18:30", "inline day: " + when();
}
