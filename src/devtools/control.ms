import { JsonValue, JsonKind, parseJson } from "std/serialize/json";
import { jsonObject, jsonString, jsonNumber, jsonInt, jsonBool, jsonNull, jsonArray } from "std/serialize/json/builder";
import { stringify } from "std/serialize/json/stringify";
import { getDynamicField } from "std/serialize/json/accessors";
import { DevNode, DevDriver, devDriver } from "./driver";
import { onDevEvent, DEV_EVENTS_VERSION } from "./events";
import { refreshMounted } from "../render/refresh";

when (hcr) {
	import { env } from "std/process";
	import { createSocket, bind, listen, setNonBlocking, acceptNonBlock, recvNonBlock, sendNonBlock, close } from "std/net";
}

export const PARSE_ERROR = -32700;
export const INVALID_REQUEST = -32600;
export const METHOD_NOT_FOUND = -32601;
export const INVALID_PARAMS = -32602;
export const APP_ERROR = -32000;

export const CONTROL_METHODS = ["ping", "tree", "components", "press", "type", "subscribe", "eval"];

export class ControlSession {
	send: (line: string) => void;
	unsubscribe: (() => void) | null = null;

	constructor(send: (line: string) => void) {
		this.send = send;
	}
}

export function closeSession(session: ControlSession): void {
	const off = session.unsubscribe;
	session.unsubscribe = null;
	if (off !== null) { (off as () => void)(); }
}

class ControlError extends Error {
	code: int32;

	constructor(code: int32, message: string) {
		super(message);
		this.code = code;
	}
}

function reply(id: JsonValue, result: JsonValue): string {
	return stringify(jsonObject(["jsonrpc", "id", "result"], [jsonString("2.0"), id, result]), false);
}

function failure(id: JsonValue, code: int32, message: string): string {
	const error = jsonObject(["code", "message"], [jsonInt(code as int64), jsonString(message)]);
	return stringify(jsonObject(["jsonrpc", "id", "error"], [jsonString("2.0"), id, error]), false);
}

function nodeJson(n: DevNode, id: string): JsonValue {
	const children: JsonValue[] = [];
	for (let i = 0; i < n.children.length; i += 1) { children.push(nodeJson(n.children[i], id === "" ? `${i}` : `${id}.${i}`)); }
	const frame = jsonArray([jsonNumber(n.x as number), jsonNumber(n.y as number), jsonNumber(n.w as number), jsonNumber(n.h as number)]);
	return jsonObject(
		["id", "tag", "text", "value", "focused", "pressable", "frame", "children"],
		[jsonString(id), jsonString(n.tag), jsonString(n.text), n.value === null ? jsonNull() : jsonString(n.value as string), jsonBool(n.focused), jsonBool(n.pressable), frame, jsonArray(children)],
	);
}

function findById(n: DevNode, path: string): DevNode | null {
	if (path === "") { return n; }
	let cur = n;
	for (const part of path.split(".")) {
		const at = parseInt(part);
		if (`${at}` !== part || at < 0 || at >= cur.children.length) { return null; }
		cur = cur.children[at];
	}
	return cur;
}

function findByText(n: DevNode, text: string): DevNode | null {
	if (n.text === text || n.value === text) { return n; }
	for (const c of n.children) {
		const hit = findByText(c, text);
		if (hit !== null) { return hit; }
	}
	return null;
}

function stringParam(params: JsonValue, name: string): string {
	const v = getDynamicField(params, name);
	if (v.kind !== JsonKind.String) { throw new ControlError(INVALID_PARAMS as int32, `params.${name} must be a string`); }
	return v.strVal;
}

function driverOrFail(): DevDriver {
	const d = devDriver();
	if (d === null) { throw new ControlError(APP_ERROR as int32, "no UI driver: this host has not opened a surface the control channel can drive"); }
	return d as DevDriver;
}

function components(): JsonValue {
	const out: JsonValue[] = [];
	for (const c of refreshMounted()) {
		const keys: string[] = [];
		const values: JsonValue[] = [];
		for (const kept of c.state) {
			keys.push(kept.key);
			values.push(jsonString(kept.value));
		}
		out.push(jsonObject(["component", "broken", "state"], [jsonString(c.key), jsonBool(c.broken), jsonObject(keys, values)]));
	}
	return jsonArray(out);
}

function call(session: ControlSession, method: string, params: JsonValue): JsonValue {
	if (method === "ping") {
		const d = devDriver();
		return jsonObject(["protocol", "host"], [jsonInt(DEV_EVENTS_VERSION as int64), d === null ? jsonNull() : jsonString(d.host)]);
	}
	if (method === "tree") { return nodeJson(driverOrFail().tree(), ""); }
	if (method === "components") { return components(); }
	if (method === "press") {
		const d = driverOrFail();
		const root = d.tree();
		const target = stringParam(params, "target");
		const found = target.startsWith("text:") ? findByText(root, target.substring(5)) : findById(root, target);
		if (found === null) { throw new ControlError(INVALID_PARAMS as int32, `press: no node matches "${target}"; read "tree" for ids, or use "text:<exact text>"`); }
		const n = found as DevNode;
		const x = n.x + n.w / 2.0;
		const y = n.y + n.h / 2.0;
		d.pressAt(x, y);
		return jsonObject(["x", "y"], [jsonNumber(x as number), jsonNumber(y as number)]);
	}
	if (method === "type") {
		driverOrFail().type(stringParam(params, "text"));
		return jsonBool(true);
	}
	if (method === "subscribe") {
		if (session.unsubscribe === null) {
			session.unsubscribe = onDevEvent((line: string): void => {
				session.send(`{"jsonrpc":"2.0","method":"event","params":${line}}`);
			});
		}
		return jsonBool(true);
	}
	if (method === "eval") {
		throw new ControlError(METHOD_NOT_FOUND as int32, "eval needs the compiler half (msc compiles the snippet against the running build); see docs/DEVTOOLS.md §Build events and eval");
	}
	throw new ControlError(METHOD_NOT_FOUND as int32, `unknown method "${method}"; known: ${CONTROL_METHODS.join(", ")}`);
}

export function handleRequest(session: ControlSession, line: string): void {
	const parsed = parseJson(line);
	if (!parsed.ok) {
		session.send(failure(jsonNull(), PARSE_ERROR as int32, `parse error: ${parsed.error}`));
		return;
	}
	const request = parsed.value;
	const idField = getDynamicField(request, "id");
	const notification = idField.kind === JsonKind.Null;
	const methodField = getDynamicField(request, "method");
	if (request.kind !== JsonKind.Object || methodField.kind !== JsonKind.String) {
		session.send(failure(idField, INVALID_REQUEST as int32, "a request is an object with a string \"method\""));
		return;
	}
	try {
		const result = call(session, methodField.strVal, getDynamicField(request, "params"));
		if (!notification) { session.send(reply(idField, result)); }
	} catch (e) {
		if (notification) { return; }
		if (e instanceof ControlError) {
			session.send(failure(idField, e.code, e.message));
		} else {
			session.send(failure(idField, APP_ERROR as int32, `${methodField.strVal} threw: ${e.message}`));
		}
	}
}

interface ControlClient {
	fd: int32;
	input: string;
	output: string;
	session: ControlSession;
}

let listening = false;
let listener: int32 = -1;
const clients: ControlClient[] = [];

function openListener(): void {
	when (hcr) {
		const port = env.get("NEON_CONTROL");
		if (port === "") { return; }
		const n = parseInt(port);
		if (`${n}` !== port || n <= 0 || n > 65535) { throw new Error(`NEON_CONTROL must be a TCP port, got "${port}"`); }
		const fd = createSocket();
		if (fd < 0 || bind(fd, "127.0.0.1", n as int32) !== 0 || listen(fd, 4 as int32) !== 0) {
			throw new Error(`neon devtools: cannot listen on 127.0.0.1:${n} (NEON_CONTROL); is another app holding it?`);
		}
		setNonBlocking(fd);
		listener = fd;
		console.log(`neon devtools: control channel on 127.0.0.1:${n}`);
	}
}

function flush(c: ControlClient): boolean {
	when (hcr) {
		while (c.output.length > 0) {
			const sent = sendNonBlock(c.fd, c.output, 0 as int32);
			if (sent < 0) { return false; }
			if (sent === 0) { return true; }
			c.output = c.output.substring(sent);
		}
	}
	return true;
}

function drop(at: int32): void {
	const c = clients[at];
	closeSession(c.session);
	when (hcr) { close(c.fd); }
	clients.splice(at, 1);
}

export function pollControl(): void {
	if (!listening) {
		listening = true;
		openListener();
	}
	if (listener < 0) { return; }
	when (hcr) {
		for (let fd = acceptNonBlock(listener); fd >= 0; fd = acceptNonBlock(listener)) {
			setNonBlocking(fd);
			const c: ControlClient = { fd, input: "", output: "", session: new ControlSession((line: string): void => {}) };
			c.session.send = (line: string): void => { c.output += line + "\n"; };
			clients.push(c);
		}
		for (let i = clients.length - 1; i >= 0; i -= 1) {
			const c = clients[i];
			for (let chunk = recvNonBlock(c.fd, 8192 as int32); chunk !== ""; chunk = recvNonBlock(c.fd, 8192 as int32)) { c.input += chunk; }
			for (let nl = c.input.indexOf("\n"); nl >= 0; nl = c.input.indexOf("\n")) {
				const line = c.input.substring(0, nl).trim();
				c.input = c.input.substring(nl + 1);
				if (line !== "") { handleRequest(c.session, line); }
			}
		}
		for (let i = clients.length - 1; i >= 0; i -= 1) {
			if (!flush(clients[i])) { drop(i as int32); }
		}
	}
}
