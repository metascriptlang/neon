// Platform blocks (docs/STYLE.md §4 job 5, S4c): underscore-prefixed platform
// keys, ported from the `_web` key Unistyles 3.0 ships. Two differences from
// theirs, both from having a compiler: the key set extends past web (`_ios`,
// `_android`, `_macos` — Unistyles punts those to RN's runtime Platform.select),
// and the non-target block is cut by `when` at parse time, so it never reaches
// the binary.
//
// Asserted on the sheet value rather than through a host, so both lanes run it.
// The per-lane expectation is computed at module scope: `when` splices into a
// statement list, and a test body is not one it can reach.

import { createStyles, styleOf } from "../../src/macros/ui/style";

const sheet = createStyles({
	box: {
		width: 200,
		height: 120,
		_web: { width: 100 },
		_macos: { width: 300 },
		_ios: { height: 999 },
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
	assert sheet.box.height === 120, "height comes from the base, not from _ios";
}

test "a non-target platform block never lands" {
	assert sheet.box.height !== 999, "_ios must be cut on both the js and macos lanes";
}

test "an entry with no platform block is untouched" {
	assert sheet.plain.width === 10, "plain entry passes through";
}
