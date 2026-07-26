function boom(): string { throw "x"; }

test "plain throw caught" {
	let threw = false;
	try { const s = boom(); } catch (e) { threw = true; }
	assert threw, "threw";
}
