import { Accessor, accessor } from "../core/signal";
import { createEffect } from "../core/effect";
import { createRoot } from "../core/owner";
import { onCleanup } from "../core/cleanup";
import { createContext, useContext } from "../render/context";
import { VoidSpace, voidScope } from "../render/voidScope";
import { Host, HostNode, NeonNode } from "../render/hostTypes";
import {
	Scene2D as VoidScene2D,
	NodeRef,
	Local2D,
	Paint2D,
	Order2D,
	group,
	rect,
	sprite,
	mask,
	label,
	refOf,
	addChild,
	isLive,
	dispose,
	setLocal,
	setPaint,
	paint,
	NO_COLOR_MATRIX_ROW,
	setColorMatrix,
	setOrder,
	setFilter,
	setSize,
	setColor,
	setTile,
	setText,
	textStyle,
	setTextStyle,
} from "../../../void/src/void2d/node";
import { create, close, setScaleMode } from "../../../void/src/void2d/scene";
import { Color, Camera, Tile, Filter, ScaleMode, rgba } from "../../../void/src/void2d/types";
import { TextStyle } from "../../../void/src/void2d/textLayout";
import { Mat4 } from "../../../void/src/math/math3d";

interface Scene2DProps {
	clear?: Accessor<Color> | null;
	camera?: Accessor<Camera> | null;
	smooth?: Accessor<boolean> | null;
	scaleMode?: Accessor<ScaleMode> | null;
	designW?: Accessor<float32> | null;
	designH?: Accessor<float32> | null;
	ref?: ((scene: VoidScene2D) => void) | null;
	children?: NeonNode | null;
}

interface NodeProps {
	local?: Accessor<Local2D> | null;
	paint?: Accessor<Paint2D> | null;
	colorMatrix?: Accessor<Mat4> | null;
	order?: Accessor<Order2D> | null;
	filter?: Accessor<Filter> | null;
	ref?: ((node: NodeRef) => void) | null;
	children?: NeonNode | null;
}

interface RectProps extends NodeProps {
	width: Accessor<float32>;
	height: Accessor<float32>;
	color: Accessor<Color>;
}

interface SpriteProps extends NodeProps {
	tile: Accessor<Tile>;
}

interface MaskProps extends NodeProps {
	width: Accessor<float32>;
	height: Accessor<float32>;
}

interface LabelProps extends NodeProps {
	text: Accessor<string>;
	size: Accessor<float32>;
	color: Accessor<Color>;
	textStyle?: Accessor<TextStyle> | null;
}

const sceneScope = createContext<NodeRef | null>(null);

function mountOwned(body: () => void): void {
	const dispose = createRoot((dispose) => {
		try { body(); } catch (error) {
			dispose();
			throw error;
		}
		return dispose;
	});
	onCleanup(dispose);
}

function requireScene(tag: string): NodeRef {
	if (useContext(voidScope) !== VoidSpace.Scene2D) {
		throw new Error(tag + ": mount inside Scene2D within Void");
	}
	const under = useContext(sceneScope);
	if (under === null) { throw new Error(tag + ": mount inside Scene2D within Void"); }
	return under;
}

function bindNode(tag: string, node: NodeRef, props: NodeProps): void {
	if (props.local !== null) {
		const local = props.local as () => Local2D;
		createEffect((): void => { node.setLocal(local()); });
	}
	if (props.paint !== null) {
		const readPaint = props.paint as () => Paint2D;
		createEffect((): void => {
			const value = readPaint();
			const row = node.paint().colorMatrixRow;
			if (value.colorMatrixRow !== NO_COLOR_MATRIX_ROW && value.colorMatrixRow !== row) {
				throw new Error(tag + ": paint cannot move a colorMatrixRow; use colorMatrix");
			}
			node.setPaint({ ...value, colorMatrixRow: row });
		});
	}
	if (props.colorMatrix !== null) {
		const matrix = props.colorMatrix as () => Mat4;
		createEffect((): void => { node.setColorMatrix(matrix()); });
	}
	if (props.order !== null) {
		const order = props.order as () => Order2D;
		createEffect((): void => { node.setOrder(order()); });
	}
	if (props.filter !== null) {
		const filter = props.filter as () => Filter;
		createEffect((): void => { node.setFilter(filter()); });
	}
}

function renderNode(
	tag: string,
	props: NodeProps,
	make: (scene: VoidScene2D) => NodeRef,
	bind: (node: NodeRef) => void,
): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const under = requireScene(tag);
		mountOwned((): void => {
			const scene = under.scene;
			const node = make(scene);
			onCleanup((): void => { if (node.isLive()) { node.dispose(); } });
			under.addChild(node);
			bind(node);
			bindNode(tag, node, props);
			if (props.ref !== null) { (props.ref as (node: NodeRef) => void)(node); }
			const children = props.children;
			if (children !== null) {
				sceneScope.Provider({ value: accessor(() => node), children: children })(
					host, parent, before,
				);
			}
		});
	};
}

export function Scene2D(props: Scene2DProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		if (useContext(voidScope) !== VoidSpace.Area) {
			throw new Error("Scene2D: mount directly within Void, outside another scene");
		}
		mountOwned((): void => {
			const scene = VoidScene2D.create(rgba(0.0, 0.0, 0.0, 0.0));
			onCleanup((): void => { scene.close(); });
			if (props.clear !== null) {
				const clear = props.clear as () => Color;
				createEffect((): void => { scene.clear = clear(); });
			}
			if (props.camera !== null) {
				const camera = props.camera as () => Camera;
				createEffect((): void => { scene.cam = camera(); });
			}
			if (props.smooth !== null) {
				const smooth = props.smooth as () => boolean;
				createEffect((): void => { scene.defaultSmooth = smooth(); });
			}
			if (props.scaleMode !== null || props.designW !== null || props.designH !== null) {
				createEffect((): void => {
					const mode: ScaleMode = props.scaleMode === null ? ScaleMode.Resize :
						(props.scaleMode as () => ScaleMode)();
					const width: float32 = props.designW === null ? 0.0 :
						(props.designW as () => float32)();
					const height: float32 = props.designH === null ? 0.0 :
						(props.designH as () => float32)();
					scene.setScaleMode(mode, width, height);
				});
			}
			if (props.ref !== null) { (props.ref as (scene: VoidScene2D) => void)(scene); }
			const children = props.children;
			if (children !== null) {
				const root = scene.refOf(scene.root);
				const sceneHost: Host = {
					...host,
					createText: (text: string): HostNode => {
						if (text !== "") { throw new Error("Scene2D: raw text requires Label"); }
						return host.createText(text);
					},
					setText: (node: HostNode, text: string): void => {
						if (text !== "") { throw new Error("Scene2D: raw text requires Label"); }
						host.setText(node, text);
					},
					createElement: (tag: string): HostNode => {
						throw new Error("Scene2D: host element <" + tag + "> needs its UI host");
					},
				};
				voidScope.Provider({
					value: accessor(() => VoidSpace.Scene2D),
					children: sceneScope.Provider({
						value: accessor(() => root), children: children,
					}),
				})(sceneHost, parent, before);
			}
		});
	};
}

export function Group(props: NodeProps): NeonNode {
	return renderNode("Group", props, (scene: VoidScene2D): NodeRef => scene.group(),
		(node: NodeRef): void => {});
}

export function Rect(props: RectProps): NeonNode {
	return renderNode("Rect", props,
		(scene: VoidScene2D): NodeRef => scene.rect(props.width(), props.height(), props.color()),
		(node: NodeRef): void => {
			createEffect((): void => { node.setSize(props.width(), props.height()); });
			if (props.paint === null) {
				createEffect((): void => { node.setColor(props.color()); });
			}
		});
}

export function Sprite(props: SpriteProps): NeonNode {
	return renderNode("Sprite", props, (scene: VoidScene2D): NodeRef => scene.sprite(props.tile()),
		(node: NodeRef): void => {
			createEffect((): void => {
				const tile = props.tile();
				node.setTile(tile).setSize(tile.w, tile.h);
			});
		});
}

export function Mask(props: MaskProps): NeonNode {
	return renderNode("Mask", props,
		(scene: VoidScene2D): NodeRef => scene.mask(props.width(), props.height()),
		(node: NodeRef): void => {
			createEffect((): void => { node.setSize(props.width(), props.height()); });
		});
}

export function Label(props: LabelProps): NeonNode {
	return renderNode("Label", props,
		(scene: VoidScene2D): NodeRef => scene.label(props.text(), props.size(), props.color()),
		(node: NodeRef): void => {
			createEffect((): void => { node.setText(props.text()); });
			if (props.paint === null) {
				createEffect((): void => { node.setColor(props.color()); });
			}
			createEffect((): void => {
				const style = props.textStyle === null ? node.textStyle() :
					(props.textStyle as () => TextStyle)();
				node.setTextStyle({ ...style, size: props.size() });
			});
		});
}
