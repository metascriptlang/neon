import { Accessor, accessor } from "../core/signal";
import { createRenderEffect } from "../core/effect";
import { Cleanup } from "../core/types";
import { createRoot } from "../core/owner";
import { onCleanup } from "../core/cleanup";
import { createContext, useContext } from "../render/context";
import { VoidSpace, voidScope } from "../render/voidScope";
import { Host, HostNode, NeonNode } from "../render/hostTypes";
import { place } from "../render/reconcile";
import { createVoidHostWith, VoidHost, VoidNode, freeVoidLayoutTree } from "../platform/void/host";
import { DEFAULT_FONT } from "../../../void/src/void2d/font";
import {
	Scene2D as VoidScene2D,
	NodeRef,
	Local2D,
	Paint2D,
	Order2D,
	TileCell,
	ALL_TILES,
	tileGroup,
	setTiles,
	setRange,
	scaleGrid,
	underline,
	selection,
	content,
	setContent,
	group,
	rect,
	sprite,
	mask,
	label,
	isLive,
	dispose,
	setLocal,
	setPaint,
	paint,
	NO_COLOR_MATRIX_ROW,
	setColorMatrix,
	setOrder,
	setFilter,
	setSize, content, setBackground, clearBackground,
	setBoxStyle,
	setImageStyle,
	setScrollBounds,
	scrollTo,
	setColor,
	setTile,
	setText,
	textStyle,
	setTextStyle, setTextRuns, setShapingBreaks, setTruncate, setHangingIndent, setForceWidth,
	SelectionRange, setSelectionRange, setCursorIndex, setCursorBlinkTime,
} from "../../../void/src/void2d/node";
import { create, close, setScaleMode } from "../../../void/src/void2d/scene";
import {
	Color, Camera, Tile, Filter, ScaleMode, Bounds2D, rgba,
} from "../../../void/src/void2d/types";
import { TextStyle, TextRun, Truncate } from "../../../void/src/void2d/textLayout";
import { Mat4 } from "../../../void/src/math/math3d";
import { BoxStyle } from "../../../void/src/void2d/boxStyle";
import { ImageStyle } from "../../../void/src/void2d/imageStyle";
import { graphics } from "../../../void/src/void2d/node";
import { GraphicsOp, replayGraphics } from "../render/graphics";

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

interface GraphicsProps extends NodeProps {
	operations: Accessor<GraphicsOp[]>;
}

interface GroupProps extends NodeProps {
	width?: Accessor<float32> | null;
	height?: Accessor<float32> | null;
	background?: Accessor<Color | null> | null;
}

interface RectProps extends NodeProps {
	width: Accessor<float32>;
	height: Accessor<float32>;
	color: Accessor<Color>;
	boxStyle?: Accessor<BoxStyle> | null;
}

interface SpriteProps extends NodeProps {
	tile: Accessor<Tile>;
	width?: Accessor<float32> | null;
	height?: Accessor<float32> | null;
	imageStyle?: Accessor<ImageStyle> | null;
}

interface ScaleGridProps extends NodeProps {
	tile: Accessor<Tile>;
	width?: Accessor<float32> | null;
	height?: Accessor<float32> | null;
	borderL: Accessor<float32>;
	borderT: Accessor<float32>;
	borderR: Accessor<float32>;
	borderB: Accessor<float32>;
}

interface UnderlineProps extends NodeProps {
	width: Accessor<float32>;
	thickness: Accessor<float32>;
	wavy: Accessor<boolean>;
	color: Accessor<Color>;
}

interface SelectionProps extends NodeProps {
	width: Accessor<float32>;
	height: Accessor<float32>;
	color: Accessor<Color>;
	prevOffsetX: Accessor<float32>;
	prevWidth: Accessor<float32>;
	nextOffsetX: Accessor<float32>;
	nextWidth: Accessor<float32>;
}

interface TileGroupProps extends NodeProps {
	cells: Accessor<TileCell[]>;
	first?: Accessor<int32> | null;
	count?: Accessor<int32> | null;
}

interface MaskProps extends NodeProps {
	width: Accessor<float32>;
	height: Accessor<float32>;
	scrollX?: Accessor<float32> | null;
	scrollY?: Accessor<float32> | null;
	scrollBounds?: Accessor<Bounds2D | null> | null;
}

interface LabelProps extends NodeProps {
	text: Accessor<string>;
	size: Accessor<float32>;
	color: Accessor<Color>;
	textStyle?: Accessor<TextStyle> | null;
	textRuns?: Accessor<TextRun[]> | null;
	shapingBreaks?: Accessor<int32[]> | null;
	truncate?: Accessor<Truncate> | null;
	hangingIndent?: Accessor<float32> | null;
	forceWidth?: Accessor<float32> | null;
	selectionRange?: Accessor<SelectionRange> | null;
	selectionColor?: Accessor<Color> | null;
	cursorIndex?: Accessor<int32> | null;
	cursorColor?: Accessor<Color> | null;
	cursorBlinkTime?: Accessor<float32> | null;
}

const sceneScope = createContext<VoidHost | null>(null);

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

function requireScene(tag: string): VoidHost {
	if (useContext(voidScope) !== VoidSpace.Scene2D) {
		throw new Error(tag + ": mount inside Scene2D within Void");
	}
	const under = useContext(sceneScope);
	if (under === null) { throw new Error(tag + ": mount inside Scene2D within Void"); }
	return under;
}

function bindScene<T>(read: () => T, apply: (value: T) => void): void {
	const vh = requireScene("Scene2D");
	createRenderEffect<T>(
		(prev: T | null): T => read(),
		(value: T, prev: T | null): Cleanup | null => {
			vh.mutate((): void => { apply(value); });
			return null;
		},
	);
}

function bindNode(tag: string, node: NodeRef, props: NodeProps): void {
	if (props.local !== null) {
		const local = props.local as () => Local2D;
		bindScene(local, (value: Local2D): void => { node.setLocal(value); });
	}
	if (props.paint !== null) {
		const readPaint = props.paint as () => Paint2D;
		bindScene(readPaint, (value: Paint2D): void => {
			const row = node.paint().colorMatrixRow;
			if (value.colorMatrixRow !== NO_COLOR_MATRIX_ROW && value.colorMatrixRow !== row) {
				throw new Error(tag + ": paint cannot move a colorMatrixRow; use colorMatrix");
			}
			node.setPaint({ ...value, colorMatrixRow: row });
		});
	}
	if (props.colorMatrix !== null) {
		const matrix = props.colorMatrix as () => Mat4;
		bindScene(matrix, (value: Mat4): void => { node.setColorMatrix(value); });
	}
	if (props.order !== null) {
		const order = props.order as () => Order2D;
		bindScene(order, (value: Order2D): void => { node.setOrder(value); });
	}
	if (props.filter !== null) {
		const filter = props.filter as () => Filter;
		bindScene(filter, (value: Filter): void => { node.setFilter(value); });
	}
}

function renderNode(
	tag: string,
	props: NodeProps,
	make: (scene: VoidScene2D) => NodeRef,
	bind: (node: NodeRef) => void,
): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const vh = requireScene(tag);
		mountOwned((): void => {
			vh.mutate((): void => {
				const node = make(vh.scene);
				const wrapped = new VoidNode(node, true);
				try {
					place(host, parent, wrapped, before);
					bind(node);
					bindNode(tag, node, props);
					if (props.ref !== null) { (props.ref as (node: NodeRef) => void)(node); }
					const children = props.children;
					if (children !== null) { children(host, wrapped, null); }
				} catch (error) {
					if (!wrapped.disposed) {
						const up = wrapped.parent;
						if (up !== null) { host.removeChild(up, wrapped); }
						else {
							if (node.isLive()) { node.dispose(); }
							wrapped.disposed = true;
						}
					}
					throw error;
				}
			});
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
			const vh = createVoidHostWith(scene, DEFAULT_FONT, null, true);
			onCleanup((): void => {
				const root = vh.root as VoidNode;
				for (let i = root.children.length - 1; i >= 0; i -= 1) {
					vh.host.removeChild(root, root.children[i]);
				}
				freeVoidLayoutTree(root);
				root.disposed = true;
				scene.close();
			});
			if (props.clear !== null) {
				const clear = props.clear as () => Color;
				createRenderEffect<Color>(
					(prev: Color | null): Color => clear(),
					(value: Color, prev: Color | null): Cleanup | null => {
						vh.mutate((): void => { scene.clear = value; });
						return null;
					},
				);
			}
			if (props.camera !== null) {
				const camera = props.camera as () => Camera;
				createRenderEffect<Camera>(
					(prev: Camera | null): Camera => camera(),
					(value: Camera, prev: Camera | null): Cleanup | null => {
						vh.mutate((): void => { scene.cam = value; });
						return null;
					},
				);
			}
			if (props.smooth !== null) {
				const smooth = props.smooth as () => boolean;
				createRenderEffect<boolean>(
					(prev: boolean | null): boolean => smooth(),
					(value: boolean, prev: boolean | null): Cleanup | null => {
						vh.mutate((): void => { scene.defaultSmooth = value; });
						return null;
					},
				);
			}
			if (props.scaleMode !== null || props.designW !== null || props.designH !== null) {
				createRenderEffect<[ScaleMode, float32, float32]>(
					(prev: [ScaleMode, float32, float32] | null): [ScaleMode, float32, float32] => [
						props.scaleMode === null ? ScaleMode.Resize : (props.scaleMode as () => ScaleMode)(),
						props.designW === null ? 0.0 : (props.designW as () => float32)(),
						props.designH === null ? 0.0 : (props.designH as () => float32)(),
					],
					(value: [ScaleMode, float32, float32], prev: [ScaleMode, float32, float32] | null): Cleanup | null => {
						vh.mutate((): void => { scene.setScaleMode(value[0], value[1], value[2]); });
						return null;
					},
				);
			}
			if (props.ref !== null) { (props.ref as (scene: VoidScene2D) => void)(scene); }
			const children = props.children;
			if (children !== null) {
				voidScope.provider({
					value: accessor(() => VoidSpace.Scene2D),
					children: sceneScope.provider({
						value: accessor(() => vh), children: children,
					}),
				})(vh.host, vh.root, null);
			}
		});
	};
}

export function Group(props: GroupProps): NeonNode {
	return renderNode("Group", props, (scene: VoidScene2D): NodeRef => scene.group(),
		(node: NodeRef): void => {
			if (props.width !== null || props.height !== null) {
				const initial = node.content();
				bindScene<[float32, float32]>(
					(): [float32, float32] => [
						props.width === null ? initial.w : (props.width as () => float32)(),
						props.height === null ? initial.h : (props.height as () => float32)(),
					],
					(value: [float32, float32]): void => { node.setSize(value[0], value[1]); },
				);
			}
			if (props.background !== null) {
				const background = props.background as () => Color | null;
				bindScene<Color | null>(
					(): Color | null => {
						const color = background();
						return color === null ? null : props.paint === null ? color : (props.paint as () => Paint2D)().color;
					},
					(color: Color | null): void => {
						if (color === null) { node.clearBackground(); }
						else { node.setBackground(color); }
					},
				);
			}
		});
}

export function TileGroup(props: TileGroupProps): NeonNode {
	return renderNode("TileGroup", props, (scene: VoidScene2D): NodeRef => scene.tileGroup(),
		(node: NodeRef): void => {
			bindScene((): TileCell[] => props.cells(), (value: TileCell[]): void => { node.setTiles(value); });
			if (props.first !== null || props.count !== null) {
				bindScene<[int32, int32]>(
					(): [int32, int32] => [
						props.first === null ? 0 : (props.first as () => int32)(),
						props.count === null ? ALL_TILES : (props.count as () => int32)(),
					],
					(value: [int32, int32]): void => {
						if (value[0] < 0 || value[1] < 0) { throw new Error("TileGroup: first/count must be nonnegative"); }
						node.setRange(value[0], value[1]);
					},
				);
			}
		});
}

export function Rect(props: RectProps): NeonNode {
	return renderNode("Rect", props,
		(scene: VoidScene2D): NodeRef => scene.rect(props.width(), props.height(), props.color()),
		(node: NodeRef): void => {
			bindScene<[float32, float32]>(
				(): [float32, float32] => [props.width(), props.height()],
				(value: [float32, float32]): void => { node.setSize(value[0], value[1]); },
			);
			if (props.boxStyle !== null) {
				const style = props.boxStyle as () => BoxStyle;
				bindScene(style, (value: BoxStyle): void => { node.setBoxStyle(value); });
			}
			if (props.paint === null) {
				bindScene((): Color => props.color(), (value: Color): void => { node.setColor(value); });
			}
		});
}

export function Sprite(props: SpriteProps): NeonNode {
	return renderNode("Sprite", props, (scene: VoidScene2D): NodeRef => scene.sprite(props.tile()),
		(node: NodeRef): void => {
			bindScene<[Tile, float32, float32]>(
				(): [Tile, float32, float32] => {
					const tile = props.tile();
					return [tile, props.width === null ? tile.w : (props.width as () => float32)(),
						props.height === null ? tile.h : (props.height as () => float32)()];
				},
				(value: [Tile, float32, float32]): void => { node.setTile(value[0]).setSize(value[1], value[2]); },
			);
			if (props.imageStyle !== null) {
				const style = props.imageStyle as () => ImageStyle;
				bindScene(style, (value: ImageStyle): void => { node.setImageStyle(value); });
			}
		});
}

export function ScaleGrid(props: ScaleGridProps): NeonNode {
	return renderNode("ScaleGrid", props, (scene: VoidScene2D): NodeRef => scene.scaleGrid(
		props.tile(), props.borderL(), props.borderT(), props.borderR(), props.borderB(),
	), (node: NodeRef): void => {
		bindScene<[Tile, float32, float32, float32, float32, float32, float32]>(
			(): [Tile, float32, float32, float32, float32, float32, float32] => {
				const tile = props.tile();
				return [tile, props.width === null ? tile.w : (props.width as () => float32)(),
					props.height === null ? tile.h : (props.height as () => float32)(),
					props.borderL(), props.borderT(), props.borderR(), props.borderB()];
			},
			(value: [Tile, float32, float32, float32, float32, float32, float32]): void => {
				node.setContent({ w: value[1], h: value[2], tile: value[0],
					borderL: value[3], borderT: value[4], borderR: value[5], borderB: value[6] });
			},
		);
	});
}

export function Underline(props: UnderlineProps): NeonNode {
	return renderNode("Underline", props, (scene: VoidScene2D): NodeRef => scene.underline(
		props.width(), props.thickness(), props.color(), props.wavy(),
	), (node: NodeRef): void => {
		bindScene<[float32, float32, boolean]>(
			(): [float32, float32, boolean] => [props.width(), props.thickness(), props.wavy()],
			(value: [float32, float32, boolean]): void => {
				node.setContent({ ...node.content(), w: value[0], h: value[2] ? value[1] * 3.0 : value[1],
					borderL: value[1], borderT: value[2] ? 1.0 : 0.0 });
			},
		);
		if (props.paint === null) {
			bindScene((): Color => props.color(), (value: Color): void => { node.setColor(value); });
		}
	});
}

export function Selection(props: SelectionProps): NeonNode {
	return renderNode("Selection", props, (scene: VoidScene2D): NodeRef => scene.selection(
		props.width(), props.height(), props.color(), props.prevOffsetX(), props.prevWidth(),
		props.nextOffsetX(), props.nextWidth(),
	), (node: NodeRef): void => {
		bindScene<[float32, float32, float32, float32, float32, float32]>(
			(): [float32, float32, float32, float32, float32, float32] => [props.width(), props.height(),
				props.prevOffsetX(), props.prevWidth(), props.nextOffsetX(), props.nextWidth()],
			(value: [float32, float32, float32, float32, float32, float32]): void => {
				node.setContent({ ...node.content(), w: value[0], h: value[1], borderL: value[2],
					borderT: value[3], borderR: value[4], borderB: value[5] });
			},
		);
		if (props.paint === null) {
			bindScene((): Color => props.color(), (value: Color): void => { node.setColor(value); });
		}
	});
}

export function Graphics(props: GraphicsProps): NeonNode {
	return renderNode("Graphics", props,
		(scene: VoidScene2D): NodeRef => scene.graphics(),
		(node: NodeRef): void => {
			bindScene((): GraphicsOp[] => props.operations(), (value: GraphicsOp[]): void => { replayGraphics(node, value); });
		});
}

export function Mask(props: MaskProps): NeonNode {
	return renderNode("Mask", props,
		(scene: VoidScene2D): NodeRef => scene.mask(props.width(), props.height()),
		(node: NodeRef): void => {
			const scrolling = props.scrollX !== null || props.scrollY !== null || props.scrollBounds !== null;
			bindScene<[float32, float32, Bounds2D | null, float32, float32]>(
				(): [float32, float32, Bounds2D | null, float32, float32] => [props.width(), props.height(),
					!scrolling || props.scrollBounds === null ? null : (props.scrollBounds as () => Bounds2D | null)(),
					!scrolling || props.scrollX === null ? 0.0 : (props.scrollX as () => float32)(),
					!scrolling || props.scrollY === null ? 0.0 : (props.scrollY as () => float32)()],
				(value: [float32, float32, Bounds2D | null, float32, float32]): void => {
					node.setSize(value[0], value[1]);
					if (scrolling) { node.setScrollBounds(value[2]).scrollTo(value[3], value[4]); }
				},
			);
		});
}

export function Label(props: LabelProps): NeonNode {
	return renderNode("Label", props,
		(scene: VoidScene2D): NodeRef => scene.label(props.text(), props.size(), props.color()),
		(node: NodeRef): void => {
			if ((props.selectionRange === null) !== (props.selectionColor === null)) {
				throw new Error("Label: provide selectionRange and selectionColor together");
			}
			if ((props.cursorIndex === null) !== (props.cursorColor === null)) {
				throw new Error("Label: provide cursorIndex and cursorColor together");
			}
			bindScene((): string => props.text(), (value: string): void => { node.setText(value); });
			if (props.paint === null) {
				bindScene((): Color => props.color(), (value: Color): void => { node.setColor(value); });
			}
			bindScene<[TextStyle | null, float32]>(
				(): [TextStyle | null, float32] => [props.textStyle === null ? null : (props.textStyle as () => TextStyle)(), props.size()],
				(value: [TextStyle | null, float32]): void => {
					const style = value[0] === null ? node.textStyle() : value[0] as TextStyle;
					node.setTextStyle({ ...style, size: value[1] });
				},
			);
			if (props.textRuns !== null) {
				const runs = props.textRuns as () => TextRun[];
				bindScene(runs, (value: TextRun[]): void => { node.setTextRuns(value); });
			}
			if (props.shapingBreaks !== null) {
				const breaks = props.shapingBreaks as () => int32[];
				bindScene(breaks, (value: int32[]): void => { node.setShapingBreaks(value); });
			}
			if (props.truncate !== null) {
				const truncate = props.truncate as () => Truncate;
				bindScene(truncate, (value: Truncate): void => { node.setTruncate(value); });
			}
			if (props.hangingIndent !== null) {
				const indent = props.hangingIndent as () => float32;
				bindScene(indent, (value: float32): void => { node.setHangingIndent(value); });
			}
			if (props.forceWidth !== null) {
				const width = props.forceWidth as () => float32;
				bindScene(width, (value: float32): void => { node.setForceWidth(value); });
			}
			if (props.selectionRange !== null) {
				const range = props.selectionRange as () => SelectionRange;
				const color = props.selectionColor as () => Color;
				bindScene<[SelectionRange, Color]>((): [SelectionRange, Color] => [range(), color()],
					(value: [SelectionRange, Color]): void => { node.setSelectionRange(value[0], value[1]); });
			}
			if (props.cursorIndex !== null) {
				const index = props.cursorIndex as () => int32;
				const color = props.cursorColor as () => Color;
				bindScene<[int32, Color]>((): [int32, Color] => [index(), color()],
					(value: [int32, Color]): void => { node.setCursorIndex(value[0], value[1]); });
			}
			if (props.cursorBlinkTime !== null) {
				const seconds = props.cursorBlinkTime as () => float32;
				bindScene(seconds, (value: float32): void => { node.setCursorBlinkTime(value); });
			}
		});
}
