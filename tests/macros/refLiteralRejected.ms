import { NeonNode } from "../../src/render/node";

const v: NeonNode = <div><p ref="lit">hi</p></div>;
console.log(v === null);
