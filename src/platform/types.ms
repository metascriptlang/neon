// Platform Types
// Cross-platform abstractions for UI elements

export interface Element {
	tag: string;
	props: Record<string, unknown>;
	children: Element[];
}

export type Component<Props = {}> = (props: Props) => Element;

// Style types
export interface ViewStyle {
	width?: number | string;
	height?: number | string;
	padding?: number;
	margin?: number;
	backgroundColor?: string;
	flexDirection?: "row" | "column";
	alignItems?: "center" | "flex-start" | "flex-end";
	justifyContent?: "center" | "flex-start" | "flex-end" | "space-between";
}

export interface TextStyle {
	color?: string;
	fontSize?: number;
	fontWeight?: "normal" | "bold";
}
