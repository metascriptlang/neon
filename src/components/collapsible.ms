// react-native-collapsible's Collapsible and Accordion, and Flutter material/expansion_tile.dart
// over them. The content is measured at its natural height and the outer box animates
// between the collapsed height and that measurement (Flutter: ClipRect with an animated
// heightFactor); once open and at rest the box lets the content size itself again.

import { Accessor, accessor, createSignal, untrack } from "../core/signal";
import { createEffect } from "../core/effect";
import { onCleanup } from "../core/cleanup";
import { For } from "../macros/ui/flow";
import { element } from "../macros/ui/element";
import { NeonNode, VAttr, dynAttr, evt, hostElement } from "../render/node";
import { NeonEvent } from "../render/event";
import { Style, mergeStyle } from "../render/style";
import { Text, View } from "./primitives";
import { MATERIAL_ON_SURFACE, MATERIAL_PRIMARY, colorOr, stateAttr } from "./material";
import { Animated, AnimatedValue, CompositeAnimation, Easing, EasingFunction, EndResult } from "../animation/index";

// react-native-collapsible: duration 300 ms; Flutter ExpansionTile: 200 ms, Curves.easeIn
// for the size and the icon's half turn.
const COLLAPSIBLE_MS = 300;
const EXPANSION_MS = 200;
const TILE_MIN_HEIGHT = 56;

export function Collapsible(props: {
	collapsed: Accessor<boolean>;
	children?: NeonNode | null;
	duration?: Accessor<number> | null;
	easing?: EasingFunction | null;
	collapsedHeight?: Accessor<number> | null;
	progress?: AnimatedValue | null;
	onAnimationEnd?: (() => void) | null;
	style?: Accessor<Style> | null;
}): NeonNode {
	const collapsed = props.collapsed;
	const durationProp = props.duration;
	const easingProp = props.easing;
	const heightProp = props.collapsedHeight;
	const onAnimationEnd = props.onAnimationEnd;
	const given = props.progress;
	const startOpen = !untrack<boolean>(collapsed);
	const progress = given === null ? new AnimatedValue(startOpen ? 1 : 0) : given as AnimatedValue;
	progress.setValue(startOpen ? 1 : 0);
	const [measured, setMeasured] = createSignal<number>(0);
	const [moving, setMoving] = createSignal<boolean>(false);
	const [open, setOpen] = createSignal<boolean>(startOpen);
	let motion: CompositeAnimation | null = null;
	let waiting = false;
	const floor = (): number => heightProp === null ? 0 : (heightProp as Accessor<number>)();

	const stop = (): void => {
		if (motion !== null) {
			(motion as CompositeAnimation).stop();
			motion = null;
		}
	};
	onCleanup(stop);
	const run = (to: number): void => {
		stop();
		waiting = false;
		const duration = durationProp === null ? COLLAPSIBLE_MS : (durationProp as Accessor<number>)();
		const easing = easingProp === null ? Easing.out(Easing.cubic) : easingProp as EasingFunction;
		const anim = Animated.timing(progress, { toValue: to, duration, easing });
		motion = anim;
		anim.start((result: EndResult): void => {
			if (motion === anim) { motion = null; }
			if (!result.finished) { return; }
			setMoving(false);
			if (to === 0) { setOpen(false); }
			if (onAnimationEnd !== null) { (onAnimationEnd as () => void)(); }
		});
	};
	let first = true;
	createEffect((): void => {
		const closing = collapsed();
		if (first) {
			first = false;
			return;
		}
		untrack<number>((): number => {
			setMoving(true);
			if (closing) {
				run(0);
			} else {
				setOpen(true);
				if (measured() > 0) { run(1); } else { waiting = true; }
			}
			return 0;
		});
	});

	const outer = accessor((): Style => {
		const user = props.style;
		const base: Style = { overflow: "hidden" };
		const merged = user === null ? base : mergeStyle(base, (user as Accessor<Style>)());
		if (open() && !moving()) { return merged; }
		const low = floor();
		const high = Math.max(low, measured());
		return { ...merged, height: low + (high - low) * progress.get() };
	});
	const inner = accessor((): Style => {
		const hidden = !open() && !moving() && floor() <= 0;
		return { flexShrink: 0, display: hidden ? "none" : "flex" };
	});
	const layout = (e: NeonEvent): void => {
		if (e.height === untrack<number>(measured)) { return; }
		setMeasured(e.height);
		if (waiting && e.height > 0) { run(1); }
	};
	return View({ style: outer, children: View({ style: inner, onLayout: layout, children: props.children }) });
}

export function ExpansionTile(props: {
	title: Accessor<string>;
	subtitle?: Accessor<string> | null;
	leading?: NeonNode | null;
	trailing?: NeonNode | null;
	children?: NeonNode | null;
	initiallyExpanded?: Accessor<boolean> | null;
	expanded?: Accessor<boolean> | null;
	onExpansionChanged?: ((expanded: boolean) => void) | null;
	textColor?: Accessor<string> | null;
	collapsedTextColor?: Accessor<string> | null;
	iconColor?: Accessor<string> | null;
	backgroundColor?: Accessor<string> | null;
	collapsedBackgroundColor?: Accessor<string> | null;
	childrenPadding?: Accessor<number> | null;
	duration?: Accessor<number> | null;
	style?: Accessor<Style> | null;
}): NeonNode {
	const { title, onExpansionChanged } = props;
	const subtitle = props.subtitle;
	const controlled = props.expanded;
	const initialProp = props.initiallyExpanded;
	const textProp = props.textColor;
	const collapsedTextProp = props.collapsedTextColor;
	const iconProp = props.iconColor;
	const backgroundProp = props.backgroundColor;
	const collapsedBackgroundProp = props.collapsedBackgroundColor;
	const paddingProp = props.childrenPadding;
	const durationProp = props.duration;
	const startOpen = controlled !== null ? untrack<boolean>(controlled as Accessor<boolean>) : (initialProp !== null && untrack<boolean>(initialProp as Accessor<boolean>));
	const [inner, setInner] = createSignal<boolean>(startOpen);
	const expanded = (): boolean => controlled === null ? inner() : (controlled as Accessor<boolean>)();
	const turns = new AnimatedValue(startOpen ? 1 : 0);

	const toggle = (e: NeonEvent): void => {
		const next = !untrack<boolean>(expanded);
		if (controlled === null) { setInner(next); }
		if (onExpansionChanged !== null) { (onExpansionChanged as (x: boolean) => void)(next); }
	};
	const ink = (): string => expanded() ? colorOr(textProp, MATERIAL_PRIMARY) : colorOr(collapsedTextProp, MATERIAL_ON_SURFACE);
	const titleStyle = accessor((): Style => ({ fontSize: 16, color: ink() }));
	const subtitleStyle = accessor((): Style => ({ fontSize: 14, color: "#757575" }));
	const iconStyle = accessor((): Style => ({
		fontSize: 18,
		color: expanded() ? colorOr(iconProp, MATERIAL_PRIMARY) : colorOr(iconProp, "#757575"),
		transform: `rotate(${turns.get() * 180}deg)`,
	}));
	const trailing: NeonNode = props.trailing === null ? element(<Text style={iconStyle}>▾</Text>) : props.trailing as NeonNode;
	const leading = props.leading;
	const texts: NeonNode = subtitle === null
		? element(<View style={{ flex: 1 }}><Text style={titleStyle}>{title()}</Text></View>)
		: element(<View style={{ flex: 1 }}>
			<Text style={titleStyle}>{title()}</Text>
			<Text style={subtitleStyle}>{(subtitle as Accessor<string>)()}</Text>
		</View>);
	const leadingBox: NeonNode = leading === null ? View({}) : View({ style: accessor((): Style => ({ marginRight: 16 })), children: leading });
	const headerStyle = (): Style => ({
		flexDirection: "row", alignItems: "center", minHeight: TILE_MIN_HEIGHT, paddingLeft: 16, paddingRight: 16,
	});
	const attrs: VAttr[] = [];
	attrs.push(dynAttr("accessibilityRole", (): string | null => "button"));
	attrs.push(dynAttr("accessibilityLabel", (): string | null => title()));
	stateAttr(attrs, (): string => expanded() ? "expanded" : "collapsed");
	const headerKids: NeonNode = element(<>{leadingBox}{texts}{trailing}</>);
	const header = hostElement("pressable", attrs, [evt("onPress", toggle)], headerKids, headerStyle, null);
	const body = Collapsible({
		collapsed: accessor((): boolean => !expanded()),
		duration: accessor((): number => durationProp === null ? EXPANSION_MS : (durationProp as Accessor<number>)()),
		easing: Easing.ease,
		progress: turns,
		children: View({
			style: accessor((): Style => paddingProp === null ? {} : { padding: (paddingProp as Accessor<number>)() }),
			children: props.children,
		}),
	});
	const userStyle = props.style;
	const outer = accessor((): Style => {
		const fill = expanded() ? backgroundProp : collapsedBackgroundProp;
		const base: Style = fill === null ? {} : { backgroundColor: (fill as Accessor<string>)() };
		return userStyle === null ? base : mergeStyle(base, (userStyle as Accessor<Style>)());
	});
	return View({ style: outer, children: element(<>{header}{body}</>) });
}

export function Accordion<T>(props: {
	sections: Accessor<T[]>;
	activeSections: Accessor<number[]>;
	renderHeader: (section: T, index: number, isActive: Accessor<boolean>) => NeonNode;
	renderContent: (section: T, index: number, isActive: Accessor<boolean>) => NeonNode;
	onChange: (activeSections: number[]) => void;
	expandMultiple?: Accessor<boolean> | null;
	duration?: Accessor<number> | null;
	easing?: EasingFunction | null;
	renderSectionTitle?: ((section: T, index: number, isActive: Accessor<boolean>) => NeonNode) | null;
	sectionContainerStyle?: Accessor<Style> | null;
	style?: Accessor<Style> | null;
}): NeonNode {
	const { sections, activeSections, renderHeader, renderContent, onChange } = props;
	const multipleProp = props.expandMultiple;
	const titleRender = props.renderSectionTitle;
	const containerProp = props.sectionContainerStyle;
	const isActive = (index: number): boolean => activeSections().indexOf(index) >= 0;
	// react-native-collapsible Accordion._toggleSection.
	const toggle = (index: number): void => {
		const current = untrack<number[]>(activeSections);
		const multiple = multipleProp !== null && untrack<boolean>(multipleProp as Accessor<boolean>);
		const next: number[] = [];
		const found = current.indexOf(index) >= 0;
		if (multiple) {
			for (const at of current) {
				if (at !== index) { next.push(at); }
			}
			if (!found) { next.push(index); }
		} else if (!found) {
			next.push(index);
		}
		onChange(next);
	};
	const section = (item: T, at: Accessor<number>): NeonNode => {
		const index = untrack<number>(at);
		const active = accessor((): boolean => isActive(at()));
		const attrs: VAttr[] = [];
		attrs.push(dynAttr("accessibilityRole", (): string | null => "button"));
		stateAttr(attrs, (): string => active() ? "expanded" : "collapsed");
		const header = hostElement("pressable", attrs, [evt("onPress", (e: NeonEvent): void => { toggle(at()); })], renderHeader(item, index, active), (): Style => ({}), null);
		const body = Collapsible({
			collapsed: accessor((): boolean => !active()),
			duration: props.duration,
			easing: props.easing,
			children: renderContent(item, index, active),
		});
		const title: NeonNode = titleRender === null ? View({}) : (titleRender as (s: T, i: number, a: Accessor<boolean>) => NeonNode)(item, index, active);
		return View({
			style: accessor((): Style => containerProp === null ? {} : (containerProp as Accessor<Style>)()),
			children: element(<>{title}{header}{body}</>),
		});
	};
	return View({ style: props.style, children: For<T>({ each: sections, children: section }) });
}
