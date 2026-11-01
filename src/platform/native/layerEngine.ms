import { HostNode } from "../../render/hostTypes";

export enum LayerProperty {
	Opacity,
	Transform,
}

export enum LayerComponent {
	Opacity,
	ScaleX,
	ScaleY,
	TranslateX,
	TranslateY,
	Rotation,
}

export struct LayerTiming {
	durationMs: float64;
	repeatCount: float64;
	autoreverses: boolean;
	startMs: float64;
	offsetMs: float64;
	speed: float64;
}

export interface LayerEngine {
	owns: (node: HostNode) => boolean;
	write: (node: HostNode, property: LayerProperty, values: float64[]) => void;
	read: (node: HostNode, component: LayerComponent) => float64;
	animate: (
		node: HostNode,
		property: LayerProperty,
		keyTimes: float64[],
		values: float64[],
		timing: LayerTiming,
	) => void;
	remove: (node: HostNode, property: LayerProperty) => void;
}

let installed: LayerEngine | null = null;

export function installLayerEngine(engine: LayerEngine | null): void {
	installed = engine;
}

export function layerEngine(): LayerEngine | null {
	return installed;
}

export function componentCount(property: LayerProperty): int32 {
	return match (property) {
		LayerProperty.Opacity => 1,
		LayerProperty.Transform => 5,
	};
}
