import { Accessor } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { createRoot } from "../../src/core/owner";
import { Dispose } from "../../src/core/types";
import { NavigationChild } from "../../src/navigation/children";
import { ChildSlot, createChildSlot } from "../../src/navigation/childSlot";

interface Dialog {
	name: string;
	title: string;
}

interface DialogInstance {
	name: string;
	configuration: Accessor<Dialog>;
	active: Accessor<boolean>;
}

let created = "";
let disposed = "";

function dialog(name: string): Dialog {
	return { name, title: "" };
}

function dialogKey(dialog: Dialog): string {
	return dialog.name;
}

function makeSlot(initial: Dialog | null): ChildSlot<Dialog, DialogInstance> {
	created = "";
	disposed = "";
	return createChildSlot<Dialog, DialogInstance>(
		initial,
		dialogKey,
		(configuration: Accessor<Dialog>, active: Accessor<boolean>): DialogInstance => {
			const name = configuration().name;
			created += name + ";";
			onCleanup((): void => { disposed += name + ";"; });
			return { name, configuration, active };
		},
	);
}

function shown(slot: ChildSlot<Dialog, DialogInstance>): string {
	const child = slot.child();
	if (child === null) { return "none"; }
	const present = child as NavigationChild<Dialog, DialogInstance>;
	return present.instance.name + (present.active() ? "*" : "");
}

function instanceOf(slot: ChildSlot<Dialog, DialogInstance>): DialogInstance {
	return (slot.child() as NavigationChild<Dialog, DialogInstance>).instance;
}

function failure(run: () => void): string {
	try { run(); } catch (error) { return error.message; }
	return "";
}

test "a slot created without a configuration has no child, and with one has it active" {
	const empty = makeSlot(null);
	assert shown(empty) === "none", shown(empty);
	assert empty.configuration() === null;
	assert empty.items().length === 0 && created === "", created;
	empty.dispose();
	const open = makeSlot(dialog("confirm"));
	assert shown(open) === "confirm*", shown(open);
	assert created === "confirm;", created;
	open.dispose();
}

test "activate shows a child, and dismiss disposes it" {
	const slot = makeSlot(null);
	slot.activate(dialog("confirm"));
	assert shown(slot) === "confirm*", shown(slot);
	const confirm = instanceOf(slot);
	assert confirm.active(), "an activated child is active";
	assert slot.dismiss();
	assert shown(slot) === "none", shown(slot);
	assert disposed === "confirm;", disposed;
	slot.dispose();
}

test "activate with the same key keeps the instance and updates its configuration" {
	const slot = makeSlot(dialog("confirm"));
	const confirm = instanceOf(slot);
	slot.activate(dialog("confirm"));
	assert shown(slot) === "confirm*", shown(slot);
	assert instanceOf(slot) === confirm, "the same key keeps the instance";
	slot.activate({ name: "confirm", title: "Delete?" });
	assert instanceOf(slot) === confirm;
	assert confirm.configuration().title === "Delete?", confirm.configuration().title;
	assert created === "confirm;" && disposed === "", created + " / " + disposed;
	slot.dispose();
}

test "activate with another key disposes the old child and creates the new one" {
	const slot = makeSlot(dialog("confirm"));
	const confirm = instanceOf(slot);
	slot.activate(dialog("share"));
	assert shown(slot) === "share*", shown(slot);
	assert instanceOf(slot) !== confirm;
	assert disposed === "confirm;", disposed;
	assert created === "confirm;share;", created;
	slot.dispose();
	assert disposed === "confirm;share;", disposed;
}

test "dismiss reports whether a child was shown, as back does in Decompose" {
	const empty = makeSlot(null);
	assert !empty.dismiss(), "an empty slot has nothing to dismiss";
	assert shown(empty) === "none";
	empty.dispose();
	const slot = makeSlot(dialog("confirm"));
	assert slot.dismiss(), "a shown child is dismissed";
	assert shown(slot) === "none";
	assert !slot.dismiss(), "a dismissed slot has nothing left to dismiss";
	assert disposed === "confirm;", disposed;
	slot.dispose();
}

test "navigate applies a transformer to the current configuration" {
	const slot = makeSlot(null);
	slot.navigate((current: Dialog | null): Dialog | null => {
		assert current === null;
		return dialog("confirm");
	});
	assert shown(slot) === "confirm*", shown(slot);
	slot.navigate((current: Dialog | null): Dialog | null => {
		assert current !== null && (current as Dialog).name === "confirm";
		return null;
	});
	assert shown(slot) === "none" && disposed === "confirm;", disposed;
	slot.dispose();
}

test "a slot fails loudly on an empty key and changes nothing" {
	const slot = makeSlot(dialog("confirm"));
	const empty = failure((): void => { slot.activate(dialog("")); });
	assert empty === "navigation: empty child key", empty;
	assert shown(slot) === "confirm*", shown(slot);
	assert disposed === "", disposed;
	slot.dispose();
}

test "the owner of the slot disposes its child" {
	createRoot((dispose: Dispose): void => {
		makeSlot(dialog("confirm"));
		dispose();
	});
	assert disposed === "confirm;", disposed;
}
