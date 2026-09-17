import { NeonView } from "../../src/render/host";

const v: NeonView = <p ref="lit">hi</p>;
console.log(v === null);
