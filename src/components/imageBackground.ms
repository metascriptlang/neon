import { NeonEvent } from "../render/event";
import { Style, layerStyles } from "../render/style";
import { Accessor, accessor } from "../core/signal";
import { NeonNode } from "../render/node";
import { Host, HostNode } from "../render/hostTypes";
import { AccessibilityProps, View } from "./primitives";
import { Image, ImageResizeMode, ImageSource } from "./image";

interface ImageBackgroundProps extends AccessibilityProps {
	source?: Accessor<ImageSource> | null;
	resizeMode?: Accessor<ImageResizeMode> | null;
	style?: Accessor<Style> | null;
	imageStyle?: Accessor<Style> | null;
	onLoadStart?: (() => void) | null;
	onLoad?: ((e: NeonEvent) => void) | null;
	onError?: ((e: NeonEvent) => void) | null;
	onLoadEnd?: (() => void) | null;
	onLayout?: ((e: NeonEvent) => void) | null;
	children?: NeonNode | null;
}

const RELATIVE: Style = { position: "relative" };
const FILL: Style = { position: "absolute", top: 0, left: 0, right: 0, bottom: 0 };

// RN Libraries/Image/ImageBackground.js: a View holding an Image stretched
// over its whole box, then the children on top of it. The View is the image's
// containing block, which a browser only grants a positioned element.
export function ImageBackground(props: ImageBackgroundProps): NeonNode {
	const imageStyle = props.imageStyle;
	const fill = accessor((): Style => imageStyle === null ? FILL : layerStyles([FILL, (imageStyle as () => Style)()]));
	const image = Image({
		source: props.source,
		resizeMode: props.resizeMode,
		style: fill,
		onLoadStart: props.onLoadStart,
		onLoad: props.onLoad,
		onError: props.onError,
		onLoadEnd: props.onLoadEnd,
	});
	const kids = props.children;
	const layers: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		image(host, parent, before);
		if (kids !== null) { (kids as NeonNode)(host, parent, before); }
	};
	const user = props.style;
	const box = accessor((): Style => user === null ? RELATIVE : layerStyles([RELATIVE, (user as () => Style)()]));
	return View({
		style: box,
		accessible: props.accessible,
		accessibilityLabel: props.accessibilityLabel,
		accessibilityHint: props.accessibilityHint,
		accessibilityRole: props.accessibilityRole,
		onLayout: props.onLayout,
		children: layers,
	});
}
