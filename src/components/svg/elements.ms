// react-native-svg's element surface. Each shape renders a lowercase tag into the scene
// of its <Svg> (./scene.ms); only <Svg> itself places a node on the real host.

import { Accessor } from "../../core/signal";
import { Style, mergeStyle } from "../../render/style";
import { NeonEvent } from "../../render/event";
import { Host, HostNode } from "../../render/hostTypes";
import { NeonNode, VAttr, VEvent, RefFn, hostElement, evt, dynAttr } from "../../render/node";
import { bindAttr, bindStyleAll } from "../../render/bind";
import { place } from "../../render/reconcile";
import { AccessibilityProps, accessibilityAttrs, stringAttr } from "../primitives";
import { SvgScene, encodeScene, sceneChanged, sceneHost } from "./scene";

export type NumberProp = float64 | string;
export type NumberArrayProp = float64[] | string;
export type FillRule = "nonzero" | "evenodd";
export type StrokeLinecap = "butt" | "round" | "square";
export type StrokeLinejoin = "miter" | "round" | "bevel";
export type TextAnchor = "start" | "middle" | "end";
export type GradientUnits = "objectBoundingBox" | "userSpaceOnUse";

export function numberPropText(v: NumberProp): string {
	if (typeof v === "string") { return v as string; }
	return (v as float64).toString();
}

export function numberArrayText(v: NumberArrayProp): string {
	if (typeof v === "string") { return v as string; }
	const values = v as float64[];
	let text = "";
	for (const n of values) { text += (text === "" ? "" : " ") + n.toString(); }
	return text;
}

function numberAttr(attrs: VAttr[], name: string, value: Accessor<NumberProp> | null): void {
	if (value === null) { return; }
	const read = value as Accessor<NumberProp>;
	attrs.push(dynAttr(name, (): string | null => numberPropText(read())));
}

function numbersAttr(attrs: VAttr[], name: string, value: Accessor<NumberArrayProp> | null): void {
	if (value === null) { return; }
	const read = value as Accessor<NumberArrayProp>;
	attrs.push(dynAttr(name, (): string | null => numberArrayText(read())));
}

function fillRuleAttr(attrs: VAttr[], name: string, value: Accessor<FillRule> | null): void {
	if (value === null) { return; }
	const read = value as Accessor<FillRule>;
	attrs.push(dynAttr(name, (): string | null => { const v: FillRule = read(); return v; }));
}

export interface SvgPresentationProps {
	id?: Accessor<string> | null;
	fill?: Accessor<string> | null;
	fillOpacity?: Accessor<NumberProp> | null;
	fillRule?: Accessor<FillRule> | null;
	stroke?: Accessor<string> | null;
	strokeWidth?: Accessor<NumberProp> | null;
	strokeOpacity?: Accessor<NumberProp> | null;
	strokeLinecap?: Accessor<StrokeLinecap> | null;
	strokeLinejoin?: Accessor<StrokeLinejoin> | null;
	strokeMiterlimit?: Accessor<NumberProp> | null;
	strokeDasharray?: Accessor<NumberArrayProp> | null;
	strokeDashoffset?: Accessor<NumberProp> | null;
	opacity?: Accessor<NumberProp> | null;
	color?: Accessor<string> | null;
	transform?: Accessor<string> | null;
	rotation?: Accessor<NumberProp> | null;
	scale?: Accessor<NumberProp> | null;
	originX?: Accessor<NumberProp> | null;
	originY?: Accessor<NumberProp> | null;
	translateX?: Accessor<NumberProp> | null;
	translateY?: Accessor<NumberProp> | null;
	clipPath?: Accessor<string> | null;
	clipRule?: Accessor<FillRule> | null;
	fontSize?: Accessor<NumberProp> | null;
	fontWeight?: Accessor<NumberProp> | null;
	textAnchor?: Accessor<TextAnchor> | null;
}

function presentationAttrs(props: SvgPresentationProps, attrs: VAttr[]): VAttr[] {
	stringAttr(attrs, "id", props.id);
	stringAttr(attrs, "fill", props.fill);
	numberAttr(attrs, "fillOpacity", props.fillOpacity);
	fillRuleAttr(attrs, "fillRule", props.fillRule);
	stringAttr(attrs, "stroke", props.stroke);
	numberAttr(attrs, "strokeWidth", props.strokeWidth);
	numberAttr(attrs, "strokeOpacity", props.strokeOpacity);
	const cap = props.strokeLinecap;
	if (cap !== null) {
		const read = cap as Accessor<StrokeLinecap>;
		attrs.push(dynAttr("strokeLinecap", (): string | null => { const v: StrokeLinecap = read(); return v; }));
	}
	const join = props.strokeLinejoin;
	if (join !== null) {
		const read = join as Accessor<StrokeLinejoin>;
		attrs.push(dynAttr("strokeLinejoin", (): string | null => { const v: StrokeLinejoin = read(); return v; }));
	}
	numberAttr(attrs, "strokeMiterlimit", props.strokeMiterlimit);
	numbersAttr(attrs, "strokeDasharray", props.strokeDasharray);
	numberAttr(attrs, "strokeDashoffset", props.strokeDashoffset);
	numberAttr(attrs, "opacity", props.opacity);
	stringAttr(attrs, "color", props.color);
	stringAttr(attrs, "transform", props.transform);
	numberAttr(attrs, "rotation", props.rotation);
	numberAttr(attrs, "scale", props.scale);
	numberAttr(attrs, "originX", props.originX);
	numberAttr(attrs, "originY", props.originY);
	numberAttr(attrs, "translateX", props.translateX);
	numberAttr(attrs, "translateY", props.translateY);
	stringAttr(attrs, "clipPath", props.clipPath);
	fillRuleAttr(attrs, "clipRule", props.clipRule);
	numberAttr(attrs, "fontSize", props.fontSize);
	numberAttr(attrs, "fontWeight", props.fontWeight);
	const anchor = props.textAnchor;
	if (anchor !== null) {
		const read = anchor as Accessor<TextAnchor>;
		attrs.push(dynAttr("textAnchor", (): string | null => { const v: TextAnchor = read(); return v; }));
	}
	return attrs;
}

function shape(tag: string, attrs: VAttr[], children: NeonNode | null): NeonNode {
	return hostElement(tag, attrs, [], children, null, null);
}

export interface GProps extends SvgPresentationProps {
	children?: NeonNode | null;
}

export function G(props: GProps): NeonNode {
	return shape("g", presentationAttrs(props, []), props.children);
}

export interface PathProps extends SvgPresentationProps {
	d?: Accessor<string> | null;
}

export function Path(props: PathProps): NeonNode {
	const attrs = presentationAttrs(props, []);
	stringAttr(attrs, "d", props.d);
	return shape("path", attrs, null);
}

export interface RectProps extends SvgPresentationProps {
	x?: Accessor<NumberProp> | null;
	y?: Accessor<NumberProp> | null;
	width?: Accessor<NumberProp> | null;
	height?: Accessor<NumberProp> | null;
	rx?: Accessor<NumberProp> | null;
	ry?: Accessor<NumberProp> | null;
}

export function Rect(props: RectProps): NeonNode {
	const attrs = presentationAttrs(props, []);
	numberAttr(attrs, "x", props.x);
	numberAttr(attrs, "y", props.y);
	numberAttr(attrs, "width", props.width);
	numberAttr(attrs, "height", props.height);
	numberAttr(attrs, "rx", props.rx);
	numberAttr(attrs, "ry", props.ry);
	return shape("rect", attrs, null);
}

export interface CircleProps extends SvgPresentationProps {
	cx?: Accessor<NumberProp> | null;
	cy?: Accessor<NumberProp> | null;
	r?: Accessor<NumberProp> | null;
}

export function Circle(props: CircleProps): NeonNode {
	const attrs = presentationAttrs(props, []);
	numberAttr(attrs, "cx", props.cx);
	numberAttr(attrs, "cy", props.cy);
	numberAttr(attrs, "r", props.r);
	return shape("circle", attrs, null);
}

export interface EllipseProps extends SvgPresentationProps {
	cx?: Accessor<NumberProp> | null;
	cy?: Accessor<NumberProp> | null;
	rx?: Accessor<NumberProp> | null;
	ry?: Accessor<NumberProp> | null;
}

export function Ellipse(props: EllipseProps): NeonNode {
	const attrs = presentationAttrs(props, []);
	numberAttr(attrs, "cx", props.cx);
	numberAttr(attrs, "cy", props.cy);
	numberAttr(attrs, "rx", props.rx);
	numberAttr(attrs, "ry", props.ry);
	return shape("ellipse", attrs, null);
}

export interface LineProps extends SvgPresentationProps {
	x1?: Accessor<NumberProp> | null;
	y1?: Accessor<NumberProp> | null;
	x2?: Accessor<NumberProp> | null;
	y2?: Accessor<NumberProp> | null;
}

export function Line(props: LineProps): NeonNode {
	const attrs = presentationAttrs(props, []);
	numberAttr(attrs, "x1", props.x1);
	numberAttr(attrs, "y1", props.y1);
	numberAttr(attrs, "x2", props.x2);
	numberAttr(attrs, "y2", props.y2);
	return shape("line", attrs, null);
}

export interface PolylineProps extends SvgPresentationProps {
	points?: Accessor<NumberArrayProp> | null;
}

export function Polyline(props: PolylineProps): NeonNode {
	const attrs = presentationAttrs(props, []);
	numbersAttr(attrs, "points", props.points);
	return shape("polyline", attrs, null);
}

export function Polygon(props: PolylineProps): NeonNode {
	const attrs = presentationAttrs(props, []);
	numbersAttr(attrs, "points", props.points);
	return shape("polygon", attrs, null);
}

export interface SvgTextProps extends SvgPresentationProps {
	x?: Accessor<NumberProp> | null;
	y?: Accessor<NumberProp> | null;
	dx?: Accessor<NumberProp> | null;
	dy?: Accessor<NumberProp> | null;
	children?: NeonNode | null;
}

function textAttrs(props: SvgTextProps): VAttr[] {
	const attrs = presentationAttrs(props, []);
	numberAttr(attrs, "x", props.x);
	numberAttr(attrs, "y", props.y);
	numberAttr(attrs, "dx", props.dx);
	numberAttr(attrs, "dy", props.dy);
	return attrs;
}

export function Text(props: SvgTextProps): NeonNode {
	return shape("text", textAttrs(props), props.children);
}

export function TSpan(props: SvgTextProps): NeonNode {
	return shape("tspan", textAttrs(props), props.children);
}

export interface UseProps extends SvgPresentationProps {
	href?: Accessor<string> | null;
	x?: Accessor<NumberProp> | null;
	y?: Accessor<NumberProp> | null;
}

export function Use(props: UseProps): NeonNode {
	const attrs = presentationAttrs(props, []);
	stringAttr(attrs, "href", props.href);
	numberAttr(attrs, "x", props.x);
	numberAttr(attrs, "y", props.y);
	return shape("use", attrs, null);
}

export interface DefsProps {
	children?: NeonNode | null;
}

export function Defs(props: DefsProps): NeonNode {
	return shape("defs", [], props.children);
}

export interface ClipPathProps {
	id?: Accessor<string> | null;
	clipRule?: Accessor<FillRule> | null;
	transform?: Accessor<string> | null;
	children?: NeonNode | null;
}

export function ClipPath(props: ClipPathProps): NeonNode {
	const attrs: VAttr[] = [];
	stringAttr(attrs, "id", props.id);
	fillRuleAttr(attrs, "clipRule", props.clipRule);
	stringAttr(attrs, "transform", props.transform);
	return shape("clippath", attrs, props.children);
}

interface GradientProps {
	id?: Accessor<string> | null;
	gradientUnits?: Accessor<GradientUnits> | null;
	gradientTransform?: Accessor<string> | null;
	children?: NeonNode | null;
}

function gradientAttrs(props: GradientProps): VAttr[] {
	const attrs: VAttr[] = [];
	stringAttr(attrs, "id", props.id);
	const units = props.gradientUnits;
	if (units !== null) {
		const read = units as Accessor<GradientUnits>;
		attrs.push(dynAttr("gradientUnits", (): string | null => { const v: GradientUnits = read(); return v; }));
	}
	stringAttr(attrs, "gradientTransform", props.gradientTransform);
	return attrs;
}

export interface LinearGradientProps extends GradientProps {
	x1?: Accessor<NumberProp> | null;
	y1?: Accessor<NumberProp> | null;
	x2?: Accessor<NumberProp> | null;
	y2?: Accessor<NumberProp> | null;
}

export function LinearGradient(props: LinearGradientProps): NeonNode {
	const attrs = gradientAttrs(props);
	numberAttr(attrs, "x1", props.x1);
	numberAttr(attrs, "y1", props.y1);
	numberAttr(attrs, "x2", props.x2);
	numberAttr(attrs, "y2", props.y2);
	return shape("lineargradient", attrs, props.children);
}

export interface RadialGradientProps extends GradientProps {
	cx?: Accessor<NumberProp> | null;
	cy?: Accessor<NumberProp> | null;
	r?: Accessor<NumberProp> | null;
	fx?: Accessor<NumberProp> | null;
	fy?: Accessor<NumberProp> | null;
}

export function RadialGradient(props: RadialGradientProps): NeonNode {
	const attrs = gradientAttrs(props);
	numberAttr(attrs, "cx", props.cx);
	numberAttr(attrs, "cy", props.cy);
	numberAttr(attrs, "r", props.r);
	numberAttr(attrs, "fx", props.fx);
	numberAttr(attrs, "fy", props.fy);
	return shape("radialgradient", attrs, props.children);
}

export interface StopProps {
	offset?: Accessor<NumberProp> | null;
	stopColor?: Accessor<string> | null;
	stopOpacity?: Accessor<NumberProp> | null;
}

export function Stop(props: StopProps): NeonNode {
	const attrs: VAttr[] = [];
	numberAttr(attrs, "offset", props.offset);
	stringAttr(attrs, "stopColor", props.stopColor);
	numberAttr(attrs, "stopOpacity", props.stopOpacity);
	return shape("stop", attrs, null);
}

export interface SvgProps extends SvgPresentationProps, AccessibilityProps {
	width?: Accessor<NumberProp> | null;
	height?: Accessor<NumberProp> | null;
	viewBox?: Accessor<string> | null;
	preserveAspectRatio?: Accessor<string> | null;
	style?: Accessor<Style> | null;
	onLayout?: ((e: NeonEvent) => void) | null;
	ref?: RefFn | null;
	children?: NeonNode | null;
}

// A width or height given in points sizes the view; a percentage leaves it to layout.
function pointsOf(value: Accessor<NumberProp> | null): float64 | null {
	if (value === null) { return null; }
	const v = (value as Accessor<NumberProp>)();
	if (typeof v === "string") {
		const text = (v as string).trim();
		if (text.endsWith("%") || text === "") { return null; }
		const n: float64 = parseFloat(text);
		return n === n ? n : null;
	}
	return v as float64;
}

function svgStyle(width: Accessor<NumberProp> | null, height: Accessor<NumberProp> | null, style: Accessor<Style> | null): Style {
	const size: Style = {};
	const w = pointsOf(width);
	const h = pointsOf(height);
	if (w !== null) { size.width = w as float64; }
	if (h !== null) { size.height = h as float64; }
	if (style === null) { return size; }
	return mergeStyle(size, (style as Accessor<Style>)());
}

// The <Svg> host node carries the scene as one `displayList` attr (grammar: encodeScene).
export function Svg(props: SvgProps): NeonNode {
	const sceneAttrs = presentationAttrs(props, []);
	numberAttr(sceneAttrs, "width", props.width);
	numberAttr(sceneAttrs, "height", props.height);
	stringAttr(sceneAttrs, "viewBox", props.viewBox);
	stringAttr(sceneAttrs, "preserveAspectRatio", props.preserveAspectRatio);
	const access: AccessibilityProps = {
		accessible: props.accessible,
		accessibilityLabel: props.accessibilityLabel,
		accessibilityHint: props.accessibilityHint,
		accessibilityRole: props.accessibilityRole,
	};
	const hostAttrs = accessibilityAttrs(access, []);
	const events: VEvent[] = [];
	if (props.onLayout !== null) { events.push(evt("onLayout", props.onLayout as (e: NeonEvent) => void)); }
	const width = props.width;
	const height = props.height;
	const style = props.style;
	const children = props.children;
	const ref = props.ref;
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const node = host.createElement("svg");
		for (const a of hostAttrs) { bindAttr(host, node, a.name, a.dyn); }
		bindStyleAll(host, node, (): Style => svgStyle(width, height, style));
		for (const e of events) { host.addEvent(node, e.name, e.handler); }
		const scene = new SvgScene();
		const inner = sceneHost(scene);
		const root = scene.root as unknown as HostNode;
		scene.held = 1;
		for (const a of sceneAttrs) { bindAttr(inner, root, a.name, a.dyn); }
		if (children !== null) { (children as NeonNode)(inner, root, null); }
		scene.held = 0;
		scene.pending = false;
		let last = "";
		let written = false;
		scene.listener = (): void => {
			const list = encodeScene(scene);
			if (written && list === last) { return; }
			written = true;
			last = list;
			host.setAttr(node, "displayList", list);
		};
		sceneChanged(scene);
		if (ref !== null) { (ref as RefFn)(node); }
		place(host, parent, node, before);
	};
}
