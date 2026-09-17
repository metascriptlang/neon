import { NeonView } from "../../src/render/host";

function field(onText: ((t: string) => void) | null): NeonView {
	return <div><input onChangeText={onText} /></div>;
}
console.log(field(null) === null);
