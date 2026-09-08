import { NeonNode } from "../../src/render/node";

const p = { id: "x" };
const v: NeonNode = <div {...p}>hi</div>;
console.log(v === null);
