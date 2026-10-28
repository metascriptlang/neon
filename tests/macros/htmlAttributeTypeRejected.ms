import { NeonNode } from "../../src/render/node";

const wide = true;
const v: NeonNode = <table><tr><td colspan={wide}>a</td></tr></table>;
console.log(v === null);
