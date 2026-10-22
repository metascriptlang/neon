import { addFont, registerFace, registerFaceBytes, defaultFontBytes, FontId, FontStyle } from "../../../../void/src/void2d/font";
import { familyFont } from "../void/host";

export function canvasFont(font: string, fontFamily: string | null, fontBytes: uint8[] | null, defaultBytes: uint8[] | null): Result<FontId, string> {
	if (defaultBytes !== null) {
		const held = defaultFontBytes(defaultBytes as uint8[]);
		if (!held.ok) { return Result.err(`cannot load the default font from bytes: ${held.error.toString()}`); }
	}
	if (fontBytes !== null) {
		const held = registerFaceBytes(font, fontBytes as uint8[], font, 400, FontStyle.Normal);
		if (!held.ok) { return Result.err(`cannot load the font ${font} from bytes: ${held.error.toString()}`); }
	} else {
		registerFace(font, font, 400, FontStyle.Normal);
	}
	const family = fontFamily !== null ? fontFamily as string : font;
	const loaded = fontFamily !== null ? familyFont(family, 400, false) : addFont(font);
	if (!loaded.ok) { return Result.err(`cannot load the font ${family}: ${loaded.error.toString()}`); }
	return Result.ok(loaded.value);
}
