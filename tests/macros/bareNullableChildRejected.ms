import { NeonNode } from "../../src/render/node";

function view(maybe: NeonNode | null): NeonNode {
	return <div><p>a</p>{maybe}</div>;
}
console.log(view(null) === null);
