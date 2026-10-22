import { Accessor, untrack } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { onCleanup } from "../../core/cleanup";
import { Host, HostNode, NeonNode, VoidArea } from "../../render/hostTypes";
import { useContext } from "../../render/context";
import { getVoidAreaContext } from "../../render/voidScope";
import { FontId } from "../../../../void/src/void2d/font";
import { Mat4, vec3, determinant3x3 } from "../../../../void/src/math/math3d";
import { Color, rgba } from "../../../../void/src/void2d/types";
import { TextStyle } from "../../../../void/src/void2d/textLayout";
import { setColor, textStyle, setTextStyle } from "../../../../void/src/void2d/node";
import { Anchor, ANCHOR_CENTER } from "../../../../void/src/void3d/billboard";
import { basisOf } from "../../../../void/src/void3d/camera";
import { NodeId3D, Transform3D, addGroup, setLocal, worldOf } from "../../../../void/src/void3d/scene";
import {
	WorldLabel, WorldLabelStyle, plainStyle, setLabelText, setLabelOutline, refreshLabel, faceCamera, closeLabel,
} from "../../../../void/src/void3d/worldLabel";
import {
	NodeProps, SceneState, mountOwned, requireScene, localOf, bindNode, ownNode, mountNodeChildren, viewCamera,
	onBeforeRefresh,
} from "./core";

export interface Text3DProps extends NodeProps {
	text: Accessor<string>;
	size?: Accessor<float32> | null;
	color?: Accessor<Color> | null;
	textStyle?: Accessor<TextStyle> | null;
	outlineWidth?: Accessor<float32> | null;
	outlineColor?: Accessor<Color> | null;
	pixelsPerUnit?: Accessor<float32> | null;
	anchor?: Accessor<Anchor> | null;
	billboard?: Accessor<boolean> | null;
}

const DEFAULT_SIZE: float32 = 16.0;
const DEFAULT_PIXELS_PER_UNIT: float32 = 100.0;

function sizeOf(props: Text3DProps): float32 {
	return props.size === null ? DEFAULT_SIZE : (props.size as () => float32)();
}

function colorOf(props: Text3DProps): Color {
	return props.color === null ? rgba(1.0, 1.0, 1.0, 1.0) : (props.color as () => Color)();
}

function styleLabel(label: WorldLabel, style: TextStyle | null, size: float32, font: FontId): void {
	if (!(size > 0.0)) { throw new Error("Text3D: size must be positive"); }
	const base: TextStyle = style === null ? { ...label.text.textStyle(), font: font } : style as TextStyle;
	label.text.setTextStyle({ ...base, size: size });
	label.stale = true;
}

function colorLabel(label: WorldLabel, color: Color): void {
	label.text.setColor(color);
	label.stale = true;
}

function outlineLabel(label: WorldLabel, width: float32, color: Color): void {
	if (!(width >= 0.0)) { throw new Error("Text3D: outlineWidth must be nonnegative"); }
	when (voidTextOutline) {
		setLabelOutline(label, width, color);
	} else {
		if (width > 0.0) { throw new Error("Text3D: positive outlineWidth requires -d:voidTextOutline"); }
		setLabelOutline(label, width, color);
	}
}

function faceActiveCamera(state: SceneState, label: WorldLabel, group: NodeId3D): void {
	const world = state.handle.scene.worldOf(group);
	if (!world.ok) { throw new Error("Text3D: billboard has no world pose: " + world.error.toString()); }
	const pose: Mat4 = world.value;
	if (pose.determinant3x3() < 0.0) { throw new Error("Text3D: billboard needs ancestors that do not mirror"); }
	const camera = viewCamera(state.handle);
	if (!camera.ok) { throw new Error("Text3D: billboard needs a camera with a world pose: " + camera.error.toString()); }
	faceCamera(label, vec3(pose.m41, pose.m42, pose.m43), camera.value.basisOf());
}

export function Text3D(props: Text3DProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Text3D");
		if ((props.outlineWidth === null) !== (props.outlineColor === null)) {
			throw new Error("Text3D: provide outlineWidth and outlineColor together");
		}
		const area = useContext(getVoidAreaContext());
		if (area === null) { throw new Error("Text3D: the Void area did not provide its frame"); }
		const font = (area as VoidArea).hub.font;
		mountOwned((): void => {
			const state = scope.state;
			const scene = state.handle.scene;
			const local = localOf(props);
			const node = addGroup(scene, scope.parent, local);
			ownNode(state, node);
			let label: WorldLabel | null = null;
			let billboard = false;
			const close = (): void => {
				const open = label;
				if (open !== null) {
					label = null;
					closeLabel(open);
				}
			};
			onCleanup(close);
			createRenderEffect<[float32, Anchor, boolean]>(
				(prev: [float32, Anchor, boolean] | null): [float32, Anchor, boolean] => [
					props.pixelsPerUnit === null ? DEFAULT_PIXELS_PER_UNIT : (props.pixelsPerUnit as () => float32)(),
					props.anchor === null ? ANCHOR_CENTER : (props.anchor as () => Anchor)(),
					props.billboard === null ? false : (props.billboard as () => boolean)(),
				],
				(value: [float32, Anchor, boolean], prev: [float32, Anchor, boolean] | null): Cleanup | null => {
					if (!(value[0] > 0.0)) { throw new Error("Text3D: pixelsPerUnit must be positive"); }
					untrack((): void => {
						const size = sizeOf(props);
						if (!(size > 0.0)) { throw new Error("Text3D: size must be positive"); }
						const made = WorldLabel.create(scene, node, props.text(), {
							...WorldLabelStyle.plainStyle(value[0]), fontSize: size, color: colorOf(props), anchor: value[1],
						});
						if (!made.ok) { throw new Error("Text3D: WorldLabel.create failed: " + made.error.toString()); }
						const next = made.value;
						try {
							styleLabel(next, props.textStyle === null ? null : (props.textStyle as () => TextStyle)(), size, font);
							if (props.outlineWidth !== null) {
								outlineLabel(next, (props.outlineWidth as () => float32)(), (props.outlineColor as () => Color)());
							}
						} catch (error) {
							closeLabel(next);
							throw error;
						}
						close();
						label = next;
					});
					billboard = value[2];
					state.invalidate();
					return null;
				},
			);
			createRenderEffect<string>(
				(prev: string | null): string => props.text(),
				(value: string, prev: string | null): Cleanup | null => {
					const open = label;
					if (prev !== null && open !== null) { setLabelText(open, value); state.invalidate(); }
					return null;
				},
			);
			if (props.size !== null || props.textStyle !== null) {
				createRenderEffect<[TextStyle | null, float32]>(
					(prev: [TextStyle | null, float32] | null): [TextStyle | null, float32] => [
						props.textStyle === null ? null : (props.textStyle as () => TextStyle)(), sizeOf(props),
					],
					(value: [TextStyle | null, float32], prev: [TextStyle | null, float32] | null): Cleanup | null => {
						const open = label;
						if (prev !== null && open !== null) { styleLabel(open, value[0], value[1], font); state.invalidate(); }
						return null;
					},
				);
			}
			if (props.color !== null) {
				createRenderEffect<Color>(
					(prev: Color | null): Color => colorOf(props),
					(value: Color, prev: Color | null): Cleanup | null => {
						const open = label;
						if (prev !== null && open !== null) { colorLabel(open, value); state.invalidate(); }
						return null;
					},
				);
			}
			if (props.outlineWidth !== null) {
				const width = props.outlineWidth as () => float32;
				const color = props.outlineColor as () => Color;
				createRenderEffect<[float32, Color]>(
					(prev: [float32, Color] | null): [float32, Color] => [width(), color()],
					(value: [float32, Color], prev: [float32, Color] | null): Cleanup | null => {
						const open = label;
						if (prev !== null && open !== null) { outlineLabel(open, value[0], value[1]); state.invalidate(); }
						return null;
					},
				);
			}
			onBeforeRefresh(state, (): void => {
				const open = label;
				if (open === null) { return; }
				if (billboard) { faceActiveCamera(state, open, node); }
				if (refreshLabel(open) && !billboard) {
					setLocal(scene, open.node, {
						...Transform3D.identity(),
						scale: vec3((open.width as float32) / open.pixelsPerUnit, (open.height as float32) / open.pixelsPerUnit, 1.0),
					});
				}
			});
			bindNode(state, node, props, local);
			mountNodeChildren(scope, node, props, host, parent, before);
		});
	};
}
