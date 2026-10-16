import { Host, HostNode, NeonNode } from "../../src/render/hostTypes";
import { render, mockHost, mockNode, mockToString } from "../../src/render/host";
import { isServer } from "../../src/render/environment";
import { View, ViewHandle } from "../../src/components/primitives";
import { form } from "./requestForm";

test "a client render outside a request draws ids that never repeat" {
	const host = mockHost();
	const a = mockNode("root");
	const b = mockNode("root");
	const disposeA = render(form(), host, a as unknown as HostNode);
	const disposeB = render(form(), host, b as unknown as HostNode);
	const htmlA = mockToString(a);
	const htmlB = mockToString(b);
	disposeA();
	disposeB();
	assert htmlA.includes("for=\"cl-") && htmlA !== htmlB, htmlA + " | " + htmlB;
}

test "a client render runs each ref once" {
	let refs = 0;
	const count = (n: HostNode): void => { refs += 1; };
	const countView = (h: ViewHandle): void => { refs += 1; };
	const tree = (): NeonNode => <View><canvas ref={count}></canvas><View ref={countView}><p>x</p></View></View>;
	const root = mockNode("root");
	const dispose = render(tree(), mockHost(), root as unknown as HostNode);
	dispose();
	assert refs === 2, "the client render ran " + refs.toString() + " refs";
}

test "a client render on the mock host is not a server render" {
	let during = true;
	const probe: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => { during = isServer(); };
	const root = mockNode("root");
	render(probe, mockHost(), root as unknown as HostNode)();
	assert !during, "a client render on the mock host is not a server render";
}
