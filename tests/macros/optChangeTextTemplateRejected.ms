import { NeonNode } from "../../src/render/host";

function field(onText: ((t: string) => void) | null): NeonNode {
	return <div><input onChangeText={onText} /></div>;
}
console.log(field(null) === null);
