import { createSignal } from "../../src/core/signal";
import { render, mockHost, mockNode, mockToString, MockNode, HostNode } from "../../src/render/host";
import { hydrate } from "../../src/render/hydrate";
import { View } from "../../src/components/primitives";
import { Layout, Page } from "./headPages";
import { flush } from "../../src/core/runtime";

test "on a client the title follows its signal and leaves with its Head" {
	const [title, setTitle] = createSignal("One");
	const [shown, setShown] = createSignal(true);
	const host = mockHost();
	const root = mockNode("root");
	render(<View><Show when={shown()}><Page title={title} /></Show></View>, host, root as unknown as HostNode);
	const head = (host.headRoot as (n: HostNode) => HostNode)(root as unknown as HostNode) as unknown as MockNode;
	assert mockToString(head).indexOf("<title>One</title>") >= 0, mockToString(head);
	setTitle("Two");
	flush();
	assert mockToString(head).indexOf("<title>Two</title>") >= 0, mockToString(head);
	setShown(false);
	flush();
	assert mockToString(head) === "<head></head>", mockToString(head);
}

test "the Head mounted last comes first, where a browser reads the title" {
	const [title, _t] = createSignal("Page");
	const host = mockHost();
	const root = mockNode("root");
	render(<Layout><Page title={title} /></Layout>, host, root as unknown as HostNode);
	const head = (host.headRoot as (n: HostNode) => HostNode)(root as unknown as HostNode) as unknown as MockNode;
	assert mockToString(head).indexOf("<head><title>Page</title>") === 0, mockToString(head);
}

test "a host with no head renders the rest of the tree" {
	const [title, _t] = createSignal("Docs");
	const host = mockHost();
	host.headRoot = null;
	const root = mockNode("root");
	render(<Page title={title} />, host, root as unknown as HostNode);
	assert mockToString(root) === "<root><view><text>body</text></view></root>", mockToString(root);
}

test "hydrate reads the body from the page and mounts what Head holds fresh" {
	const [title, _t] = createSignal("Docs");
	const root = mockNode("root");
	render(<Page title={title} />, mockHost(), root as unknown as HostNode, "")();
	const before = mockToString(root);
	const host = mockHost();
	hydrate(<Page title={title} />, host, root as unknown as HostNode);
	assert mockToString(root) === before, mockToString(root);
	const head = (host.headRoot as (n: HostNode) => HostNode)(root as unknown as HostNode) as unknown as MockNode;
	assert mockToString(head).indexOf("<head><title>Docs</title>") === 0, mockToString(head);
}
