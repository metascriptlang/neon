import { NeonEvent } from "../render/event";
import { Style } from "../render/style";
import { Accessor, accessor } from "../core/signal";
import { element } from "../macros/ui/element";
import { NeonNode } from "../render/node";
import { Pressable, Text } from "./primitives";

interface ButtonProps {
	title: Accessor<string>;
	onPress?: ((e: NeonEvent) => void) | null;
	color?: Accessor<string> | null;
	disabled?: Accessor<boolean> | null;
	accessibilityLabel?: Accessor<string> | null;
	accessibilityHint?: Accessor<string> | null;
}

// RN Libraries/Components/Button.js styles: iOS draws a text-only button,
// Android (and every other platform here) the Material raised button.
when (ios) {
	function buttonBox(tint: string, disabled: boolean): Style {
		return { alignItems: "center", justifyContent: "center" };
	}
	function buttonLabel(tint: string, disabled: boolean): Style {
		return { color: disabled ? "#cdcdcd" : tint, fontSize: 18, textAlign: "center", margin: 8 };
	}
	function buttonTitle(title: string): string { return title; }
	function defaultTint(): string { return "#007AFF"; }
} else {
	function buttonBox(tint: string, disabled: boolean): Style {
		return {
			backgroundColor: disabled ? "#dfdfdf" : tint,
			borderRadius: 2,
			alignItems: "center", justifyContent: "center",
		};
	}
	function buttonLabel(tint: string, disabled: boolean): Style {
		return { color: disabled ? "#a1a1a1" : "#ffffff", fontWeight: "bold", textAlign: "center", margin: 8 };
	}
	function buttonTitle(title: string): string { return title.toUpperCase(); }
	function defaultTint(): string { return "#2196F3"; }
}

export function Button(props: ButtonProps): NeonNode {
	const { onPress, color, disabled } = props;
	const isDisabled = (): boolean => disabled !== null && (disabled as Accessor<boolean>)();
	const tint = (): string => color === null ? defaultTint() : (color as Accessor<string>)();
	const box = accessor((): Style => buttonBox(tint(), isDisabled()));
	const label = accessor((): Style => buttonLabel(tint(), isDisabled()));
	const press = (e: NeonEvent): void => {
		if (isDisabled() || onPress === null) { return; }
		(onPress as (x: NeonEvent) => void)(e);
	};
	const title = props.title;
	const a11y = props.accessibilityLabel === null ? title : props.accessibilityLabel as Accessor<string>;
	const hintProp = props.accessibilityHint;
	const hint = accessor((): string => hintProp === null ? "" : (hintProp as Accessor<string>)());
	return element(<Pressable style={box} onPress={press} accessibilityRole="button" accessibilityLabel={a11y()} accessibilityHint={hint()}>
		<Text style={label}>{buttonTitle(title())}</Text>
	</Pressable>);
}
