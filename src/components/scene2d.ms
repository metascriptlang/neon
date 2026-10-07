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

export function Group(props: GroupProps): NeonNode {
	return renderNode("Group", props, (scene: VoidScene2D): NodeRef => scene.group(),
		(node: NodeRef): void => {
			if (props.width !== null || props.height !== null) {
				const initial = node.content();
				createEffect((): void => {
					const width = props.width === null ? initial.w : (props.width as () => float32)();
					const height = props.height === null ? initial.h : (props.height as () => float32)();
					node.setSize(width, height);
				});
			}
			if (props.background !== null) {
				const background = props.background as () => Color | null;
				createEffect((): void => {
					const color = background();
					if (color === null) { node.clearBackground(); }
					else {
						const fill = props.paint === null ? color : (props.paint as () => Paint2D)().color;
						node.setBackground(fill);
					}
				});
			}
		});
}

export function TileGroup(props: TileGroupProps): NeonNode {
	return renderNode("TileGroup", props, (scene: VoidScene2D): NodeRef => scene.tileGroup(),
		(node: NodeRef): void => {
			createEffect((): void => { node.setTiles(props.cells()); });
			if (props.first !== null || props.count !== null) {
				createEffect((): void => {
					const first: int32 = props.first === null ? 0 : (props.first as () => int32)();
					const count: int32 = props.count === null ? ALL_TILES :
						(props.count as () => int32)();
					if (first < 0 || count < 0) {
						throw new Error("TileGroup: first/count must be nonnegative");
					}
					node.setRange(first, count);
				});
			}
		});
}

export function Rect(props: RectProps): NeonNode {
	return renderNode("Rect", props,
		(scene: VoidScene2D): NodeRef => scene.rect(props.width(), props.height(), props.color()),
		(node: NodeRef): void => {
			createEffect((): void => { node.setSize(props.width(), props.height()); });
			if (props.boxStyle !== null) {
				const style = props.boxStyle as () => BoxStyle;
				createEffect((): void => { node.setBoxStyle(style()); });
			}
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
				const width: float32 = props.width === null ? tile.w :
					(props.width as () => float32)();
				const height: float32 = props.height === null ? tile.h :
					(props.height as () => float32)();
				node.setTile(tile).setSize(width, height);
			});
			if (props.imageStyle !== null) {
				const style = props.imageStyle as () => ImageStyle;
				createEffect((): void => { node.setImageStyle(style()); });
			}
		});
}

export function ScaleGrid(props: ScaleGridProps): NeonNode {
	return renderNode("ScaleGrid", props, (scene: VoidScene2D): NodeRef => scene.scaleGrid(
		props.tile(), props.borderL(), props.borderT(), props.borderR(), props.borderB(),
	), (node: NodeRef): void => {
		createEffect((): void => {
			const tile = props.tile();
			const width: float32 = props.width === null ? tile.w :
				(props.width as () => float32)();
			const height: float32 = props.height === null ? tile.h :
				(props.height as () => float32)();
			node.setContent({
				w: width, h: height, tile: tile,
				borderL: props.borderL(), borderT: props.borderT(),
				borderR: props.borderR(), borderB: props.borderB(),
			});
		});
	});
}

export function Underline(props: UnderlineProps): NeonNode {
	return renderNode("Underline", props, (scene: VoidScene2D): NodeRef => scene.underline(
		props.width(), props.thickness(), props.color(), props.wavy(),
	), (node: NodeRef): void => {
		createEffect((): void => {
			const thickness = props.thickness();
			const wavy = props.wavy();
			node.setContent({
				...node.content(), w: props.width(), h: wavy ? thickness * 3.0 : thickness,
				borderL: thickness, borderT: wavy ? 1.0 : 0.0,
			});
		});
		if (props.paint === null) {
			createEffect((): void => { node.setColor(props.color()); });
		}
	});
}

export function Selection(props: SelectionProps): NeonNode {
	return renderNode("Selection", props, (scene: VoidScene2D): NodeRef => scene.selection(
		props.width(), props.height(), props.color(), props.prevOffsetX(), props.prevWidth(),
		props.nextOffsetX(), props.nextWidth(),
	), (node: NodeRef): void => {
		createEffect((): void => {
			node.setContent({
				...node.content(), w: props.width(), h: props.height(),
				borderL: props.prevOffsetX(), borderT: props.prevWidth(),
				borderR: props.nextOffsetX(), borderB: props.nextWidth(),
			});
		});
		if (props.paint === null) {
			createEffect((): void => { node.setColor(props.color()); });
		}
	});
}

export function Mask(props: MaskProps): NeonNode {
	return renderNode("Mask", props,
		(scene: VoidScene2D): NodeRef => scene.mask(props.width(), props.height()),
		(node: NodeRef): void => {
			const scrolling = props.scrollX !== null || props.scrollY !== null ||
				props.scrollBounds !== null;
			createEffect((): void => {
				node.setSize(props.width(), props.height());
				if (scrolling) {
					const bounds: Bounds2D | null = props.scrollBounds === null ? null :
						(props.scrollBounds as () => Bounds2D | null)();
					const x: float32 = props.scrollX === null ? 0.0 :
						(props.scrollX as () => float32)();
					const y: float32 = props.scrollY === null ? 0.0 :
						(props.scrollY as () => float32)();
					node.setScrollBounds(bounds).scrollTo(x, y);
				}
			});
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
			createEffect((): void => { node.setText(props.text()); });
			if (props.paint === null) {
				createEffect((): void => { node.setColor(props.color()); });
			}
			createEffect((): void => {
				const style = props.textStyle === null ? node.textStyle() :
					(props.textStyle as () => TextStyle)();
				node.setTextStyle({ ...style, size: props.size() });
			});
			if (props.textRuns !== null) {
				const runs = props.textRuns as () => TextRun[];
				createEffect((): void => { node.setTextRuns(runs()); });
			}
			if (props.shapingBreaks !== null) {
				const breaks = props.shapingBreaks as () => int32[];
				createEffect((): void => { node.setShapingBreaks(breaks()); });
			}
			if (props.truncate !== null) {
				const truncate = props.truncate as () => Truncate;
				createEffect((): void => { node.setTruncate(truncate()); });
			}
			if (props.hangingIndent !== null) {
				const indent = props.hangingIndent as () => float32;
				createEffect((): void => { node.setHangingIndent(indent()); });
			}
			if (props.forceWidth !== null) {
				const width = props.forceWidth as () => float32;
				createEffect((): void => { node.setForceWidth(width()); });
			}
			if (props.selectionRange !== null) {
				const range = props.selectionRange as () => SelectionRange;
				const color = props.selectionColor as () => Color;
				createEffect((): void => { node.setSelectionRange(range(), color()); });
			}
			if (props.cursorIndex !== null) {
				const index = props.cursorIndex as () => int32;
				const color = props.cursorColor as () => Color;
				createEffect((): void => { node.setCursorIndex(index(), color()); });
			}
			if (props.cursorBlinkTime !== null) {
				const seconds = props.cursorBlinkTime as () => float32;
				createEffect((): void => { node.setCursorBlinkTime(seconds()); });
			}
		});
}
