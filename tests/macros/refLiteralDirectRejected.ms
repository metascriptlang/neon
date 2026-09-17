import { NeonView } from "../../src/render/host";

const v: NeonView = <div><p ref="lit">hi</p></div>;
console.log(v === null);
