import { Accessor, accessor } from "../core/signal";
import { NeonNode } from "../render/hostTypes";
import { NeonEvent } from "../render/event";
import { Style } from "../render/style";
import { Pressable, Text } from "../components/primitives";
import { useLinkTo } from "./core";

export function Link(props: {
	to: Accessor<string>;
	children?: NeonNode | null;
	style?: Accessor<Style> | null;
	accessibilityLabel?: Accessor<string> | null;
}): NeonNode {
	const linkTo = useLinkTo();
	const to = props.to;
	const own = props.style;
	const style = accessor((): Style => own === null ? {} : (own as Accessor<Style>)());
	const label = props.accessibilityLabel;
	const name = accessor((): string => label === null ? to() : (label as Accessor<string>)());
	const children = props.children;
	const body: NeonNode = children === null ? <Text>{to()}</Text> : children as NeonNode;
	const press = (e: NeonEvent): void => { linkTo(to()); };
	return <Pressable style={style} accessibilityRole="link" accessibilityLabel={name()}
		onPress={press}>
		{body}
	</Pressable>;
}
