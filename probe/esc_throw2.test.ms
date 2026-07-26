function boom(v: number): number {
	throw new Error("boom");
}
test "throw escapes -> should FAIL, not pass" {
	console.log("MARK-before");
	const r = boom(1);
	console.log("MARK-after");
	assert 1 === 2, "this assert must fail";
}
