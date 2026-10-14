import { NeonNode } from "../../src/render/node";

const v: NeonNode = <div><p ref={[]}>hi</p></div>;
console.log(v === null);
