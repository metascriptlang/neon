import { Accessor } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { createRoot } from "../../src/core/owner";
import { Dispose } from "../../src/core/types";
import { ChildStack, createChildStack } from "../../src/navigation/childStack";

struct Screen {
	name: string;
	detail: string;
}

interface ScreenInstance {
	name: string;
	active: Accessor<boolean>;
}

let created = "";
let disposed = "";

function screen(name: string): Screen {
	return { name, detail: "" };
}

function screenKey(screen: Screen): string {
	return screen.name;
}

function makeStack(names: string[]): ChildStack<Screen, ScreenInstance> {
	created = "";
	disposed = "";
	const initial: Screen[] = [];
	for (const name of names) { initial.push(screen(name)); }
	return createChildStack<Screen, ScreenInstance>(
		initial,
		screenKey,
		(configuration: Accessor<Screen>, active: Accessor<boolean>): ScreenInstance => {
			const name = configuration().name;
			created += name + ";";
			onCleanup((): void => { disposed += name + ";"; });
			return { name, active };
		},
	);
}

function names(stack: ChildStack<Screen, ScreenInstance>): string {
	let out = "";
	for (const child of stack.items()) {
		out += child.instance.name + (child.active() ? "*" : "") + ";";
	}
	return out;
}

function disposedAll(wanted: string[]): boolean {
	let count = 0;
	for (const name of wanted) {
		if (disposed.indexOf(name + ";") < 0) { return false; }
		count += name.length + 1;
	}
	return disposed.length === count;
}

function failure(run: () => void): string {
	try { run(); } catch (error) { return error.message; }
	return "";
}

test "push and pop move the active child to the top and dispose the popped owner" {
	const stack = makeStack(["list"]);
	const list = stack.active().instance;
	stack.push(screen("detail"));
	stack.push(screen("edit"));
	assert names(stack) === "list;detail;edit*;", names(stack);
	assert stack.backStack().length === 2;
	assert !list.active(), "a covered child is inactive";
	stack.pop();
	assert names(stack) === "list;detail*;", names(stack);
	assert disposed === "edit;", disposed;
	assert stack.items()[0].instance === list, "a kept child keeps its instance";
	assert created === "list;detail;edit;", created;
	stack.dispose();
	assert disposedAll(["edit", "detail", "list"]), disposed;
}

test "popTo keeps the children up to an index and disposes the rest" {
	const stack = makeStack(["a", "b", "c", "d"]);
	const b = stack.items()[1].instance;
	stack.popTo(1);
	assert names(stack) === "a;b*;", names(stack);
	assert disposedAll(["c", "d"]), disposed;
	assert stack.active().instance === b && b.active(), "b is the kept active child";
	stack.popTo(1);
	assert names(stack) === "a;b*;", "popTo the top changes nothing: " + names(stack);
	stack.dispose();
}

test "replaceCurrent swaps the top child and keeps the back stack" {
	const stack = makeStack(["list", "detail"]);
	const list = stack.items()[0].instance;
	stack.replaceCurrent(screen("edit"));
	assert names(stack) === "list;edit*;", names(stack);
	assert disposed === "detail;", disposed;
	assert stack.items()[0].instance === list;
	stack.dispose();
}

test "bringToFront moves a child already in the stack to the top with its instance" {
	const stack = makeStack(["a", "b", "c"]);
	const a = stack.items()[0].instance;
	stack.bringToFront(screen("a"));
	assert names(stack) === "b;c;a*;", names(stack);
	assert stack.active().instance === a, "the moved child is not recreated";
	assert disposed === "", disposed;
	stack.bringToFront(screen("d"));
	assert names(stack) === "b;c;a;d*;", names(stack);
	assert created === "a;b;c;d;", created;
	stack.dispose();
}

test "navigate applies a transformer to the configurations and updates kept children" {
	const stack = makeStack(["a", "b"]);
	const a = stack.items()[0].instance;
	stack.navigate((configurations: Screen[]): Screen[] => {
		assert configurations.length === 2 && configurations[1].name === "b";
		return [{ name: "a", detail: "edited" }, screen("x")];
	});
	assert names(stack) === "a;x*;", names(stack);
	assert stack.items()[0].instance === a;
	assert stack.items()[0].configuration().detail === "edited";
	assert stack.configurations()[0].detail === "edited";
	assert disposed === "b;", disposed;
	stack.dispose();
}

test "a stack fails loudly when it would be empty, pop has no back stack or popTo is out of range" {
	const stack = makeStack(["only"]);
	const pop = failure((): void => { stack.pop(); });
	assert pop === "child stack: pop needs a back stack, the stack has one item", pop;
	const above = failure((): void => { stack.popTo(1); });
	assert above === "child stack: popTo index 1 is outside a stack of 1", above;
	const below = failure((): void => { stack.popTo(-1); });
	assert below === "child stack: popTo index -1 is outside a stack of 1", below;
	const empty = failure((): void => {
		stack.navigate((configurations: Screen[]): Screen[] => []);
	});
	assert empty === "child stack: a stack must not be empty", empty;
	const duplicate = failure((): void => { stack.push(screen("only")); });
	assert duplicate === "duplicate child key: only", duplicate;
	const after = names(stack);
	assert after === "only*;", "a refused change leaves the stack as it was: " + after;
	assert disposed === "", disposed;
	const initial = failure((): void => { makeStack([]); });
	assert initial === "child stack: a stack must not be empty", initial;
	stack.dispose();
}

test "the owner of the stack disposes every child" {
	createRoot((dispose: Dispose): void => {
		makeStack(["a", "b"]);
		dispose();
	});
	assert disposedAll(["a", "b"]), disposed;
}
