import { createSignal } from "../src/core/signal";
import { dynText } from "../src/render/node";

function main(): void {
	const [count, setCount] = createSignal(0);
	const t = dynText(() => count() + "");
	console.log(t.dyn());
	setCount(count() + 1);
	console.log(t.dyn());
}
main();
