function viaFinally(): void {
	try { throw "boom"; } finally { }
}

function viaEmptyCatch(): void {
	try { throw "boom2"; } catch { }
}

test "try/finally must NOT swallow (propagates to caller)" {
	let threw = false;
	try { viaFinally(); } catch (e) { threw = true; }
	assert threw, "try/finally must propagate";
}

test "empty catch{} MUST swallow" {
	viaEmptyCatch();
	assert true, "empty catch swallowed";
}
