import { Signal, accessor } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import {
	WebHistoryItem,
	WebKeySerializer,
	WebNavigation,
	WebNavigationError,
	WebNavigationNode,
	webNavigationNode,
} from "../../src/navigation/webNavigation";

function prefixed(prefix: string): WebKeySerializer<string> {
	return {
		encode: (value: string): string => prefix + value,
		decode: (text: string): Result<string, WebNavigationError> => {
			if (!text.startsWith(prefix)) { return Result.err(WebNavigationError.UndecodableKey); }
			return Result.ok(text.substring(prefix.length, text.length));
		},
	};
}

function keys(node: WebNavigationNode): string {
	let out = "";
	for (const item of node.history()) {
		out += item.key + (item.path === "" ? "" : "@" + item.path) + ";";
	}
	return out;
}

test "a navigation erases to serialized keys and applies only a fully decoded traversal" {
	const entries = new Signal<string[]>(["a"]);
	let allowed = true;
	const navigation: WebNavigation<string> = {
		serializer: prefixed("k:"),
		history: accessor((): WebHistoryItem<string>[] => {
			const items: WebHistoryItem<string>[] = [];
			for (const key of entries.get()) {
				items.push({ key, path: key, parameters: new Map<string, string>(), child: null });
			}
			return items;
		}),
		onBeforeNavigate: (): boolean => allowed,
		navigate: (history: string[]): void => { entries.set(history); },
	};
	const node = webNavigationNode<string>(navigation);
	let runs: int32 = 0;
	const stop = createEffect((): void => {
		node.history();
		runs += 1;
	});
	assert keys(node) === "k:a@a;", keys(node);
	assert node.navigate(["k:a", "k:b"]).ok;
	assert runs === 2, runs.toString();
	assert keys(node) === "k:a@a;k:b@b;", keys(node);
	const refused = node.navigate(["k:c", "c"]);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error === WebNavigationError.UndecodableKey; }
	assert keys(node) === "k:a@a;k:b@b;", "a refused traversal changes nothing: " + keys(node);
	assert node.onBeforeNavigate();
	allowed = false;
	assert !node.onBeforeNavigate();
	stop();
}
