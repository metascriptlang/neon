// Variants (docs/STYLE.md §2): named groups selected by the CALLER at the use
// site. An entry carrying `variants` becomes callable — the macro emits an
// arrow whose selector type names the groups and their variant names, so a
// group typo or a wrong variant name is a checker error at the call site.
// Selection merges at runtime through mergeStyle, so a selected result drops
// cssId/css and takes the inline path — a one-off combination, like a merged
// layer array. An entry without `variants` is untouched by this feature.
//
// Asserted on the returned Style directly, so both lanes run it (no host).

import { Style, mergeStyle, emptyStyle } from "../../src/render/style";
import { createStyles, styleOf } from "../../src/macros/ui/style";

const s = createStyles({
	btn: {
		padding: 8,
		backgroundColor: "#334",
		variants: {
			size: { sm: { padding: 6 }, lg: { padding: 12 } },
			state: { on: { backgroundColor: "#445" } },
		},
	},
	title: { fontSize: 18 },
});

test "no selection keeps the base fields" {
	const st = s.btn({});
	assert st.padding === 8, "base padding survives an empty selection";
	assert st.backgroundColor === "#334", "base color survives an empty selection";
}

test "a selected variant overrides its group's fields" {
	const st = s.btn({ size: "lg" });
	assert st.padding === 12, "lg padding wins over the base";
	assert st.backgroundColor === "#334", "an unselected group leaves its fields alone";
}

test "each variant in a group is reachable" {
	assert s.btn({ size: "sm" }).padding === 6, "sm selects the sm block";
	assert s.btn({ size: "lg" }).padding === 12, "lg selects the lg block";
}

test "two groups select independently" {
	const st = s.btn({ size: "sm", state: "on" });
	assert st.padding === 6, "size group applied";
	assert st.backgroundColor === "#445", "state group applied";
}

test "a selection driven by data picks per call" {
	const pressed = true;
	const st = s.btn({ state: pressed ? "on" : "" });
	assert st.backgroundColor === "#445", "a matched runtime value selects";
	const st2 = s.btn({ state: false ? "on" : "" });
	assert st2.backgroundColor === "#334", "an unmatched value falls back to the base";
}

test "a selected result leaves the class path" {
	const st = s.btn({ size: "lg" });
	assert st.cssId === null, "a one-off combination carries no class id";
}

test "an entry without variants stays a plain style" {
	assert s.title.fontSize === 18, "plain entry unchanged";
}
