export { raiserDispatch, raiserDispose } from "../../../src/platform/raiser/guest";

extern function unsignedProbe(): int32 from "test.unsigned";

export function probe(): int32 {
	return unsignedProbe();
}
