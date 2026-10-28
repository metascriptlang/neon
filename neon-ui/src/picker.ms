// @react-native-picker/picker, drawn by Neon: a field showing the selected label that opens
// the items as a list in a Modal, the shape of Android's `mode="dialog"` spinner. Items
// arrive as an `items` array instead of `<Picker.Item>` children (WORKAROUND.md M2).

import { NeonEvent } from "../../src/render/event";
import { Style } from "../../src/render/style";
import { Accessor, accessor, createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { For } from "../../src/macros/ui/flow";
import { NeonNode, VAttr, VEvent, dynAttr, evt, hostElement } from "../../src/render/node";
import { defaultRole, layered } from "../../src/components/drawn";
import { AccessibilityProps, ScrollView, Text, ViewHandle, accessibilityAttrs, viewGrab, viewMount, viewRef } from "../../src/components/primitives";
import { Modal } from "../../src/components/modal";
import { MATERIAL_DISABLED, MATERIAL_ON_SURFACE, MATERIAL_PRIMARY, colorOr, stateAttr, stateTokens } from "../../src/components/material";
import { Dialog } from "../../src/components/dialog";

export interface PickerItem {
	label: string;
	value: string;
}

export type PickerMode = "dialog" | "dropdown";

interface PickerProps extends AccessibilityProps {
	items: Accessor<PickerItem[]>;
	selectedValue?: Accessor<string> | null;
	onValueChange?: ((value: string, index: int32) => void) | null;
	enabled?: Accessor<boolean> | null;
	mode?: Accessor<PickerMode> | null;
	prompt?: Accessor<string> | null;
	color?: Accessor<string> | null;
	style?: Accessor<Style> | null;
	ref?: ((handle: ViewHandle) => void) | null;
	onLayout?: ((e: NeonEvent) => void) | null;
}

export function pickerIndexOf(items: PickerItem[], value: string): int32 {
	for (let i = 0; i < items.length; i += 1) {
		if (items[i].value === value) { return i as int32; }
	}
	return -1;
}

const FIELD: Style = {
	minHeight: 44, flexDirection: "row", alignItems: "center", justifyContent: "space-between",
	paddingLeft: 12, paddingRight: 12, borderRadius: 4, backgroundColor: "#eeeeee",
};
const SHEET: Style = { maxHeight: 480 };

export function Picker(props: PickerProps): NeonNode {
	const { items, selectedValue, onValueChange, enabled, prompt, color } = props;
	const [open, setOpen] = createSignal(false);
	const isEnabled = (): boolean => enabled === null || (enabled as Accessor<boolean>)();
	const selected = (): int32 => {
		const list = items();
		if (selectedValue === null) { return list.length > 0 ? 0 : -1; }
		return pickerIndexOf(list, (selectedValue as Accessor<string>)());
	};
	const selectedLabel = (): string => {
		const at = selected();
		return at < 0 ? "" : items()[at].label;
	};
	const ink = accessor((): Style => ({ color: isEnabled() ? colorOr(color, MATERIAL_ON_SURFACE) : MATERIAL_DISABLED, fontSize: 16 }));
	const close = (): void => { setOpen(false); };
	const pick = (index: int32): void => {
		setOpen(false);
		if (index === selected() || onValueChange === null) { return; }
		(onValueChange as (v: string, i: int32) => void)(items()[index].value, index);
	};
	const row = (item: PickerItem, index: Accessor<number>): NeonNode => {
		const isSelected = (): boolean => selected() === (index() as int32);
		const label = accessor((): Style => ({ color: isSelected() ? MATERIAL_PRIMARY : MATERIAL_ON_SURFACE, fontSize: 16 }));
		const attrs: VAttr[] = [];
		defaultRole(attrs, true, "menuitem");
		attrs.push(dynAttr("accessibilityLabel", (): string | null => item.label));
		stateAttr(attrs, (): string => stateTokens("", isSelected(), false));
		const press = (e: NeonEvent): void => { pick(index() as int32); };
		const box = (): Style => ({ minHeight: 48, justifyContent: "center" });
		return hostElement("pressable", attrs, [evt("onPress", press)], element(<Text style={label}>{item.label}</Text>), box, null);
	};
	const list = element(<ScrollView>
		<For each={items()}>{(item: PickerItem, index: Accessor<number>): NeonNode => row(item, index)}</For>
	</ScrollView>);
	const sheet = element(<Modal visible={open()} transparent={true} animationType="fade" onRequestClose={close}>
		{Dialog({ visible: accessor((): boolean => true), onDismiss: close, title: prompt, style: accessor((): Style => SHEET), children: list })}
	</Modal>);
	const attrs: VAttr[] = [];
	defaultRole(attrs, props.accessibilityRole === null, "combobox");
	accessibilityAttrs(props, attrs);
	stateAttr(attrs, (): string => stateTokens("", false, !isEnabled()));
	const evts: VEvent[] = [evt("onPress", (e: NeonEvent): void => { if (isEnabled()) { setOpen(true); } })];
	if (props.onLayout !== null) { evts.push(evt("onLayout", props.onLayout as (e: NeonEvent) => void)); }
	const handle = viewRef(props.ref);
	const field = viewMount(handle, hostElement("pressable", attrs, evts, element(<>
		<Text style={ink}>{selectedLabel()}</Text>
		<Text style={ink}>▾</Text>
	</>), layered(() => FIELD, props.style), viewGrab(handle)));
	return element(<>{field}{sheet}</>);
}
