function rec(d: number): string {
	if (d === 0) { throw "x"; }
	return rec(d - 1);
}

test "recursive throw caught" {
	let threw = false;
	try { const s = rec(3); } catch (e) { threw = true; }
	assert threw, "threw";
}
