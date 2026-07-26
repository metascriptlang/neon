let log = "";

// A: throw inside a catch body — the enclosing finally MUST still run
function aThrowInCatch(): void {
	try { throw "a1"; } catch (e) { throw "a2"; } finally { log = log + "A"; }
}

// B: nested try/finally — BOTH finallys run, error keeps propagating
function bInner(): void {
	try { throw "b"; } finally { log = log + "i"; }
}
function bOuter(): void {
	try { bInner(); } finally { log = log + "o"; }
}

// C: DRC scaffold — owned local forces cleanup try/finally around the body
function cOwnedLocal(n: number): string {
	const s = "x" + n.toString();
	if (s.length > 0) { throw "c"; }
	return s;
}

// D: tail-recursive throw (the renderToString hang shape)
function dRec(n: number): string {
	if (n === 0) { throw "d"; }
	return dRec(n - 1);
}

// E: finally runs on the NORMAL path
function eNormal(): number {
	try { return 7; } finally { log = log + "E"; }
}

test "A: throw in catch still runs finally" {
	let outer = "";
	try { aThrowInCatch(); } catch (e) { outer = "caught"; }
	assert log.indexOf("A") >= 0, "finally must run when catch body throws";
	assert outer === "caught", "catch-body throw must reach the caller";
}

test "B: nested finallys both run, error propagates" {
	log = "";
	let threw = false;
	try { bOuter(); } catch (e) { threw = true; }
	assert threw, "must propagate through two finallys";
	assert log === "io", "both finallys run inner-then-outer";
}

test "C: DRC-cleanup scope propagates" {
	let threw = false;
	try { const r = cOwnedLocal(3); } catch (e) { threw = true; }
	assert threw, "owned-local scope must not swallow";
}

test "D: tail-recursive throw propagates (no infinite loop)" {
	let threw = false;
	try { const r = dRec(4); } catch (e) { threw = true; }
	assert threw, "tail-recursive throw must propagate";
}

test "E: finally runs on the normal path" {
	log = "";
	const v = eNormal();
	assert v === 7, "normal return value survives finally";
	assert log === "E", "finally runs without an exception";
}
