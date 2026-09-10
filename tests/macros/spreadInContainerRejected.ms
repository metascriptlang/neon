import { NeonNode } from "../../src/render/node";

const p = { id: "x" };
const flag = true;
const v: NeonNode = <div>{flag ? <span {...p}>hi</span> : null}</div>;
console.log(v === null);
