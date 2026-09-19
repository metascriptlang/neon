import { NeonNode, el } from "../../src/render/node";

function Label(): NeonNode { return <label></label>; }
function field(onText: ((t: string) => void) | null): NeonNode {
	return <div><Label /><input onChangeText={onText} /></div>;
}
console.log(field(null) === null);
