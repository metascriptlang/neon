import { createSignal } from "../../src/core/signal";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEventWith } from "../../src/render/host";
import { TextInput, TextInputHandle } from "../../src/components/primitives";
import { neonEvent } from "../../src/render/event";

function secureMultilineDiagnostic(message: string): boolean {
	return message.indexOf("TextInput") >= 0 && message.indexOf("secureTextEntry") >= 0 && message.indexOf("multiline") >= 0 && message.indexOf("private-token") < 0;
}

test "secure multiline value is rejected before any host value write or ref" {
	const root = mockNode("root");
	const host = mockHost();
	const setAttr = host.setAttr;
	let secretWrites = 0;
	let refs = 0;
	host.setAttr = (node: HostNode, name: string, value: string): void => {
		if (value.indexOf("private-token") >= 0) { secretWrites += 1; }
		setAttr(node, name, value);
	};
	let message = "";
	try {
		render(element(<TextInput multiline={true} secureTextEntry={true} value="private-token" ref={(h: TextInputHandle): void => { refs += 1; }} />), host, root as unknown as HostNode);
	} catch (e) { message = e.toString(); }
	resetErrorHalt();
	assert secureMultilineDiagnostic(message), "case-naming rejection without secret: " + message;
	assert root.children.length === 0 && secretWrites === 0 && refs === 0, "no mounted node, secret write or ref";
}

test "secure multiline defaultValue is rejected before mounting" {
	const root = mockNode("root");
	let message = "";
	try {
		render(element(<TextInput multiline={true} secureTextEntry={true} defaultValue="private-token-default" />), mockHost(), root as unknown as HostNode);
	} catch (e) { message = e.toString(); }
	resetErrorHalt();
	assert secureMultilineDiagnostic(message), "case-naming rejection without secret: " + message;
	assert root.children.length === 0, mockToString(root);
}

test "secure single line and nonsecure multiline preserve value events selection ref and cleanup" {
	const [value, setValue] = createSignal("first");
	const handles: TextInputHandle[] = [];
	let selected = "";
	const root: MockNode = mockNode("root");
	const dispose = render(element(<>
		<TextInput secureTextEntry={true} value={value()} accessibilityLabel="Password" selection={{ start: 1, end: 3 }}
			ref={(h: TextInputHandle): void => { handles.push(h); }} onChangeText={(text: string): void => { setValue(text); }}
			onSelectionChange={(s): void => { selected = `${s.start},${s.end}`; }} />
		<TextInput multiline={true} secureTextEntry={false} defaultValue="notes" />
	</>), mockHost(), root as unknown as HostNode);
	const single = root.children[0];
	assert single.tag === "textinput" && root.children[1].tag === "multilinetextinput", mockToString(root);
	assert mockToString(root).indexOf('secureTextEntry="true"') >= 0 && mockToString(root).indexOf('selection="1,3"') >= 0 && mockToString(root).indexOf('accessibilityLabel="Password"') >= 0, mockToString(root);
	const event = neonEvent("changetext");
	event.value = "next";
	fireEventWith(single, "onChangeText", event);
	assert value() === "next" && mockToString(root).indexOf('value="next"') >= 0, mockToString(root);
	event.value = "2,4";
	fireEventWith(single, "onSelectionChange", event);
	assert selected === "2,4", selected;
	handles[0].focus();
	assert handles[0].isFocused(), "focus works";
	dispose();
	let refused = false;
	try { handles[0].focus(); } catch { refused = true; }
	assert refused, "disposed handle refuses focus";
}

test "a mounted multiline field rejects batched secure and value changes before writing the new secret" {
	const [secure, setSecure] = createSignal(false);
	const [value, setValue] = createSignal("public notes");
	const root = mockNode("root");
	const dispose = render(element(<TextInput multiline={true} secureTextEntry={secure()} value={value()} />), mockHost(), root as unknown as HostNode);
	let message = "";
	try { flush((): void => { setValue("private-token-update"); setSecure(true); }); } catch (e) { message = e.toString(); }
	resetErrorHalt();
	assert secureMultilineDiagnostic(message), "case-naming rejection without secret: " + message;
	assert mockToString(root).indexOf("private-token") < 0, "new secret never reaches existing multiline node: " + mockToString(root);
	dispose();
}

test "a multiline host stays unsupported for secure entry after its multiline prop becomes false" {
	const [multiline, setMultiline] = createSignal(true);
	const [secure, setSecure] = createSignal(false);
	const root = mockNode("root");
	const dispose = render(element(<TextInput multiline={multiline()} secureTextEntry={secure()} />), mockHost(), root as unknown as HostNode);
	setMultiline(false);
	assert root.children[0].tag === "multilinetextinput", "host tag is fixed";
	let message = "";
	try { setSecure(true); } catch (e) { message = e.toString(); }
	resetErrorHalt();
	assert secureMultilineDiagnostic(message), "case-naming rejection without secret: " + message;
	dispose();
}

test "a secure single-line host rejects requested multiline changes alone and with value or defaultValue" {
	for (const channel of [0, 1, 2]) {
		const [multiline, setMultiline] = createSignal(false);
		const [value, setValue] = createSignal("original");
		const root = mockNode("root");
		const host = mockHost();
		const setAttr = host.setAttr;
		let secretWrites = 0;
		host.setAttr = (node: HostNode, name: string, text: string): void => {
			if (text.indexOf("private-token") >= 0) { secretWrites += 1; }
			setAttr(node, name, text);
		};
		const content = channel === 2
			? element(<TextInput multiline={multiline()} secureTextEntry={true} defaultValue={value()} />)
			: element(<TextInput multiline={multiline()} secureTextEntry={true} value={value()} />);
		const dispose = render(content, host, root as unknown as HostNode);
		assert root.children[0].tag === "textinput", "initial host is single-line";
		let message = "";
		try {
			flush((): void => {
				if (channel !== 0) { setValue("private-token-transition"); }
				setMultiline(true);
			});
		} catch (e) { message = e.toString(); }
		resetErrorHalt();
		assert secureMultilineDiagnostic(message), "requested multiline rejection: " + message;
		assert secretWrites === 0 && mockToString(root).indexOf("private-token") < 0, "no transient or final secret write";
		dispose();
	}
}

test "a nonsecure single-line host allows requested multiline and value changes" {
	const [multiline, setMultiline] = createSignal(false);
	const [value, setValue] = createSignal("public");
	const root = mockNode("root");
	const dispose = render(element(<TextInput multiline={multiline()} secureTextEntry={false} value={value()} />), mockHost(), root as unknown as HostNode);
	setMultiline(true);
	setValue("next");
	assert root.children[0].tag === "textinput" && mockToString(root).indexOf('value="next"') >= 0, "fixed host remains usable";
	dispose();
}
