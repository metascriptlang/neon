import { NeonNode } from "../../src/render/host";

const v: NeonNode = <p ref="lit">hi</p>;
console.log(v === null);
