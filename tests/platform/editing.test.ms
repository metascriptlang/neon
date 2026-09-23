import {
	TextEditingValue, editingValue, textRange, isEmptyRange,
	commitText, composeText, deleteBackward, deleteForward, moveCaret,
} from "../../src/platform/void/editing";

function show(v: TextEditingValue): string {
	return `${v.text}|${v.selection.start}-${v.selection.end}|${v.composing.start}-${v.composing.end}`;
}

test "committed text lands at the caret and moves it" {
	let v = editingValue("ab");
	v = moveCaret(v, 1);
	v = commitText(v, "X");
	assert show(v) === "aXb|2-2|-1--1", show(v);
}

test "a Telex word composes in place and commits once" {
	let v = editingValue("chào ");
	for (const step of ["v", "vi", "vie", "viê", "viêt", "việt"]) {
		v = composeText(v, step, step.length);
	}
	assert show(v) === "chào việt|9-9|5-9", "composing covers the preedit: " + show(v);
	v = composeText(v, "", 0);
	v = commitText(v, "việt");
	assert show(v) === "chào việt|9-9|-1--1", "commit replaces the composition: " + show(v);
}

test "a preedit cursor inside the composition places the caret there" {
	const v = composeText(editingValue("x"), "abc", 1);
	assert show(v) === "xabc|2-2|1-4", show(v);
}

test "commit replaces a live composition instead of appending" {
	let v = composeText(editingValue(""), "ne", 2);
	v = commitText(v, "né");
	assert show(v) === "né|2-2|-1--1", show(v);
}

test "backspace and delete edit around the caret, and wait during composition" {
	let v = moveCaret(editingValue("abcd"), 2);
	v = deleteBackward(v);
	assert show(v) === "acd|1-1|-1--1", "backspace: " + show(v);
	v = deleteForward(v);
	assert show(v) === "ad|1-1|-1--1", "delete: " + show(v);
	assert show(deleteBackward(moveCaret(v, 0))) === "ad|0-0|-1--1", "backspace at start is a no-op";
	const composing = composeText(v, "xy", 2);
	assert show(deleteBackward(composing)) === show(composing), "the IME owns backspace while composing";
}

test "moveCaret clamps to the text" {
	assert show(moveCaret(editingValue("ab"), 9)) === "ab|2-2|-1--1", "past the end";
	assert show(moveCaret(editingValue("ab"), -3)) === "ab|0-0|-1--1", "before the start";
	assert isEmptyRange(textRange(3, 3)), "a collapsed range is empty";
}
