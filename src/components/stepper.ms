// Flutter's vertical Stepper: numbered circles joined by a line, the active step's body with its
// Continue and Cancel controls, and a check mark on every step before the current one.

import { NeonEvent } from "../render/event";
import { Style, layerStyles } from "../render/style";
import { Accessor, accessor } from "../core/signal";
import { element } from "../macros/ui/element";
import { Index, Show } from "../macros/ui/flow";
import { NeonNode } from "../render/node";
import { Host, HostNode } from "../render/hostTypes";
import { Pressable, Text, View } from "./primitives";
import { MATERIAL_ON_PRIMARY, MATERIAL_ON_SURFACE, MATERIAL_PRIMARY, colorOr } from "./material";
import { DialogAction } from "./dialog";

export interface StepItem {
	title: string;
	subtitle?: string | null;
}

interface StepperProps {
	steps: Accessor<StepItem[]>;
	currentStep: Accessor<int32>;
	renderContent?: ((index: int32) => NeonNode) | null;
	onStepTapped?: ((index: int32) => void) | null;
	onStepContinue?: (() => void) | null;
	onStepCancel?: (() => void) | null;
	continueLabel?: Accessor<string> | null;
	cancelLabel?: Accessor<string> | null;
	color?: Accessor<string> | null;
	style?: Accessor<Style> | null;
}

// Flutter Stepper: a 24-point circle, black38 while inactive, the line 24 points from the
// edge and at least 24 points long between two steps.
const STEP_INACTIVE = "#9e9e9e";
const STEP_LINE = "#bdbdbd";

const STEPPER: Style = { flexDirection: "column" };
const STEP_HEADER: Style = {
	flexDirection: "row",
	alignItems: "center",
	gap: 12,
	paddingTop: 8,
	paddingBottom: 8,
	paddingLeft: 12,
	paddingRight: 12,
};
const STEP_NUMBER: Style = { color: MATERIAL_ON_PRIMARY, fontSize: 12 };
const STEP_TITLES: Style = { flexDirection: "column", flexShrink: 1 };
const STEP_SUBTITLE: Style = { color: "#757575", fontSize: 12 };
const STEP_BODY_ROW: Style = { flexDirection: "row", marginLeft: 23, minHeight: 24 };
const STEP_BODY: Style = {
	flex: 1,
	flexDirection: "column",
	paddingLeft: 24,
	paddingRight: 12,
	gap: 16,
};
const STEP_CONTROLS: Style = {
	flexDirection: "row",
	alignItems: "center",
	gap: 8,
	paddingBottom: 16,
};
const STEP_CONTINUE: Style = {
	minHeight: 40,
	justifyContent: "center",
	paddingLeft: 24,
	paddingRight: 24,
	borderRadius: 20,
};

function stepNumberText(index: int32, current: int32): string {
	return index < current ? "✓" : (index + 1).toString();
}

export function Stepper(props: StepperProps): NeonNode {
	const { steps, currentStep, renderContent, onStepTapped, onStepContinue, onStepCancel } = props;
	const { continueLabel, cancelLabel, color } = props;
	const userStyle = props.style;
	const accent = (): string => colorOr(color, MATERIAL_PRIMARY);
	const continueText = accessor((): string => continueLabel === null
		? "Continue"
		: (continueLabel as Accessor<string>)());
	const cancelText = accessor((): string => cancelLabel === null
		? "Cancel"
		: (cancelLabel as Accessor<string>)());
	const root = accessor((): Style => userStyle === null
		? STEPPER
		: layerStyles([STEPPER, (userStyle as Accessor<Style>)()]));
	const continuePress = (e: NeonEvent): void => {
		if (onStepContinue !== null) { (onStepContinue as () => void)(); }
	};
	const cancelPress = (): void => {
		if (onStepCancel !== null) { (onStepCancel as () => void)(); }
	};
	const continueBox = accessor((): Style => ({ ...STEP_CONTINUE, backgroundColor: accent() }));
	const continueLabelStyle: Style = {
		color: MATERIAL_ON_PRIMARY,
		fontSize: 14,
		fontWeight: "bold",
	};
	const controls = element(<View style={STEP_CONTROLS}>
		<Pressable style={continueBox} onPress={continuePress}
			accessibilityRole="button" accessibilityLabel={continueText()}>
			<Text style={continueLabelStyle}>{continueText()}</Text>
		</Pressable>
		<DialogAction label={cancelText()} color={MATERIAL_ON_SURFACE} onPress={cancelPress} />
	</View>);

	const step = (item: Accessor<StepItem>, at: number): NeonNode => {
		const index = at as int32;
		const isLast = (): boolean => index === (steps().length as int32) - 1;
		const reached = (): boolean => index <= currentStep();
		const subtitle = (): string => {
			const s = item().subtitle;
			return s === null ? "" : s as string;
		};
		const label = accessor((): string => {
			const done = index < currentStep() ? ", completed" : "";
			const total = steps().length.toString();
			return `${item().title}, step ${(index + 1).toString()} of ${total}${done}`;
		});
		const circle = accessor((): Style => ({
			width: 24,
			height: 24,
			borderRadius: 12,
			alignItems: "center",
			justifyContent: "center",
			backgroundColor: reached() ? accent() : STEP_INACTIVE,
		}));
		const title = accessor((): Style => ({
			color: MATERIAL_ON_SURFACE,
			fontSize: 14,
			fontWeight: index === currentStep() ? "bold" : "normal",
		}));
		const line = accessor((): Style => ({
			width: isLast() ? 0 : 1,
			backgroundColor: STEP_LINE,
		}));
		const tap = (e: NeonEvent): void => {
			if (onStepTapped !== null) { (onStepTapped as (i: int32) => void)(index); }
		};
		const content: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
			if (renderContent === null) { return; }
			(renderContent as (i: int32) => NeonNode)(index)(host, parent, before);
		};
		return element(<View>
			<Pressable style={STEP_HEADER} onPress={tap}
				accessibilityRole="button" accessibilityLabel={label()}>
				<View style={circle}>
					<Text style={STEP_NUMBER}>{stepNumberText(index, currentStep())}</Text>
				</View>
				<View style={STEP_TITLES}>
					<Text style={title}>{item().title}</Text>
					<Show when={subtitle() !== ""}>
						<Text style={STEP_SUBTITLE}>{subtitle()}</Text>
					</Show>
				</View>
			</Pressable>
			<View style={STEP_BODY_ROW}>
				<View style={line} />
				<View style={STEP_BODY}>
					<Show when={index === currentStep()}>
						{content}
						{controls}
					</Show>
				</View>
			</View>
		</View>);
	};
	const list = Index<StepItem>({ each: steps, children: step, fallback: null });
	return element(<View style={root}>{list}</View>);
}
