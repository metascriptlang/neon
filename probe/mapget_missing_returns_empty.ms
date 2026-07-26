function main(): void {
	const m: Map<string, string> = new Map<string, string>();
	m.set("a", "1");
	const miss = m.get("nope");
	console.log("missing === null : " + (miss === null).toString());
	console.log("missing value    : [" + (miss === null ? "<null>" : miss) + "]");
	const hit = m.get("a");
	console.log("hit === null     : " + (hit === null).toString());
	console.log("has(nope)        : " + m.has("nope").toString());
}
main();
