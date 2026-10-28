import { findSystemFonts, Presentation as SystemPresentation } from "../../../../ion/src/font";
import { FaceCandidate, FaceQuery, FontStyle, Presentation } from "../../../../void/src/void2d/font";

export function systemFace(query: FaceQuery): FaceCandidate[] {
	return findSystemFonts(query.codepoint, {
		presentation: query.presentation == Presentation.Emoji ? SystemPresentation.Emoji : SystemPresentation.Text,
		weight: query.weight,
		italic: query.style == FontStyle.Italic,
		family: "",
	}).map((f): FaceCandidate => ({ path: f.path, index: f.index }));
}
