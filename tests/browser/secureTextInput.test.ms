import { domHost } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { createSignal, batch } from "../../src/core/signal";
import { TextInput, TextInputHandle } from "../../src/components/primitives";

extern class HTMLElement {
	extern querySelector(selector: cstring): HTMLElement | null;
	extern appendChild(child: HTMLElement): void;
	extern setAttribute(name: cstring, value: cstring): void;
}

extern class window {
	static extern eval(code: cstring): string;
}

extern class document {
	static body: HTMLElement;
	static extern createElement(tag: cstring): HTMLElement;
}

function mountPoint(id: string): HTMLElement {
	const mount = document.createElement("div");
	mount.setAttribute("id", id);
	document.body.appendChild(mount);
	return mount;
}

function js(code: string): string {
	return window.eval(`String((() => { ${code} })())`);
}

function secureMultilineDiagnostic(message: string): boolean {
	return message.indexOf("TextInput") >= 0 && message.indexOf("secureTextEntry") >= 0 && message.indexOf("multiline") >= 0 && message.indexOf("private-token") < 0;
}

test "Chrome never mounts a secure multiline value as an unmasked textarea" {
	const mount = mountPoint("secure-invalid-value");
	let refs = 0;
	let message = "";
	try {
		render(element(<TextInput multiline={true} secureTextEntry={true} value="private-token" ref={(h: TextInputHandle): void => { refs += 1; }} />), domHost(), mount as unknown as HostNode);
	} catch (e) { message = e.toString(); }
	assert mount.querySelector("textarea") === null, "unsupported textarea mounted: " + js("const el = document.querySelector('#secure-invalid-value textarea'); return el ? el.type + ' ' + el.value : 'none';");
	assert secureMultilineDiagnostic(message) && refs === 0, "case-naming rejection, no secret or ref: " + message;
}

test "Chrome never mounts a secure multiline defaultValue" {
	const mount = mountPoint("secure-invalid-default");
	let message = "";
	try {
		render(element(<TextInput multiline={true} secureTextEntry={true} defaultValue="private-token-default" />), domHost(), mount as unknown as HostNode);
	} catch (e) { message = e.toString(); }
	assert mount.querySelector("textarea") === null && secureMultilineDiagnostic(message), "secure multiline defaultValue refused: " + message;
}

test "Chrome keeps password input usable and nonsecure multiline editable" {
	const [value, setValue] = createSignal("first");
	const handles: TextInputHandle[] = [];
	let notes = "";
	let selection = "";
	const mount = mountPoint("secure-controls");
	const dispose = render(element(<>
		<TextInput secureTextEntry={true} value={value()} accessibilityLabel="Password" selection={{ start: 1, end: 3 }}
			ref={(h: TextInputHandle): void => { handles.push(h); }} onChangeText={(text: string): void => { setValue(text); }}
			onSelectionChange={(s): void => { selection = `${s.start},${s.end}`; }} />
		<TextInput multiline={true} secureTextEntry={false} defaultValue="notes" onChangeText={(text: string): void => { notes = text; }} />
	</>), domHost(), mount as unknown as HostNode);
	assert js("const el = document.querySelector('#secure-controls input'); return el.type + ' ' + el.value + ' ' + el.getAttribute('aria-label') + ' ' + el.selectionStart + ',' + el.selectionEnd;") === "password first Password 1,3", "real password type, selection and accessibility";
	handles[0].focus();
	assert handles[0].isFocused() && js("return document.activeElement === document.querySelector('#secure-controls input');") === "true", "focus via ref";
	js("const el = document.querySelector('#secure-controls input'); el.value = 'typed'; el.dispatchEvent(new Event('input', { bubbles: true })); el.setSelectionRange(2, 4); el.dispatchEvent(new Event('selectionchange', { bubbles: true })); return 1;");
	assert value() === "typed" && selection === "2,4", "password input and selection events";
	setValue("controlled");
	assert js("return document.querySelector('#secure-controls input').value;") === "controlled", "controlled password update";
	assert js("return document.querySelector('#secure-controls textarea').value;") === "notes", "nonsecure defaultValue";
	js("const el = document.querySelector('#secure-controls textarea'); el.value = 'a\\nb'; el.dispatchEvent(new Event('input', { bubbles: true })); return 1;");
	assert notes === "a\nb", "nonsecure multiline input event";
	dispose();
	let refused = false;
	try { handles[0].focus(); } catch { refused = true; }
	assert refused, "disposed ref refuses focus";
}

test "Chrome rejects batched secure and value updates before a mounted textarea receives the secret" {
	const [secure, setSecure] = createSignal(false);
	const [value, setValue] = createSignal("public notes");
	const mount = mountPoint("secure-reactive-value");
	const dispose = render(element(<TextInput multiline={true} secureTextEntry={secure()} value={value()} />), domHost(), mount as unknown as HostNode);
	js("globalThis.secureWrites = 0; const el = document.querySelector('#secure-reactive-value textarea'); const d = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value'); Object.defineProperty(el, 'value', { get() { return d.get.call(this); }, set(v) { if (v.includes('private-token')) globalThis.secureWrites++; d.set.call(this, v); } }); return 1;");
	let message = "";
	try { batch((): void => { setValue("private-token-update"); setSecure(true); }); } catch (e) { message = e.toString(); }
	assert js("const el = document.querySelector('#secure-reactive-value textarea'); return el.value + ' ' + globalThis.secureWrites;") === "public notes 0", "no transient or final secret value write";
	assert secureMultilineDiagnostic(message), "reactive rejection: " + message;
	dispose();
}

test "Chrome rejects batched secure and defaultValue updates on an existing textarea" {
	const [secure, setSecure] = createSignal(false);
	const [value, setValue] = createSignal("public default");
	const mount = mountPoint("secure-reactive-default");
	const dispose = render(element(<TextInput multiline={true} secureTextEntry={secure()} defaultValue={value()} />), domHost(), mount as unknown as HostNode);
	let message = "";
	try { batch((): void => { setValue("private-token-default-update"); setSecure(true); }); } catch (e) { message = e.toString(); }
	assert js("const el = document.querySelector('#secure-reactive-default textarea'); return el.value.includes('private-token') || el.defaultValue.includes('private-token');") === "false", "no secret default value";
	assert secureMultilineDiagnostic(message), "reactive default rejection: " + message;
	dispose();
}

test "Chrome rejects secure entry on a fixed textarea even after multiline becomes false" {
	const [multiline, setMultiline] = createSignal(true);
	const [secure, setSecure] = createSignal(false);
	const mount = mountPoint("secure-fixed-tag");
	const dispose = render(element(<TextInput multiline={multiline()} secureTextEntry={secure()} />), domHost(), mount as unknown as HostNode);
	setMultiline(false);
	assert mount.querySelector("textarea") !== null, "host tag remains textarea";
	let message = "";
	try { setSecure(true); } catch (e) { message = e.toString(); }
	assert secureMultilineDiagnostic(message), "fixed-tag rejection: " + message;
	dispose();
}

test "Chrome rejects requested multiline on a password input alone and batched with value or defaultValue" {
	for (const channel of [0, 1, 2]) {
		const [multiline, setMultiline] = createSignal(false);
		const [value, setValue] = createSignal("original");
		const id = `secure-requested-${channel}`;
		const mount = mountPoint(id);
		const content = channel === 2
			? element(<TextInput multiline={multiline()} secureTextEntry={true} defaultValue={value()} />)
			: element(<TextInput multiline={multiline()} secureTextEntry={true} value={value()} />);
		const dispose = render(content, domHost(), mount as unknown as HostNode);
		js(`globalThis.secureRequestedWrites = 0; const el = document.querySelector('#${id} input'); for (const name of ['value', 'defaultValue']) { const d = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, name); Object.defineProperty(el, name, { get() { return d.get.call(this); }, set(v) { if (v.includes('private-token')) globalThis.secureRequestedWrites++; d.set.call(this, v); } }); } return 1;`);
		let message = "";
		try {
			batch((): void => {
				if (channel !== 0) { setValue("private-token-transition"); }
				setMultiline(true);
			});
		} catch (e) { message = e.toString(); }
		assert secureMultilineDiagnostic(message), "requested multiline rejection: " + message;
		assert js(`const el = document.querySelector('#${id} input'); return el.type + ' ' + el.value + ' ' + el.defaultValue + ' ' + globalThis.secureRequestedWrites;`).indexOf("private-token") < 0, "no final secret";
		assert js("return globalThis.secureRequestedWrites;") === "0", "no transient value or defaultValue write";
		dispose();
	}
}

test "Chrome preserves nonsecure input updates after requested multiline becomes true" {
	const [multiline, setMultiline] = createSignal(false);
	const [value, setValue] = createSignal("public");
	const mount = mountPoint("secure-requested-control");
	const dispose = render(element(<TextInput multiline={multiline()} secureTextEntry={false} value={value()} />), domHost(), mount as unknown as HostNode);
	setMultiline(true);
	setValue("next");
	assert js("const el = document.querySelector('#secure-requested-control input'); return el.type + ' ' + el.value;") === "text next", "nonsecure fixed host remains usable";
	dispose();
}
