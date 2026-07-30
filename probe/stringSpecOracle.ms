function row(label: string, v: string): void {
	console.log(label + " = " + v);
}

function probeString(name: string, s: string): void {
	row(name + ".length", s.length.toString());
	row(name + "[1].code", s[1].charCodeAt(0).toString());
	row(name + ".charAt(1).code", s.charAt(1).charCodeAt(0).toString());
	row(name + ".charCodeAt(1)", s.charCodeAt(1).toString());
	row(name + ".slice(1,3).codes", s.slice(1, 3).charCodeAt(0).toString() + "," + s.slice(1, 3).charCodeAt(1).toString());
	row(name + ".indexOf(x)", s.indexOf("x").toString());
	row(name + ".lastIndexOf(x)", s.lastIndexOf("x").toString());
	row(name + ".padStart(6,.)", s.padStart(6, "."));
	row(name + ".split(x).length", s.split("x").length.toString());
}

probeString("ascii", "axbxc");
probeString("latin", "héxlo");
probeString("dash", "a—xb");
probeString("cjk", "日本語x");
probeString("emoji", "👍x");
