// react-native-paper's Avatar.Text and Avatar.Image in one component: a `source` shows the
// image, otherwise `label` shows initials. Round through borderRadius = size / 2, which the
// native hosts paint. The avatar is one image to a screen reader, labelled by `label`.

import { Style } from "../render/style";
import { Accessor, accessor } from "../core/signal";
import { element } from "../macros/ui/element";
import { NeonNode, VAttr, dynAttr, hostElement } from "../render/node";
import { defaultRole, layered } from "./drawn";
import { Image, ImageSource } from "./image";
import { AccessibilityProps, Text, accessibilityAttrs } from "./primitives";
import { MATERIAL_ON_PRIMARY, MATERIAL_PRIMARY, colorOr } from "./material";

interface AvatarProps extends AccessibilityProps {
	label?: Accessor<string> | null;
	source?: Accessor<ImageSource> | null;
	size?: Accessor<int32> | null;
	color?: Accessor<string> | null;
	backgroundColor?: Accessor<string> | null;
	style?: Accessor<Style> | null;
}

const DEFAULT_SIZE = 40;

export function Avatar(props: AvatarProps): NeonNode {
	const { label, source, size, color, backgroundColor } = props;
	const side = (): int32 => size === null ? DEFAULT_SIZE : (size as Accessor<int32>)();
	const round = (): Style => ({
		width: side(), height: side(), borderRadius: side() / 2, overflow: "hidden",
		alignItems: "center", justifyContent: "center",
		backgroundColor: colorOr(backgroundColor, MATERIAL_PRIMARY),
	});
	const attrs: VAttr[] = [];
	defaultRole(attrs, props.accessibilityRole === null, "image");
	if (props.accessibilityLabel === null && label !== null) {
		const read = label as Accessor<string>;
		attrs.push(dynAttr("accessibilityLabel", (): string | null => read()));
	}
	accessibilityAttrs(props, attrs);
	let kids: NeonNode | null = null;
	if (source !== null) {
		const src = source as Accessor<ImageSource>;
		const picture = accessor((): Style => ({
			width: side(), height: side(), borderRadius: side() / 2,
		}));
		kids = element(<Image
			source={src()} style={picture} resizeMode="cover" accessible={false}
		/>);
	} else if (label !== null) {
		const read = label as Accessor<string>;
		const ink = accessor((): Style => ({
			color: colorOr(color, MATERIAL_ON_PRIMARY), fontSize: side() / 2, fontWeight: "bold",
		}));
		kids = element(<Text style={ink}>{read()}</Text>);
	}
	return hostElement("view", attrs, [], kids, layered(round, props.style), null);
}
