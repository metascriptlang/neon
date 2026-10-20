// The TextInputs of examples/windowsNative/ionInput.ms in a macOS Ion window: NSTextField over the field editor,
// a secure cell for secureTextEntry, an NSTextView for multiline.
//   msc build examples/macosNative/ionInput.ms --output=out/macosIonInput
//   out/macosIonInput            opens the window and logs each change, focus, blur, submit and selection
//   out/macosIonInput --check    clicks and types through AppKit events, composes through the field editor's
//                                NSTextInputClient, and exits 0 when every expectation holds

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, TextInput, TextSelection } from "../../src/components/primitives";
import {
	harnessIsCheck, harnessExpect, harnessExpectCount, harnessSample, harnessPostKeys, harnessClick, harnessCompose, harnessCommit,
	harnessFocusedText, harnessFocusedAutoCorrect, harnessDefaultAutoCorrect,
	harnessFocusedFieldEditor,
} from "./harness.h";
import { exit } from "std/process";

when (macos) {
	@compile("./harness.m", "-fobjc-arc");
}

const styles = createStyles({
	base: { width: 480, height: 320, backgroundColor: "#101820" },
	name: { position: "absolute", left: 20, top: 20, width: 300, backgroundColor: "#ffffff", color: "#101820", fontSize: 20, padding: 6 },
	upper: { position: "absolute", left: 20, top: 80, width: 300, backgroundColor: "#ffffff", color: "#101820", fontSize: 20, padding: 6 },
	limited: { position: "absolute", left: 20, top: 140, width: 300, backgroundColor: "#ffffff", color: "#101820", fontSize: 20, padding: 6 },
	notes: { position: "absolute", left: 20, top: 200, width: 300, backgroundColor: "#fff3c4", color: "#101820", fontSize: 20, padding: 6 },
	secret: { position: "absolute", left: 340, top: 20, width: 120, backgroundColor: "#ffffff", color: "#c0392b", fontSize: 20, padding: 6 },
});

const changes: Map<string, string[]> = new Map();
const focuses: string[] = [];
const blurs: string[] = [];
const submits: string[] = [];
let lastSelection = "";
let notesHeight: number = 0;
let notesFirstHeight: number = 0;
const [upper, setUpper] = createSignal("");
const [nameCorrection, setNameCorrection] = createSignal(false);
const [notesCorrection, setNotesCorrection] = createSignal(false);

function changed(name: string): (t: string) => void {
	return (t: string): void => {
		if (!changes.has(name)) { changes.set(name, []); }
		(changes.get(name) as string[]).push(t);
		console.log(`change ${name} "${t}"`);
	};
}

function seen(list: string[], name: string, what: string): (e: NeonEvent) => void {
	return (e: NeonEvent): void => {
		list.push(name);
		console.log(`${what} ${name} "${e.value}"`);
	};
}

function App(): NeonNode {
	return <View style={styles.base}>
		<TextInput style={styles.name} autoCorrect={nameCorrection()} placeholder="Name" placeholderTextColor="#2e86de" onChangeText={changed("name")}
			onFocus={seen(focuses, "name", "focus")} onBlur={seen(blurs, "name", "blur")} onSubmitEditing={seen(submits, "name", "submit")}
			onSelectionChange={(s: TextSelection): void => { lastSelection = `${s.start},${s.end}`; }} />
		<TextInput style={styles.upper} autoCorrect={true} value={upper()} onChangeText={(t: string): void => {
			changed("upper")(t);
			setUpper(t.toUpperCase());
		}} />
		<TextInput style={styles.limited} maxLength={3} onChangeText={changed("limited")} />
		<TextInput style={styles.notes} multiline={true} autoCorrect={notesCorrection()} onChangeText={changed("notes")} onLayout={(e: NeonEvent): void => {
			notesHeight = e.height;
			if (notesFirstHeight === 0) { notesFirstHeight = e.height; }
		}} />
		<TextInput style={styles.secret} secureTextEntry={true} autoCorrect={true} onChangeText={changed("secret")} />
	</View>;
}

const TITLE = "Neon text input on Ion";
const check = harnessIsCheck() !== 0;
let failures = 0;
let composedFrom: number = 0;

function last(name: string): string {
	if (!changes.has(name)) { return "<none>"; }
	const list = changes.get(name) as string[];
	return list.length === 0 ? "<none>" : list[list.length - 1];
}

function count(name: string): number {
	return changes.has(name) ? (changes.get(name) as string[]).length : 0;
}

function expect(what: string, ok: boolean, detail: string): void {
	console.log(`${ok ? "ok  " : "FAIL"} ${what}: ${detail}`);
	if (!ok) { failures += 1; }
}

function click(x: number, y: number): void {
	harnessClick(TITLE, x as int32, y as int32);
}

function type(keys: string): void {
	if (keys.length === 0) { return; }
	harnessPostKeys(TITLE, keys.substring(0, 1));
	setTimeout((): void => { type(keys.substring(1)); }, 60);
}

const steps: (() => void)[] = [];

function run(at: number): void {
	if (at >= steps.length) {
		console.log(`failures ${failures}`);
		exit(failures);
		return;
	}
	steps[at]();
	setTimeout((): void => { run(at + 1); }, 600);
}

steps.push((): void => {
	harnessExpect("base", 470, 310, 16, 24, 32);
	harnessExpect("name background", 24, 24, 255, 255, 255);
	harnessExpectCount("placeholder drawn", 26, 24, 290, 30, 46, 134, 222, 40, 30, 100000);
	failures += harnessSample(TITLE);
	click(300.0, 35.0);
	type("hi");
});
steps.push((): void => {
	expect("focus reached name", focuses.length === 1 && focuses[0] === "name", focuses.join(","));
	expect("typed through Ion", last("name") === "hi", last("name"));
	expect("one change per key", count("name") === 2, `${count("name")}`);
	expect("selection after typing", lastSelection === "2,2", lastSelection);
	expect("the field editor has the focus", harnessFocusedText(TITLE) === 1, `${harnessFocusedText(TITLE)}`);
	harnessExpectCount("placeholder gone", 26, 24, 290, 30, 46, 134, 222, 40, 0, 0);
	harnessExpectCount("typed text drawn", 26, 24, 290, 30, 16, 24, 32, 60, 30, 100000);
	failures += harnessSample(TITLE);
	type("\b");
});
steps.push((): void => {
	expect("backspace", last("name") === "h", last("name"));
	type("\n");
});
steps.push((): void => {
	expect("enter submits", submits.length === 1, submits.join(","));
	expect("submit blurs a single-line input", blurs.length === 1, blurs.join(","));
	expect("no text view focused after blur", harnessFocusedText(TITLE) === 0, `${harnessFocusedText(TITLE)}`);
	click(300.0, 95.0);
	type("ab");
});
steps.push((): void => {
	expect("controlled value uppercased", upper() === "AB", upper());
	type("c");
});
steps.push((): void => {
	expect("the input held the controlled value", last("upper") === "ABc", last("upper"));
	click(300.0, 155.0);
	type("abcd");
});
steps.push((): void => {
	expect("maxLength stops at 3", last("limited") === "abc" && count("limited") === 3, `${last("limited")} x${count("limited")}`);
	click(300.0, 215.0);
	type("a\nb");
});
steps.push((): void => {
	expect("enter is a newline in a multiline input", last("notes") === "a\nb", JSON.stringify(last("notes")));
	expect("multiline grows", notesHeight > notesFirstHeight, `${notesFirstHeight} -> ${notesHeight}`);
	click(300.0, 35.0);
});
steps.push((): void => {
	expect("the click moved the focus to name", focuses.length === 2 && focuses[1] === "name", focuses.join(","));
	const before = count("name");
	harnessCompose(TITLE, "vie");
	harnessCompose(TITLE, "việ");
	expect("composition reports no change", count("name") === before, `${count("name")}`);
	composedFrom = before;
});
steps.push((): void => {
	harnessExpectCount("composition drawn", 26, 24, 290, 30, 16, 24, 32, 60, 60, 100000);
	failures += harnessSample(TITLE);
	const before = composedFrom;
	harnessCommit(TITLE, "việt");
	expect("commit reports one change", count("name") === before + 1 && last("name") === "hviệt", `${last("name")} x${count("name") - before}`);
	expect("the composition stayed out of notes", last("notes") === "a\nb", JSON.stringify(last("notes")));
});
steps.push((): void => {
	click(440.0, 35.0);
	type("ab");
});
steps.push((): void => {
	expect("secure entry still reports its text", last("secret") === "ab", last("secret"));
	harnessExpectCount("bullets drawn", 346, 24, 110, 30, 192, 57, 43, 60, 10, 100000);
	failures += harnessSample(TITLE);
});

function expectCorrection(what: string, enabled: boolean): void {
	const flag = harnessFocusedAutoCorrect(TITLE);
	expect(what, flag === (enabled ? 1 : 0), `${flag}`);
}

function expectFieldEditor(what: string, shared: boolean): void {
	const flag = harnessFocusedFieldEditor(TITLE);
	expect(what, flag === (shared ? 1 : 0), `${flag}`);
}

steps.push((): void => {
	expectCorrection("secure ignores autoCorrect=true", false);
	click(300.0, 35.0);
});
steps.push((): void => {
	expectCorrection("single-line autoCorrect=false", false);
	expectFieldEditor("name uses window field editor", true);
	setNameCorrection(true);
});
steps.push((): void => {
	expectCorrection("focused single-line false to true", true);
	expect("correction update preserves IME commit", last("name") === "hviệt", last("name"));
	setNameCorrection(false);
});
steps.push((): void => {
	expectCorrection("focused single-line true to false", false);
	click(300.0, 95.0);
});
steps.push((): void => {
	expectCorrection("opposite field autoCorrect=true", true);
	expectFieldEditor("upper reuses window field editor", true);
	click(300.0, 35.0);
});
steps.push((): void => {
	expectCorrection("refocus restores false after true", false);
	expectFieldEditor("name reuses window field editor", true);
	click(300.0, 155.0);
});
steps.push((): void => {
	expectCorrection("omitted autoCorrect keeps native default", harnessDefaultAutoCorrect() === 1);
	click(300.0, 215.0);
});
steps.push((): void => {
	expectCorrection("multiline autoCorrect=false", false);
	expectFieldEditor("multiline owns text view", false);
	setNotesCorrection(true);
});
steps.push((): void => {
	expectCorrection("focused multiline false to true", true);
	expect("correction update preserves multiline", last("notes") === "a\nb", JSON.stringify(last("notes")));
	setNotesCorrection(false);
});
steps.push((): void => {
	expectCorrection("focused multiline true to false", false);
	click(300.0, 95.0);
});
steps.push((): void => {
	expectCorrection("single-line true after multiline false", true);
	click(300.0, 215.0);
});
steps.push((): void => {
	expectCorrection("multiline refocus preserves false", false);
	setNotesCorrection(true);
	click(300.0, 35.0);
});
steps.push((): void => {
	expectCorrection("single-line false while multiline true", false);
	click(300.0, 215.0);
});
steps.push((): void => {
	expectCorrection("multiline refocus preserves true", true);
	click(440.0, 35.0);
});
steps.push((): void => {
	expectCorrection("secure stays disabled after editor reuse", false);
});

const options = nativeWindowOptions(TITLE, 480, 320);
options.topmost = check;
exit(runNativeWindow(options, App, check ? (): void => {
	setTimeout((): void => { run(0); }, 700);
} : null));
