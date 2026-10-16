import { resetCss, mountSheet } from "../../src/render/sheet";

test "an empty registry emits no style block" {
	resetCss();
	assert mountSheet() === "", "nothing registered, nothing printed";
}
