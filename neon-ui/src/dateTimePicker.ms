// @react-native-community/datetimepicker, drawn by Neon: a field showing the value that opens
// a month calendar (date), hour and minute wheels (time) or both (datetime) in a dialog with
// Cancel and OK, the shape of Flutter's showDatePicker; `display="inline"` puts the calendar
// or wheels in place and reports each choice at once. MetaScript has no `Date` instance yet,
// so values are local ISO-8601 text: "2026-10-07", "18:30", "2026-10-07T18:30" (WORKAROUND.md M3).

import { NeonEvent } from "../../src/render/event";
import { Style } from "../../src/render/style";
import { Accessor, accessor, createSignal, untrack } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { For, Show } from "../../src/macros/ui/flow";
import { Host, HostNode } from "../../src/render/hostTypes";
import { NeonNode, RefFn, VAttr, VEvent, dynAttr, evt, hostElement } from "../../src/render/node";
import { defaultRole, layered } from "../../src/components/drawn";
import { AccessibilityProps, Pressable, Text, View, accessibilityAttrs } from "../../src/components/primitives";
import { Modal } from "../../src/components/modal";
import { Dialog, DialogAction } from "../../src/components/dialog";
import { ListWheelScrollView, WheelRenderItemInfo } from "../../src/components/listWheel";
import { MATERIAL_DISABLED, MATERIAL_ON_PRIMARY, MATERIAL_ON_SURFACE, MATERIAL_PRIMARY, colorOr, flagOn, stateAttr, stateTokens } from "../../src/components/material";

export type DateTimeMode = "date" | "time" | "datetime";
export type DateTimeDisplay = "default" | "compact" | "inline" | "spinner";

interface DateTimePickerProps extends AccessibilityProps {
	value: Accessor<string>;
	mode?: Accessor<DateTimeMode> | null;
	display?: Accessor<DateTimeDisplay> | null;
	minimumDate?: Accessor<string> | null;
	maximumDate?: Accessor<string> | null;
	disabled?: Accessor<boolean> | null;
	accentColor?: Accessor<string> | null;
	textColor?: Accessor<string> | null;
	onChange?: ((value: string) => void) | null;
	style?: Accessor<Style> | null;
	ref?: RefFn | null;
	onLayout?: ((e: NeonEvent) => void) | null;
}

function pad2(n: int32): string {
	return n < 10 ? "0" + n.toString() : n.toString();
}

export function isoDate(year: int32, month: int32, day: int32): string {
	return year.toString() + "-" + pad2(month) + "-" + pad2(day);
}

export function isoTime(hour: int32, minute: int32): string {
	return pad2(hour) + ":" + pad2(minute);
}

export function daysInMonth(year: int32, month: int32): int32 {
	if (month === 2) { return (year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0)) ? 29 : 28; }
	return month === 4 || month === 6 || month === 9 || month === 11 ? 30 : 31;
}

// Sakamoto's method: 0 is Sunday.
export function weekdayOf(year: int32, month: int32, day: int32): int32 {
	const offsets: number[] = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4];
	const y: number = month < 3 ? year - 1 : year;
	return ((y + Math.floor(y / 4) - Math.floor(y / 100) + Math.floor(y / 400) + offsets[month - 1] + day) % 7) as int32;
}

function field(text: string, at: int32, length: int32): int32 {
	let n: int32 = 0;
	for (let i = at; i < at + length; i += 1) {
		const c = i < text.length ? text.charCodeAt(i) : 0;
		if (c < 48 || c > 57) { throw `DateTimePicker: "${text}" is not a local ISO-8601 date, time or date and time`; }
		n = n * 10 + (c - 48) as int32;
	}
	return n;
}

interface DateParts {
	year: int32;
	month: int32;
	day: int32;
	hour: int32;
	minute: int32;
}

function partsOf(text: string, date: boolean, time: boolean): DateParts {
	const at: int32 = date ? 11 : 0;
	return {
		year: date ? field(text, 0, 4) : 0,
		month: date ? field(text, 5, 2) : 1,
		day: date ? field(text, 8, 2) : 1,
		hour: time ? field(text, at, 2) : 0,
		minute: time ? field(text, at + 3, 2) : 0,
	};
}

const MONTHS: string[] = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const WEEKDAYS: string[] = ["S", "M", "T", "W", "T", "F", "S"];

function range(count: int32): number[] {
	const out: number[] = [];
	for (let i = 0; i < count; i += 1) { out.push(i); }
	return out;
}

function twoDigits(count: int32): string[] {
	const out: string[] = [];
	for (let i = 0; i < count; i += 1) { out.push(pad2(i as int32)); }
	return out;
}

const CELL = 36;
const ITEM = 32;
const FIELD: Style = { minHeight: 44, justifyContent: "center", paddingLeft: 12, paddingRight: 12, borderRadius: 4, backgroundColor: "#eeeeee" };
const HEADER: Style = { flexDirection: "row", alignItems: "center", justifyContent: "space-between", height: 40 };
const ARROW: Style = { width: 40, height: 40, alignItems: "center", justifyContent: "center" };
const GRID: Style = { flexDirection: "row", flexWrap: "wrap", width: CELL * 7 };
const WHEELS: Style = { flexDirection: "row", justifyContent: "center", gap: 16 };
const WHEEL: Style = { width: 56, height: ITEM * 5 };

export function DateTimePicker(props: DateTimePickerProps): NeonNode {
	const { value, mode, display, minimumDate, maximumDate, disabled, accentColor, textColor, onChange } = props;
	const modeOf = (): DateTimeMode => mode === null ? "date" : (mode as Accessor<DateTimeMode>)();
	const hasDate = (): boolean => modeOf() !== "time";
	const hasTime = (): boolean => modeOf() !== "date";
	const inline = (): boolean => display !== null && (display as Accessor<DateTimeDisplay>)() === "inline";
	const start = untrack<DateParts>((): DateParts => partsOf(value(), hasDate(), hasTime()));
	const [open, setOpen] = createSignal(false);
	const [viewYear, setViewYear] = createSignal<int32>(start.year);
	const [viewMonth, setViewMonth] = createSignal<int32>(start.month);
	const [picked, setPicked] = createSignal(start.year > 0 ? isoDate(start.year, start.month, start.day) : "");
	const [hour, setHour] = createSignal<int32>(start.hour);
	const [minute, setMinute] = createSignal<int32>(start.minute);
	const ink = (): string => flagOn(disabled) ? MATERIAL_DISABLED : colorOr(textColor, MATERIAL_ON_SURFACE);
	const accent = (): string => colorOr(accentColor, MATERIAL_PRIMARY);

	const load = (): void => {
		const parts = partsOf(untrack<string>(value), hasDate(), hasTime());
		if (parts.year > 0) {
			setViewYear(parts.year);
			setViewMonth(parts.month);
			setPicked(isoDate(parts.year, parts.month, parts.day));
		}
		setHour(parts.hour);
		setMinute(parts.minute);
	};
	const result = (): string => {
		const time = isoTime(untrack<int32>(hour), untrack<int32>(minute));
		if (!hasDate()) { return time; }
		return hasTime() ? untrack<string>(picked) + "T" + time : untrack<string>(picked);
	};
	const report = (): void => {
		const next = result();
		if (next !== untrack<string>(value) && onChange !== null) { (onChange as (v: string) => void)(next); }
	};
	const changed = (): void => { if (inline()) { report(); } };
	const allowed = (iso: string): boolean =>
		(minimumDate === null || iso >= (minimumDate as Accessor<string>)().slice(0, 10)) &&
		(maximumDate === null || iso <= (maximumDate as Accessor<string>)().slice(0, 10));
	const turn = (by: int32): void => {
		const months = untrack<int32>(viewYear) * 12 + untrack<int32>(viewMonth) - 1 + by;
		setViewYear(Math.floor(months / 12) as int32);
		setViewMonth((months % 12 + 1) as int32);
	};

	const cell = (index: number): NeonNode => {
		const day = (): int32 => {
			const d = (index as int32) - weekdayOf(viewYear(), viewMonth(), 1) + 1;
			return d >= 1 && d <= daysInMonth(viewYear(), viewMonth()) ? d : 0;
		};
		const iso = (): string => isoDate(viewYear(), viewMonth(), day());
		const enabled = (): boolean => day() > 0 && allowed(iso());
		const isPicked = (): boolean => day() > 0 && picked() === iso();
		const box = accessor((): Style => ({
			width: CELL, height: CELL, borderRadius: CELL / 2, alignItems: "center", justifyContent: "center",
			backgroundColor: isPicked() ? accent() : "transparent",
		}));
		const label = accessor((): Style => ({
			fontSize: 14,
			color: isPicked() ? MATERIAL_ON_PRIMARY : enabled() ? colorOr(textColor, MATERIAL_ON_SURFACE) : MATERIAL_DISABLED,
		}));
		const attrs: VAttr[] = [];
		attrs.push(dynAttr("accessible", (): string | null => day() > 0 ? "true" : "false"));
		defaultRole(attrs, true, "button");
		attrs.push(dynAttr("accessibilityLabel", (): string | null => day() > 0 ? `${MONTHS[viewMonth() - 1]} ${day()}, ${viewYear()}` : ""));
		stateAttr(attrs, (): string => stateTokens("", isPicked(), !enabled()));
		const press = (e: NeonEvent): void => {
			if (!enabled()) { return; }
			setPicked(iso());
			changed();
		};
		return hostElement("pressable", attrs, [evt("onPress", press)], element(<Text style={label}>{day() > 0 ? day().toString() : ""}</Text>), box as () => Style, null);
	};
	const calendar = element(<View>
		<View style={HEADER}>
			<Pressable style={ARROW} onPress={(e: NeonEvent): void => { turn(-1); }} accessibilityRole="button" accessibilityLabel="Previous month"><Text>‹</Text></Pressable>
			<Text style={{ fontSize: 16, fontWeight: "bold", color: MATERIAL_ON_SURFACE }}>{`${MONTHS[viewMonth() - 1]} ${viewYear()}`}</Text>
			<Pressable style={ARROW} onPress={(e: NeonEvent): void => { turn(1); }} accessibilityRole="button" accessibilityLabel="Next month"><Text>›</Text></Pressable>
		</View>
		<View style={GRID}>
			<For each={range(7)}>{(index: number, at: Accessor<number>): NeonNode =>
				<View style={{ width: CELL, height: 24, alignItems: "center" }}><Text style={{ fontSize: 12, color: MATERIAL_DISABLED }}>{WEEKDAYS[index as int32]}</Text></View>}</For>
			<For each={range(42)}>{(index: number, at: Accessor<number>): NeonNode => cell(index)}</For>
		</View>
	</View>);
	const wheel = (labels: string[], name: string, initial: int32, choose: (i: int32) => void): NeonNode => element(<ListWheelScrollView
		data={labels} itemExtent={ITEM} initialItem={initial as number} style={WHEEL}
		onSelectedItemChanged={(i: number): void => { choose(i as int32); changed(); }}
		renderItem={(info: WheelRenderItemInfo<string>): NeonNode =>
			<Text style={{ fontSize: 20, textAlign: "center", color: MATERIAL_ON_SURFACE }} accessibilityLabel={`${info.item} ${name}`}>{info.item}</Text>} />);
	const panel = (): NeonNode => element(<View style={{ gap: 12 }}>
		<Show when={hasDate()}>{calendar}</Show>
		<Show when={hasTime()}>
			<View style={WHEELS}>
				{wheel(twoDigits(24), "hours", untrack<int32>(hour), (i: int32): void => { setHour(i); })}
				{wheel(twoDigits(60), "minutes", untrack<int32>(minute), (i: int32): void => { setMinute(i); })}
			</View>
		</Show>
	</View>);

	const close = (): void => { setOpen(false); };
	const confirm = (): void => {
		setOpen(false);
		report();
	};
	const actions = element(<>
		<DialogAction label="Cancel" onPress={close} color={accent()} />
		<DialogAction label="OK" onPress={confirm} color={accent()} />
	</>);
	const opened: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => { panel()(host, parent, before); };
	const sheet = element(<Modal visible={open()} transparent={true} animationType="fade" onRequestClose={close}>
		<Dialog visible={true} onDismiss={close} actions={actions}>{opened}</Dialog>
	</Modal>);
	const attrs: VAttr[] = [];
	defaultRole(attrs, props.accessibilityRole === null, "button");
	accessibilityAttrs(props, attrs);
	stateAttr(attrs, (): string => stateTokens("", false, flagOn(disabled)));
	const evts: VEvent[] = [evt("onPress", (e: NeonEvent): void => {
		if (flagOn(disabled)) { return; }
		load();
		setOpen(true);
	})];
	if (props.onLayout !== null) { evts.push(evt("onLayout", props.onLayout as (e: NeonEvent) => void)); }
	const text = accessor((): Style => ({ color: ink(), fontSize: 16 }));
	const opener = hostElement("pressable", attrs, evts, element(<Text style={text}>{value()}</Text>), layered(() => FIELD, props.style), props.ref);
	const inPlace: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => { panel()(host, parent, before); };
	return element(<Show when={inline()} fallback={<>{opener}{sheet}</>}>{inPlace}</Show>);
}
