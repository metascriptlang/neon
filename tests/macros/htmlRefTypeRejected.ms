import { NeonNode } from "../../src/render/node";

const v: NeonNode = <canvas ref={(c: HTMLDivElement): void => { console.log(c.id); }} />;
console.log(v === null);
