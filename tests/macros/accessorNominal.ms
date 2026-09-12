import { Accessor } from "../../src/core/signal";

const a: Accessor<number> = () => 1;
console.log(a());
