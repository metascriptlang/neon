import { findSystemFont, Presentation as SystemPresentation } from "../../../../ion/src/font";
import { FaceQuery, FontStyle, Presentation } from "../../../../void/src/void2d/font";

export function systemFace(query: FaceQuery): string | null {
	const found = findSystemFont(query.codepoint, {
		presentation: query.presentation == Presentation.Emoji ? SystemPresentation.Emoji : SystemPresentation.Text,
		weight: query.weight,
		italic: query.style == FontStyle.Italic,
		family: "",
	});
	return found === null ? null : found.path;
}
