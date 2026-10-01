import { Style, StyleValue } from "../../render/style";
import { applyCssPropBody, applyCssBody, cssStyleExternBody } from "../../macros/style/fields";

cssStyleExternBody(0);

// docs/STYLE.md §5 — the browser's projection of the portable Style IR.
// A bare number is points, which on the web means px; a string ("50%", "auto")
// is already CSS.
function len(v: number | string | null): string {
	if (v === null) { return ""; }
	if (typeof v === "string") { return v as string; }
	return `${v as number}px`;
}

function num(v: number | null): string {
	return v === null ? "" : `${v as number}`;
}

function word(v: string | null): string {
	return v === null ? "" : v as string;
}

applyCssPropBody(0);

applyCssBody(0);
