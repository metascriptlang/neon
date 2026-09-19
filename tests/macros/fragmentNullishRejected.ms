import { NeonNode } from "../../src/render/node";

const maybe: NeonNode | null = null;
const v: NeonNode = <div>{maybe ?? <><p>a</p><p>b</p></>}</div>;
console.log(v === null);
