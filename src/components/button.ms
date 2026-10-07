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

const ACCENT = "#2196f3";

export function Button(props: ButtonProps): NeonNode {
	const { onPress, color, disabled } = props;
	const isDisabled = (): boolean => disabled !== null && (disabled as Accessor<boolean>)();
	const tint = (): string => color === null ? ACCENT : (color as Accessor<string>)();
	const box = accessor((): Style => ({
		backgroundColor: isDisabled() ? "#dfdfdf" : tint(),
		borderRadius: 4,
		paddingTop: 10, paddingBottom: 10, paddingLeft: 16, paddingRight: 16,
		alignItems: "center", justifyContent: "center",
	}));
	const label = accessor((): Style => ({ color: isDisabled() ? "#a1a1a1" : "#ffffff", fontSize: 16, fontWeight: "bold" }));
	const press = (e: NeonEvent): void => {
		if (isDisabled() || onPress === null) { return; }
		(onPress as (x: NeonEvent) => void)(e);
	};
	const title = props.title;
	const a11y = props.accessibilityLabel === null ? title : props.accessibilityLabel as Accessor<string>;
	const hintProp = props.accessibilityHint;
	const hint = accessor((): string => hintProp === null ? "" : (hintProp as Accessor<string>)());
	return element(<Pressable style={box} onPress={press} accessibilityRole="button" accessibilityLabel={a11y()} accessibilityHint={hint()}>
		<Text style={label}>{title().toUpperCase()}</Text>
	</Pressable>);
}
