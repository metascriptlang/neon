import { NeonNode } from "../../src/render/node";
import { Host, HostNode } from "../../src/render/hostTypes";
import { place } from "../../src/render/reconcile";
import { createOwner } from "../../src/core/runtime";
import { NotReadyError } from "../../src/core/types";
import { Hole, ServerContext, ServerMarks, serverContext } from "../../src/core/serverContext";
import { renderToString, renderToStream } from "../../src/render/ssr";

// A part is "t:" static text, "h:" a text spot whose value arrived late, or "e" an element.
function mountParts(host: Host, parent: HostNode, marks: ServerMarks | null, parts: string[], holes: Hole[]): HostNode | null {
	let first: HostNode | null = null;
	for (const part of parts) {
		let node: HostNode;
		if (part === "e") {
			node = host.createElement("i");
			place(host, node, host.createText("x"), null);
		} else if (part.startsWith("h:") && marks !== null) {
			node = host.createText("");
			const hole = new Hole(holes.length.toString(), (): string => part.slice(2), null, createOwner());
			hole.value = part.slice(2);
			(marks as ServerMarks).pend(node, hole);
			holes.push(hole);
			const open = (serverContext() as ServerContext).holes;
			if (open !== null) { (open as Hole[]).push(hole); }
		} else {
			node = host.createText(part.slice(2));
		}
		place(host, parent, node, null);
		if (first === null) { first = node; }
	}
	return first;
}

function wrapped(host: Host, parent: HostNode, tag: string, marks: ServerMarks | null, parts: string[], holes: Hole[]): HostNode | null {
	if (tag === "") { return mountParts(host, parent, marks, parts, holes); }
	const outer = host.createElement(tag);
	mountParts(host, outer, marks, parts, holes);
	place(host, parent, outer, null);
	return outer;
}

function sync(tag: string, parts: string[]): string {
	const view: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		wrapped(host, parent, tag, null, parts, []);
	};
	return renderToString(view);
}

async function viaHoles(tag: string, parts: string[]): Promise<string> {
	let filled = "";
	const view: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const ctx = serverContext() as ServerContext;
		const marks = ctx.marks as ServerMarks;
		const holes: Hole[] = [];
		const first = wrapped(host, parent, tag, marks, parts, holes) as HostNode;
		filled = marks.fill(marks.take(first), marks.kept(marks.take(first), holes));
	};
	await renderToStream(view);
	return filled;
}

async function differs(tag: string, parts: string[]): Promise<string> {
	const held = await viaHoles(tag, parts);
	const written = sync(tag, parts);
	return held === written ? "" : tag + " " + parts.join("|") + ": [" + held + "] against [" + written + "]";
}

async function allSame(tag: string, cases: string[][]): Promise<string> {
	let bad = "";
	for (const parts of cases) { bad += await differs(tag, parts) + "\n"; }
	return bad.trim();
}

test "a late text spot fills to the bytes a text written at once has, in a marked parent" {
	const bad = await allSame("", [
		["h:v"], ["h:"], ["t:a", "h:v"], ["t:a", "h:"], ["h:v", "t:b"], ["h:", "t:b"],
		["t:", "h:v", "t:b"], ["h:v", "e", "t:b"], ["h:a<b&c"],
	]);
	assert bad === "", bad;
}

test "a late text spot after a late text spot takes its separator from the first one's text" {
	const bad = await allSame("", [
		["h:v", "h:w"], ["h:", "h:w"], ["h:v", "h:"], ["h:", "h:"],
		["t:a", "h:v", "h:w", "t:b"], ["t:a", "h:", "h:w", "h:", "t:b"], ["h:v", "h:w", "h:x", "t:b"],
	]);
	assert bad === "", bad;
}

test "a late text spot inside an element, and inside a parent that marks no text, fills the same" {
	const inP = await allSame("p", [["t:a", "h:v", "t:b"], ["h:", "h:w", "e"]]);
	const inTitle = await allSame("title", [["t:a", "h:v", "t:b"], ["h:", "h:w"]]);
	assert inP === "" && inTitle === "", inP + inTitle;
}

test "a late text spot is refused where the writer cannot fill it: raw text, the head, the overlay" {
	const refused = async (parent: (host: Host, marks: ServerMarks) => HostNode): Promise<boolean> => {
		let thrown = false;
		const view: NeonNode = (host: Host, root: HostNode, before: HostNode | null): void => {
			const marks = (serverContext() as ServerContext).marks as ServerMarks;
			const node = host.createText("");
			const source = createOwner();
			marks.pend(node, new Hole("0", (): string => "", null, source));
			try {
				place(host, parent(host, marks), node, null);
			} catch (e) {
				thrown = e instanceof NotReadyError && (e as NotReadyError).source === source;
			}
		};
		await renderToStream(view);
		return thrown;
	};
	assert await refused((host: Host, marks: ServerMarks): HostNode => host.createElement("script")), "script";
	assert await refused((host: Host, marks: ServerMarks): HostNode => host.createElement("style")), "style";
	assert await refused((host: Host, marks: ServerMarks): HostNode => (host.headRoot as (n: HostNode) => HostNode)(host.createElement("view"))), "head";
	assert await refused((host: Host, marks: ServerMarks): HostNode => (host.overlayRoot as (n: HostNode) => HostNode)(host.createElement("view"))), "overlay";
}

test "a holder beside a late text spot is refused, because its first text would guess the separator" {
	let first = "none";
	let second = "none";
	const view: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const marks = (serverContext() as ServerContext).marks as ServerMarks;
		try { marks.holder(parent); first = "held"; } catch (e) { first = "refused"; }
		const node = host.createText("");
		const hole = new Hole("0", (): string => "", null, createOwner());
		hole.value = "";
		marks.pend(node, hole);
		((serverContext() as ServerContext).holes as Hole[]).push(hole);
		place(host, parent, node, null);
		try { marks.holder(parent); second = "held"; } catch (e) { second = e instanceof NotReadyError ? "refused" : "other"; }
	};
	await renderToStream(view);
	assert first === "held" && second === "refused", first + " " + second;
}
