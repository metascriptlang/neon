import { HostNode } from "../../render/hostTypes";
import { nativeViewOf } from "./host";

@include("./layerMotion.h");

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
		LayerProperty.Opacity => 1,LayerProperty.Transform => 5,
	};
}

function propertyId(property: LayerProperty): int32 {
	return match (property) {
		LayerProperty.Opacity => 0,LayerProperty.Transform => 1,
	};
}

function componentId(component: LayerComponent): int32 {
	return match (component) {
		LayerComponent.Opacity => 0,
		LayerComponent.ScaleX => 1,
		LayerComponent.ScaleY => 2,
		LayerComponent.TranslateX => 3,
		LayerComponent.TranslateY => 4,
		LayerComponent.Rotation => 5,
	};
}

extern function niLayerWrite(
	view: Ptr<void>,
	property: int32,
	values: Readonly<Span<float64>>,
): void;
extern function niLayerRead(view: Ptr<void>, component: int32): float64;
extern function niLayerAnimate(
	view: Ptr<void>,
	property: int32,
	keyTimes: Readonly<Span<float64>>,
	values: Readonly<Span<float64>>,
	durationMs: float64,
	repeatCount: float64,
	autoreverses: int32,
	startMs: float64,
	offsetMs: float64,
	speed: float64,
): void;
extern function niLayerRemove(view: Ptr<void>, property: int32): void;
extern function niLayerPresented(view: Ptr<void>, component: int32): float64;

export function presentedComponent(
	node: HostNode,
	component: LayerComponent,
): float64 {
	return niLayerPresented(nativeViewOf(node), componentId(component));
}

export function bridgeLayerEngine(): LayerEngine {
	return {
		write: (
			node: HostNode,
			property: LayerProperty,
			values: float64[],
		): void => {
			niLayerWrite(nativeViewOf(node), propertyId(property), values);
		},
		read: (node: HostNode, component: LayerComponent): float64 =>
			niLayerRead(nativeViewOf(node), componentId(component)),
		animate: (
			node: HostNode,
			property: LayerProperty,
			keyTimes: float64[],
			values: float64[],
			timing: LayerTiming,
		): void => {
			niLayerAnimate(
				nativeViewOf(node),
				propertyId(property),
				keyTimes,
				values,
				timing.durationMs,
				timing.repeatCount,
				timing.autoreverses ? 1 : 0,
				timing.startMs,
				timing.offsetMs,
				timing.speed,
			);
		},
		remove: (node: HostNode, property: LayerProperty): void => {
			niLayerRemove(nativeViewOf(node), propertyId(property));
		},
	};
}

when (ios) {
	installLayerEngine(bridgeLayerEngine());
}
