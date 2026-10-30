import { canvasFont } from "../../src/platform/sokol/canvasFont";
import { DEFAULT_FONT, fontFace } from "../../../void/src/void2d/font";
import { readFileBytes } from "std/fs";

const VOID_FONT = "../void/assets/font.ttf";

function bytesOf(path: string): uint8[] {
	const read = readFileBytes(path);
	if (!read.ok) { throw new Error(`${path} did not read; run from the Neon checkout root beside ../void`); }
	return read.value;
}

test "a canvas font and the default font load from bytes under a name no file has" {
	const bytes = bytesOf(VOID_FONT);
	const font = canvasFont("Probe Mono", null, bytes, bytes);
	assert font.ok, font.ok ? "" : font.error;
	assert fontFace(font.value) >= 0, "the bytes face draws";
	assert fontFace(DEFAULT_FONT) >= 0, "the default font draws from its bytes, with no assets/font.ttf beside the process";
	const again = canvasFont("Probe Mono", null, bytes, null);
	assert again.ok, "the same bytes under the same name are accepted";
	const other = canvasFont("Probe Mono", null, bytes.slice(0, bytes.length - 1), null);
	assert !other.ok && other.error.includes("from bytes"), other.ok ? "other bytes were accepted" : other.error;
}

test "a canvas font given as a path loads from its file as before" {
	const font = canvasFont(VOID_FONT, null, null, null);
	assert font.ok && fontFace(font.value) >= 0, font.ok ? "the file face does not draw" : font.error;
}
