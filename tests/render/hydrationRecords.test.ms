import { NeonNode } from "../../src/render/node";
import { hydrate, mockHost, mockNode, HostNode, Host } from "../../src/render/host";
import {
	hasRecord, hasError, takeRecord, takeError, putRecord, putError, clearRecords, scriptLiteral,
} from "../../src/render/hydrationRecords";

interface Note {
	text: string;
	n: int32;
}

interface Basket {
	items: Note[];
	total: float64;
}

function whileHydrating(body: () => void): void {
	const root = mockNode("root");
	const mount: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => { body(); };
	const dispose = hydrate(mount, mockHost(), root as unknown as HostNode);
	dispose();
}

function failure(read: () => void): string {
	try {
		read();
	} catch (e) {
		return (e as Error).message;
	}
	return "";
}

test "a record is read while hydrating and reading it consumes it" {
	clearRecords();
	putRecord("t0", JSON.stringify<Note>({ text: "hi", n: 7 }));
	assert !hasRecord("t0"), "a record is not visible before hydrate";
	whileHydrating((): void => {
		assert hasRecord("t0"), "the record is visible while hydrating";
		assert !hasRecord("t1"), "an id the server did not write has no record";
		const note = takeRecord<Note>("t0");
		assert note.text === "hi" && note.n === 7, note.text;
		assert !hasRecord("t0"), "reading consumed the record";
		assert failure((): void => { takeRecord<Note>("t0"); }).indexOf("t0") >= 0, "a second read names its id";
	});
	clearRecords();
}

test "a record outside hydrate is not read, and the refusal names its id" {
	clearRecords();
	putRecord("o1", JSON.stringify<Note>({ text: "late", n: 1 }));
	assert !hasRecord("o1");
	assert failure((): void => { takeRecord<Note>("o1"); }).indexOf("o1") >= 0, "the throw names the id";
	whileHydrating((): void => { assert hasRecord("o1"), "the record was not consumed by the refused read"; });
	clearRecords();
}

test "a record that does not decode throws naming its id" {
	clearRecords();
	putRecord("bad.1", "{\"text\":5}");
	whileHydrating((): void => {
		assert failure((): void => { takeRecord<Note>("bad.1"); }).indexOf("bad.1") >= 0, "the throw names the id";
	});
	clearRecords();
}

test "an error record is read apart from a value record" {
	clearRecords();
	putError("e0", "the server failed");
	putRecord("v0", JSON.stringify<Basket>({ items: [{ text: "a", n: 1 }, { text: "b", n: 2 }], total: 2.5 }));
	whileHydrating((): void => {
		assert hasError("e0") && !hasRecord("e0"), "e0 is an error record only";
		assert hasRecord("v0") && !hasError("v0"), "v0 is a value record only";
		assert takeError("e0") === "the server failed";
		assert !hasError("e0"), "reading consumed the error";
		const basket = takeRecord<Basket>("v0");
		assert basket.items.length === 2 && basket.items[1].text === "b" && basket.total === 2.5, "the array and number fields came back";
		assert failure((): void => { takeError("v0"); }).indexOf("v0") >= 0, "an error read of a value record names its id";
	});
	clearRecords();
}

const awkward: Note = { text: "a</script><!--\"q\"\\ \u2028 \u2029 é 漢 \n\t", n: -3 };

test "a record with script-breaking and non-ASCII text decodes to the value it was written from" {
	clearRecords();
	putRecord("w0", JSON.stringify<Note>(awkward));
	whileHydrating((): void => {
		const back = takeRecord<Note>("w0");
		assert back.text === awkward.text && back.n === awkward.n, back.text;
	});
	clearRecords();
}

test "scriptLiteral escapes what a script string cannot hold" {
	const json = JSON.stringify<Note>(awkward);
	const literal = scriptLiteral(json);
	assert literal.indexOf("</") < 0 && literal.indexOf("<!--") < 0, literal;
	assert literal.indexOf("\u2028") < 0 && literal.indexOf("\u2029") < 0, "the line separators are escaped";
	assert literal.indexOf("\\u003c/script>") >= 0, literal;
	assert literal.indexOf("\\u2028") >= 0 && literal.indexOf("\\u2029") >= 0, literal;
	assert scriptLiteral("a\\b\"c") === "a\\\\b\\\"c", scriptLiteral("a\\b\"c");
}

test "scriptLiteral keeps a message with a line break or a control character on one line" {
	assert scriptLiteral("one\ntwo\r") === "one\\u000atwo\\u000d", scriptLiteral("one\ntwo\r");
	assert scriptLiteral("a\tb\u0001") === "a\\u0009b\\u0001", scriptLiteral("a\tb\u0001");
}
