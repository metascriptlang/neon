// Platform blocks (docs/STYLE.md §2, §4 job 5, S4c): a `when` key holding one
// block per platform, spelled after the language keyword because the choice is
// made at COMPILE time — the non-target block never reaches the binary. That is
// the difference from Unistyles, whose ios/android selection is RN's runtime
// Platform.select; only its web block (`_web`) is resolved by a compiler.
//
// Asserted on the sheet value rather than through a host, so both lanes run it.
// The per-lane expectation is computed at module scope: `when` splices into a
// statement list, and a test body is not one it can reach.

import { createStyles, styleOf } from "../../src/macros/ui/style";

const sheet = createStyles({
	box: {
		width: 200,
		height: 120,
		when: {
			web: { width: 100 },
			macos: { width: 300 },
			ios: { height: 999 },
		},
	},
	plain: { width: 10 },
});

when (js) {
	const expectedWidth = 100;
} else when (macos) {
	const expectedWidth = 300;
} else {
	const expectedWidth = 200;
}

test "the target's platform block overrides a base field" {
	assert sheet.box.width === expectedWidth, "platform layer wins on the target lane";
}

test "a base field the platform block does not set survives" {
	assert sheet.box.height === 120, "height comes from the base, not from the ios block";
}

test "a non-target platform block never lands" {
	assert sheet.box.height !== 999, "the ios block must be cut on both the js and macos lanes";
}

test "an entry with no platform block is untouched" {
	assert sheet.plain.width === 10, "plain entry passes through";
}
