import { createSignal } from "../../src/core/signal";
import { Host, HostNode, NeonNode } from "../../src/render/hostTypes";
import { MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { place } from "../../src/render/reconcile";
import { flush } from "../../src/core/runtime";
import { refreshComponent0, refreshBoundary0, refreshModule, refreshState, refreshReset } from "../../src/render/refresh";
import { DevNode, setDevDriver } from "../../src/devtools/driver";
import { devEvent, devEventLine } from "../../src/devtools/events";
import { ControlSession, handleRequest, closeSession } from "../../src/devtools/control";
import { jsonString } from "std/serialize/json/builder";

function session(): string[] {
	return [];
}

function ask(lines: string[], s: ControlSession, request: string): string {
	handleRequest(s, request);
	return lines.length > 0 ? lines[lines.length - 1] : "";
}

function leaf(tag: string, text: string, x: float32, y: float32, pressable: boolean): DevNode {
	return { tag, text, value: null, focused: false, pressable, x, y, w: 100.0, h: 40.0, children: [] };
}

function fakeTree(): DevNode {
	const field = leaf("textinput", "", 0.0, 100.0, false);
	field.value = "typed so far";
	return {
		tag: "view", text: "", value: null, focused: false, pressable: false, x: 0.0, y: 0.0, w: 300.0, h: 300.0,
		children: [leaf("text", "Counter", 0.0, 0.0, false), leaf("pressable", "+1", 0.0, 50.0, true), field],
	};
}

test "control: ping, parse errors and unknown methods answer as JSON-RPC 2.0" {
	setDevDriver(null);
	const lines = session();
	const s = new ControlSession((line: string): void => { lines.push(line); });
	assert ask(lines, s, `{"jsonrpc":"2.0","id":1,"method":"ping"}`) === `{"jsonrpc":"2.0","id":1,"result":{"protocol":1,"host":null}}`, "ping";
	assert ask(lines, s, `{"jsonrpc":"2.0","id":2,`).startsWith(`{"jsonrpc":"2.0","id":null,"error":{"code":-32700,`), "parse error";
	assert ask(lines, s, `{"jsonrpc":"2.0","id":"a","method":"nope"}`).includes(`"code":-32601,"message":"unknown method \\"nope\\"; known: ping, tree,`), "unknown method names the known ones";
	assert ask(lines, s, `[1]`).includes(`"code":-32600`), "a request that is not an object";
	assert ask(lines, s, `{"jsonrpc":"2.0","id":3,"method":"tree"}`).includes(`"code":-32000,"message":"no UI driver`), "tree without a driver fails loud";
	assert ask(lines, s, `{"jsonrpc":"2.0","id":4,"method":"eval","params":{"code":"1"}}`).includes(`"code":-32601,"message":"eval needs the compiler half`), "eval names what it waits on";
	const before = lines.length;
	handleRequest(s, `{"jsonrpc":"2.0","method":"ping"}`);
	handleRequest(s, `{"jsonrpc":"2.0","method":"nope"}`);
	assert lines.length === before, "a notification gets no reply, not even an error";
}

test "control: tree, press and type go through the registered driver" {
	const pressed: string[] = [];
	const typed: string[] = [];
	setDevDriver({
		host: "fake",
		tree: fakeTree,
		pressAt: (x: float32, y: float32): void => { pressed.push(`${x},${y}`); },
		type: (text: string): void => { typed.push(text); },
	});
	const lines = session();
	const s = new ControlSession((line: string): void => { lines.push(line); });
	const tree = ask(lines, s, `{"jsonrpc":"2.0","id":1,"method":"tree"}`);
	assert tree.includes(`{"id":"1","tag":"pressable","text":"+1","value":null,"focused":false,"pressable":true,"frame":[0,50,100,40],"children":[]}`), "tree gives each node a path id and its frame";
	assert tree.includes(`"value":"typed so far"`), "a field reports its value";
	assert ask(lines, s, `{"jsonrpc":"2.0","id":2,"method":"press","params":{"target":"1"}}`) === `{"jsonrpc":"2.0","id":2,"result":{"x":50,"y":70}}`, "press by id";
	ask(lines, s, `{"jsonrpc":"2.0","id":3,"method":"press","params":{"target":"text:Counter"}}`);
	assert pressed.join(" ") === "50,70 50,20", "press by text hits the centre of the node";
	assert ask(lines, s, `{"jsonrpc":"2.0","id":4,"method":"press","params":{"target":"9"}}`).includes(`"code":-32602,"message":"press: no node matches \\"9\\"`), "a missing target";
	assert ask(lines, s, `{"jsonrpc":"2.0","id":5,"method":"press","params":{"target":"1x"}}`).includes(`"code":-32602`), "a malformed id is not a prefix match";
	assert ask(lines, s, `{"jsonrpc":"2.0","id":6,"method":"press"}`).includes(`"code":-32602,"message":"params.target must be a string"`), "missing params";
	assert ask(lines, s, `{"jsonrpc":"2.0","id":7,"method":"type","params":{"text":"hé"}}`) === `{"jsonrpc":"2.0","id":7,"result":true}`, "type";
	assert typed.join("|") === "hé", "type delivers the text";
	setDevDriver(null);
}

test "control: subscribe streams dev events as notifications until the session closes" {
	const lines = session();
	const s = new ControlSession((line: string): void => { lines.push(line); });
	ask(lines, s, `{"jsonrpc":"2.0","id":1,"method":"subscribe"}`);
	ask(lines, s, `{"jsonrpc":"2.0","id":2,"method":"subscribe"}`);
	const before = lines.length;
	devEvent("probe", ["n"], [jsonString("x")]);
	assert lines.length === before + 1, "one notification per event, however often subscribe was called";
	const note = lines[lines.length - 1];
	assert note.startsWith(`{"jsonrpc":"2.0","method":"event","params":{"v":1,"t":`) && note.endsWith(`"event":"probe","n":"x"}}`), "the notification wraps the event line";
	closeSession(s);
	devEvent("probe", ["n"], [jsonString("y")]);
	assert lines.length === before + 1, "a closed session hears nothing";
}

test "control: an event line refuses keys without values" {
	assert devEventLine("e", ["a"], [jsonString("b")]).endsWith(`"event":"e","a":"b"}`), "envelope";
	let threw = "";
	try { devEvent("e", ["a", "b"], [jsonString("only one")]); } catch (e) { threw = e.message; }
	assert threw === "devEvent e: 2 keys for 1 values", "mismatch fails loud";
}

test "control: components lists mounted boundaries with their live kept state, and a remount is a refresh event" {
	refreshReset();
	let version = 1;
	let bump: () => void = (): void => {};
	const makeComp = (): () => NeonNode => {
		return (): NeonNode => {
			const [count, setCount] = createSignal(3);
			refreshState("count", count, setCount);
			bump = (): void => { setCount(count() + 1); };
			return (host: Host, parent: HostNode, before: HostNode | null): void => {
				place(host, parent, host.createText("v" + version.toString()), before);
			};
		};
	};
	const signature = (): string => "s" + version.toString();
	refreshComponent0("app.ms", "Counter", makeComp(), signature);
	const root: MockNode = mockNode("root");
	const dispose = render((host: Host, parent: HostNode, before: HostNode | null): void => {
		refreshBoundary0("app.ms", "Counter", makeComp(), signature)(host, parent, null);
	}, mockHost(), root as unknown as HostNode);
	bump();
	flush();

	const lines = session();
	const s = new ControlSession((line: string): void => { lines.push(line); });
	assert ask(lines, s, `{"jsonrpc":"2.0","id":1,"method":"components"}`) === `{"jsonrpc":"2.0","id":1,"result":[{"component":"app.ms#Counter","broken":false,"state":{"count":"4"}}]}`, "live value, not the initial one";

	ask(lines, s, `{"jsonrpc":"2.0","id":2,"method":"subscribe"}`);
	version = 2;
	refreshComponent0("app.ms", "Counter", makeComp(), signature);
	refreshModule("app.ms");
	flush();
	assert mockToString(root.children[0]) === "v2", "remounted";
	const note = lines[lines.length - 1];
	assert note.includes(`"event":"refresh","module":"app.ms","kept":0,"rebuilt":0,"remounted":1,"ms":`), `refresh event: ${note}`;
	closeSession(s);
	dispose();
	refreshReset();
}
