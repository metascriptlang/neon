import { NeonNode, el, dynText, attr, evt } from "../../src/render/node";
import { Host, HostNode } from "../../src/render/hostTypes";
import { NeonEvent } from "../../src/render/event";
import { createSignal } from "../../src/core/signal";
import { latest } from "../../src/core/runtime";
import { createAsyncMemo } from "../../src/render/hydrateMemo";

export interface Note {
	text: string;
	n: int32;
}

export function asyncPage(load: (n: int32) => Promise<Note>): NeonNode {
	const [page, setPage] = createSignal<int32>(1);
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: Note | null): Promise<Note> => load(page()));
		el("p", [attr("id", "note")], [], dynText((): string => latest((): string => data().text + " " + data().n.toString())))(host, parent, before);
		el("button", [attr("id", "next")], [evt("click", (e: NeonEvent): void => { setPage(page() + 1); })], dynText((): string => "next"))(host, parent, before);
	};
}
