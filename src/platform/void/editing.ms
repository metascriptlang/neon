// Flutter's editing model (services/text_input.dart TextEditingValue, TextRange):
// a composing range of -1..-1 means no IME composition is in progress.

export interface TextRange {
	start: number;
	end: number;
}

export interface TextEditingValue {
	text: string;
	selection: TextRange;
	composing: TextRange;
}

export function textRange(start: number, end: number): TextRange {
	return { start, end };
}

export function noRange(): TextRange {
	return { start: -1, end: -1 };
}

export function isEmptyRange(r: TextRange): boolean {
	return r.start < 0 || r.start === r.end;
}

export function editingValue(text: string): TextEditingValue {
	return { text, selection: textRange(text.length, text.length), composing: noRange() };
}

function replaced(v: TextEditingValue, r: TextRange, s: string): string {
	return v.text.substring(0, r.start) + s + v.text.substring(r.end, v.text.length);
}

function target(v: TextEditingValue): TextRange {
	return isEmptyRange(v.composing) ? v.selection : v.composing;
}

export function commitText(v: TextEditingValue, s: string): TextEditingValue {
	const r = target(v);
	const caret = r.start + s.length;
	return { text: replaced(v, r, s), selection: textRange(caret, caret), composing: noRange() };
}

export function composeText(v: TextEditingValue, s: string, cursor: number): TextEditingValue {
	const r = target(v);
	const caret = r.start + cursor;
	const composing = s.length === 0 ? noRange() : textRange(r.start, r.start + s.length);
	return { text: replaced(v, r, s), selection: textRange(caret, caret), composing };
}

export function deleteBackward(v: TextEditingValue): TextEditingValue {
	if (!isEmptyRange(v.composing)) { return v; }
	const s = v.selection;
	if (s.start !== s.end) { return commitText(v, ""); }
	if (s.start <= 0) { return v; }
	return commitText({ text: v.text, selection: textRange(s.start - 1, s.start), composing: noRange() }, "");
}

export function deleteForward(v: TextEditingValue): TextEditingValue {
	if (!isEmptyRange(v.composing)) { return v; }
	const s = v.selection;
	if (s.start !== s.end) { return commitText(v, ""); }
	if (s.end >= v.text.length) { return v; }
	return commitText({ text: v.text, selection: textRange(s.start, s.start + 1), composing: noRange() }, "");
}

export function moveCaret(v: TextEditingValue, to: number): TextEditingValue {
	if (!isEmptyRange(v.composing)) { return v; }
	const c = to < 0 ? 0 : (to > v.text.length ? v.text.length : to);
	return { text: v.text, selection: textRange(c, c), composing: noRange() };
}
