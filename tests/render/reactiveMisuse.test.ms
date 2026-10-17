import { createSignal, untrack, Accessor, Setter } from "../../src/core/signal";
import { createMemo } from "../../src/core/memo";
import { createEffect } from "../../src/core/effect";
import { Cleanup } from "../../src/core/types";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { HostNode, MockNode, mockNode, mockHost, render, fireEvent, mockToString } from "../../src/render/host";

interface CountProps {
	n: Accessor<int32>;
}

function mounted(view: NeonNode): MockNode {
	const root: MockNode = mockNode("root");
	render(view, mockHost(), root as unknown as HostNode);
	return root;
}

function Handler(props: CountProps): NeonNode {
	const [clicks, setClicks] = createSignal(0);
	const bump: (e: NeonEvent) => void = () => { setClicks(clicks() + 1); };
	return element(<button onPress={bump}>{clicks().toString()}/{props.n().toString()}</button>);
}

function OneTime(props: CountProps): NeonNode {
	const first = untrack(() => props.n());
	return element(<p>{first.toString()}:{props.n().toString()}</p>);
}

function Derived(props: CountProps): NeonNode {
	const doubled = createMemo<int32>((): int32 => props.n() * 2);
	return element(<p>{doubled().toString()}</p>);
}

function EffectPhase(props: CountProps): NeonNode {
	const [seen, setSeen] = createSignal<int32>(0);
	createEffect<int32>(
		(prev: int32 | null): int32 => props.n(),
		(value: int32, prev: int32 | null): Cleanup | null => { setSeen(value); return null; },
	);
	return element(<p>{seen().toString()}</p>);
}

function OwnedWrite(props: CountProps): NeonNode {
	const [runs, setRuns] = createSignal(0, { ownedWrite: true });
	const echoed = createMemo<int32>((): int32 => { setRuns(1); return props.n(); });
	return element(<p>{echoed().toString()}/{runs().toString()}</p>);
}

const [moduleRuns, setModuleRuns] = createSignal(0, { ownedWrite: true });
const [, setShadowed] = createSignal(0);

function ModuleOwnedWrite(props: CountProps): NeonNode {
	const echoed = createMemo<int32>((): int32 => { setModuleRuns(2); return props.n(); });
	return element(<p>{echoed().toString()}/{moduleRuns().toString()}</p>);
}

interface ShadowProps {
	n: Accessor<int32>;
	setShadowed: Setter<int32>;
}

function Shadowing(props: ShadowProps): NeonNode {
	const setShadowed: Setter<int32> = props.setShadowed;
	const echoed = createMemo<int32>((): int32 => { setShadowed(props.n()); return props.n(); });
	return element(<p>{echoed().toString()}</p>);
}

test "an event handler writes a signal and a one-time read stays at its first value" {
	const [n, setN] = createSignal(1);
	const root = mounted(element(<Handler n={n()} />));
	assert mockToString(root.children[0]) === "<button>0/1</button>", "initial: " + mockToString(root);
	fireEvent(root.children[0], "onPress");
	assert mockToString(root.children[0]) === "<button>1/1</button>", "after press: " + mockToString(root);
	setN(4);
	assert mockToString(root.children[0]) === "<button>1/4</button>", "after set: " + mockToString(root);

	const once = mounted(element(<OneTime n={n()} />));
	assert mockToString(once.children[0]) === "<p>4:4</p>", "initial: " + mockToString(once);
	setN(7);
	assert mockToString(once.children[0]) === "<p>4:7</p>", "the untrack read keeps its first value: " + mockToString(once);
}

test "a memo reads and a signal with ownedWrite is written inside a compute" {
	const [n, setN] = createSignal(2);
	const derived = mounted(element(<Derived n={n()} />));
	assert mockToString(derived.children[0]) === "<p>4</p>", "initial: " + mockToString(derived);
	setN(5);
	assert mockToString(derived.children[0]) === "<p>10</p>", "after set: " + mockToString(derived);

	const owned = mounted(element(<OwnedWrite n={n()} />));
	assert mockToString(owned.children[0]) === "<p>5/1</p>", "initial: " + mockToString(owned);
}

test "an effect's second function writes a signal" {
	const [n, setN] = createSignal(3);
	const root = mounted(element(<EffectPhase n={n()} />));
	assert mockToString(root.children[0]) === "<p>3</p>", "initial: " + mockToString(root);
	setN(6);
	assert mockToString(root.children[0]) === "<p>6</p>", "after set: " + mockToString(root);
}

test "a module-level signal with ownedWrite, and a local name shadowing a module-level setter, are written inside a compute" {
	const [n, setN] = createSignal(3);
	const owned = mounted(element(<ModuleOwnedWrite n={n()} />));
	assert mockToString(owned.children[0]) === "<p>3/2</p>", "initial: " + mockToString(owned);

	const [given, setGiven] = createSignal(0, { ownedWrite: true });
	const shadow = mounted(element(<Shadowing n={n()} setShadowed={setGiven} />));
	assert mockToString(shadow.children[0]) === "<p>3</p>", "initial: " + mockToString(shadow);
	assert given() === 3, "the local setter wrote: " + given().toString();
}
