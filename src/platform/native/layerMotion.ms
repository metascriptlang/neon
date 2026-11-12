import { LayerComponent, LayerProperty, LayerTiming } from "./layerEngine";

@include("./layerMotion.h");

function propertyId(property: LayerProperty): int32 {
	return match (property) {
		LayerProperty.Opacity => 0,
		LayerProperty.Transform => 1,
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
	lagMs: float64,
): void;
extern function niLayerRemove(view: Ptr<void>, property: int32): void;
extern function niLayerPresented(view: Ptr<void>, component: int32): float64;

export function presentedComponent(
	view: Ptr<void>,
	component: LayerComponent,
): float64 {
	return niLayerPresented(view, componentId(component));
}

export function layerWrite(view: Ptr<void>, property: LayerProperty, values: float64[]): void {
	niLayerWrite(view, propertyId(property), values);
}

export function layerAnimate(
	view: Ptr<void>,
	property: LayerProperty,
	keyTimes: float64[],
	values: float64[],
	timing: LayerTiming,
): void {
	niLayerAnimate(
		view,
		propertyId(property),
		keyTimes,
		values,
		timing.durationMs,
		timing.repeatCount,
		timing.autoreverses ? 1 : 0,
		timing.startMs,
		timing.offsetMs,
		timing.speed,
		timing.lagMs,
	);
}

export function layerRemove(view: Ptr<void>, property: LayerProperty): void {
	niLayerRemove(view, propertyId(property));
}
