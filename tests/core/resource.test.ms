import { createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { createResource, ResourceState } from "../../src/core/resource";
import { sleepAsync } from "std/core/promise";

enum LoadError {
	NotFound,
}

async function lookup(id: int32): Promise<Result<string, LoadError>> {
	await sleepAsync(30);
	if (id < 0) { return Result.err(LoadError.NotFound); }
	return Result.ok("item " + id.toString());
}

async function slowThenFast(id: int32): Promise<Result<string, LoadError>> {
	await sleepAsync(id === 1 ? 150 : 20);
	return Result.ok("v" + id.toString());
}

test "a resource goes pending, then ready with its value, then refreshing while keeping it" {
	const [id, setId] = createSignal<int32>(1);
	const [log, setLog] = createSignal("");
	createRoot((): void => {
		const [item, actions] = createResource(id, lookup);
		setLog(`${actions.state().toString()} ${actions.loading()} ${item() === null};`);
		const report = (): void => {
			const v = item();
			setLog(log() + `${actions.state().toString()} ${actions.loading()} ${v === null ? "-" : v as string};`);
		};
		setTimeout(report, 80);
		setTimeout((): void => { setId(2); report(); }, 100);
		setTimeout(report, 200);
	});
	await sleepAsync(300);
	assert log() === "Pending true true;Ready false item 1;Refreshing true item 1;Ready false item 2;", "states: " + log();
}

test "an error lands in error() instead of throwing, and a later success clears it" {
	const [id, setId] = createSignal<int32>(-1);
	const [log, setLog] = createSignal("");
	createRoot((): void => {
		const [item, actions] = createResource(id, lookup);
		const report = (): void => {
			const e = actions.error();
			setLog(log() + `${actions.state().toString()} ${e === null ? "ok" : "err"} ${item() === null ? "-" : item() as string};`);
		};
		setTimeout(report, 80);
		setTimeout((): void => { setId(3); }, 100);
		setTimeout(report, 200);
	});
	await sleepAsync(300);
	assert log() === "Errored err -;Ready ok item 3;", "states: " + log();
}

test "a stale response never overwrites a newer one" {
	const [id, setId] = createSignal<int32>(1);
	const [log, setLog] = createSignal("");
	createRoot((): void => {
		const [item, actions] = createResource(id, slowThenFast);
		setTimeout((): void => { setId(2); }, 10);
		setTimeout((): void => { setLog(item() === null ? "-" : item() as string); }, 250);
	});
	await sleepAsync(300);
	assert log() === "v2", "latest request wins: " + log();
}

test "refetch reloads the same source and mutate writes the value locally" {
	const [count, setCount] = createSignal<int32>(0);
	const [log, setLog] = createSignal("");
	createRoot((): void => {
		const [item, actions] = createResource((): int32 => 5, (id: int32): Promise<Result<string, LoadError>> => {
			setCount(count() + 1);
			return lookup(id);
		});
		setTimeout((): void => { actions.mutate("local"); setLog(item() as string); actions.refetch(); }, 60);
		setTimeout((): void => { setLog(log() + " " + (item() as string)); }, 150);
	});
	await sleepAsync(250);
	assert log() === "local item 5" && count() === 2, "mutate then refetch: " + log() + " count " + count().toString();
}
