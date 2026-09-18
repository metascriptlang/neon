import { NeonNode } from "../../src/render/host";

const cond: boolean = true;
const v: NeonNode = <div>{cond && <><p>a</p><p>b</p></>}</div>;
console.log(v === null);
