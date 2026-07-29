import { createSignal } from "../src/core/signal";

const [count, setCount] = createSignal(0);
console.log(count());
setCount(count() + 1);
console.log(count());
