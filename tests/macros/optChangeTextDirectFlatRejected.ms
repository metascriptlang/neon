import { NeonNode, el } from "../../src/render/node";
import { NeonView } from "../../src/render/host";

function Label(): NeonNode { return <label></label>; }
function field(onText: ((t: string) => void) | null): NeonView {
	return <div><Label /><input onChangeText={onText} /></div>;
}
console.log(field(null) === null);
