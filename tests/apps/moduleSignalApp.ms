import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { render, mockHost, mockNode, mockToString, HostNode } from "../../src/render/host";

const [count, setCount] = createSignal(0);

function main(): void {
	const host = mockHost();
	const root = mockNode("app");
	render(element(<div>count={count().toString()}</div>), host, root as unknown as HostNode);
	console.log(mockToString(root));
	setCount(1);
	console.log(mockToString(root));
}

main();
