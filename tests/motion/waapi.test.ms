import { ManualClock } from "pulse/src/clock";
import {
	MotionClip,
	MotionDocument,
	MotionKeyframe,
	MotionPlacement,
	MotionTrack,
	MotionValue,
	colorValue,
	linearKeyframe,
	numberValue,
} from "pulse/src/document";
import { MotionOptions, motionOptions } from "pulse/src/player";
import {
	CssRun,
	RoutedTrack,
	StyleProperty,
	TrackRoute,
	WaapiPlan,
	WaapiKeyframe,
	WaapiTiming,
	planWaapi,
	styleProperty,
	styleValue,
} from "../../src/motion/waapi";

function options(): MotionOptions {
	return motionOptions(new ManualClock().clock);
}

function track(
	slot: string,
	property: string,
	keyframes: MotionKeyframe[],
): MotionTrack {
	return {
		slot,
		property,
		kind: keyframes[0].value.kind,
		keyframes,
	};
}

function clip(
	id: string,
	duration: float64,
	tracks: MotionTrack[],
	placements: MotionPlacement[],
): MotionClip {
	return {
		id,
		duration,
		tracks,
		placements,
		labels: [],
	};
}

function single(tracks: MotionTrack[]): MotionDocument {
	return {
		version: 1,
		root: "main",
		clips: [clip("main", 1000, tracks, [])],
	};
}

function key(id: string, time: float64, value: MotionValue): MotionKeyframe {
	return {
		id,
		time,
		value,
		handles: {
			leftX: 0.6,
			leftY: 0.1,
			rightX: 0.25,
			rightY: 0.9,
		},
		connectedRight: true,
	};
}

function hold(id: string, time: float64, value: float64): MotionKeyframe {
	return {
		...linearKeyframe(id, time, value),
		connectedRight: false,
	};
}

function only(plan: WaapiPlan): RoutedTrack {
	if (plan.tracks.length !== 1) {
		throw new Error("one track: " + plan.tracks.length.toString());
	}
	return plan.tracks[0];
}

function refusal(run: () => void): string {
	let message = "";
	try { run(); } catch (e) { message = e.message; }
	return message;
}

test "keyframe offsets are time over duration and each segment eases by its handles" {
	const routed = only(
		planWaapi(
			single(
				[
					track(
						"box",
						"opacity",
						[
							key("a", 0, numberValue(0)),
							key("b", 500, numberValue(1)),
							key("c", 1000, numberValue(0.5)),
						],
					),
				],
			),
			options(),
			[],
		),
	);
	assert routed.route === TrackRoute.Waapi;
	assert routed.keyframes.map((k): float64 => k.offset).join(",") === "0,0.5,1";
	assert routed.keyframes.map((k): string => k.value).join(",") === "0,1,0.5";
	assert routed.keyframes[0].easing ===
		"cubic-bezier(0.25, 0.9, 0.6, 0.1)", routed.keyframes[0].easing;
	assert routed.keyframes[2].easing === "linear";
}

test "a track that starts late or ends early holds its end values to offsets 0 and 1" {
	const routed = only(
		planWaapi(
			single(
				[
					track(
						"box",
						"opacity",
						[linearKeyframe("a", 200, 0.2), linearKeyframe("b", 600, 0.6)],
					),
				],
			),
			options(),
			[],
		),
	);
	assert routed.keyframes.map((k): float64 => k.offset).join(",") ===
		"0,0.2,0.6,1";
	assert routed.keyframes.map((k): string => k.value).join(",") ===
		"0.2,0.2,0.6,0.6";
	assert routed.keyframes[0].easing === "linear" &&
		routed.keyframes[2].easing === "linear";
	assert routed.keyframes[1].easing ===
		"cubic-bezier(0.333333, 0.333333, 0.666667, 0.666667)", routed.keyframes[1].easing;
}

test "a hold segment lowers to a jump at its right keyframe" {
	const routed = only(
		planWaapi(
			single([track("box", "opacity", [hold("a", 0, 0), hold("b", 1000, 1)])]),
			options(),
			[],
		),
	);
	assert routed.keyframes[0].easing === "steps(1, end)";
}

test "values carry each CSS property's unit and colours become rgba in sRGB" {
	const red = colorValue(1, 0.5, 0, 0.25);
	assert styleValue(styleProperty("backgroundColor") as StyleProperty, red) ===
		"rgba(255, 127.5, 0, 0.25)";
	assert styleValue(
		styleProperty("opacity") as StyleProperty,
		numberValue(0.5),
	) ===
		"0.5";
	assert styleValue(
		styleProperty("translateX") as StyleProperty,
		numberValue(10),
	) ===
		"10px";
	assert styleValue(
		styleProperty("translateY") as StyleProperty,
		numberValue(-4),
	) ===
		"0px -4px";
	assert styleValue(
		styleProperty("rotate") as StyleProperty,
		numberValue(45),
	) ===
		"45deg";
	assert styleValue(
		styleProperty("scaleX") as StyleProperty,
		numberValue(2),
	) ===
		"2 1";
	assert styleValue(
		styleProperty("width") as StyleProperty,
		numberValue(1.0 / 3.0),
	) ===
		"0.333333px";
}

test "the eligibility table names what the browser animates; the rest needs a binding" {
	for (const name of [
		"opacity",
		"translateX",
		"rotate",
		"scale",
		"width",
		"left",
		"borderRadius",
		"color",
	]) { assert styleProperty(name) !== null, name; }
	assert styleProperty("progress") === null;
	const routed = only(
		planWaapi(
			single([track("box", "progress", [linearKeyframe("a", 0, 0)])]),
			options(),
			["box.progress"],
		),
	);
	assert routed.route === TrackRoute.Custom && routed.style === null;
}

test "repeat, yoyo, delay and timeScale map onto WAAPI timing" {
	const doc = single(
		[
			track(
				"box",
				"opacity",
				[linearKeyframe("a", 0, 0), linearKeyframe("b", 1000, 1)],
			),
		],
	);
	const plain = planWaapi(doc, options(), []).timing as WaapiTiming;
	assert plain.duration === 1000 && plain.delay === 0 && plain.iterations === 1;
	assert plain.direction === "normal" && plain.playbackRate === 1 &&
		plain.fill === "both";
	const looped = planWaapi(
		doc,
		{
			...options(),
			repeat: -1,
			yoyo: true,
			timeScale: 2,
			delay: 300,
		},
		[],
	).timing as WaapiTiming;
	assert looped.iterations === Infinity && looped.direction === "alternate";
	assert looped.playbackRate === 2 && looped.delay === 300;
	const counted = planWaapi(
		doc,
		{
			...options(),
			repeat: 2,
		},
		[],
	).timing as WaapiTiming;
	assert counted.iterations === 3;
}

test "a repeat delay has no WAAPI form, so every track runs on the evaluator" {
	const doc = single(
		[
			track(
				"box",
				"opacity",
				[linearKeyframe("a", 0, 0), linearKeyframe("b", 1000, 1)],
			),
		],
	);
	const plan = planWaapi(
		doc,
		{
			...options(),
			repeat: 1,
			repeatDelay: 100,
		},
		[],
	);
	assert plan.timing === null && only(plan).route === TrackRoute.Style;
	const once = planWaapi(
		doc,
		{
			...options(),
			repeat: 0,
			repeatDelay: 100,
		},
		[],
	);
	assert only(once).route === TrackRoute.Waapi;
}

function nested(
	start: float64,
	rate: float64,
	keyframes: MotionKeyframe[],
): MotionDocument {
	return {
		version: 1,
		root: "main",
		clips: [
			clip(
				"main",
				1000,
				[],
				[
					{
						clip: "child",
						start,
						rate,
						slots: [],
					},
				],
			),
			clip("child", 400, [track("box", "opacity", keyframes)], []),
		],
	};
}

test "a nested clip at the start with its own rate lowers by scaling its keyframe times" {
	const routed = only(
		planWaapi(
			nested(0, 2, [linearKeyframe("a", 0, 0), linearKeyframe("b", 400, 1)]),
			options(),
			[],
		),
	);
	assert routed.route === TrackRoute.Waapi;
	assert routed.keyframes.map((k): float64 => k.offset).join(",") === "0,0.2,1";
}

test "a late placement plays once as a WAAPI delay, its keyframes spread over the rest of the clip" {
	const late = only(
		planWaapi(
			nested(200, 1, [linearKeyframe("a", 0, 0), linearKeyframe("b", 400, 1)]),
			options(),
			[],
		),
	);
	assert late.route === TrackRoute.Waapi && late.delay === 200;
	assert late.keyframes.map((k): float64 => k.offset).join(",") === "0,0.5,1";
	assert late.keyframes.map((k): string => k.value).join(",") === "0,1,1";
	const staggered = planWaapi(
		{
			version: 1,
			root: "main",
			clips: [
				clip(
					"main",
					1000,
					[],
					[
						{ clip: "child", start: 0, rate: 1, slots: [] },
						{ clip: "child", start: 300, rate: 1, slots: [{ from: "box", to: "card" }] },
					],
				),
				clip(
					"child",
					400,
					[track("box", "opacity", [linearKeyframe("a", 0, 0), linearKeyframe("b", 400, 1)])],
					[],
				),
			],
		},
		options(),
		[],
	);
	assert staggered.runs.map((r: CssRun): string => r.slot + "@" + r.delay.toString()).join(",") ===
		"box@0,card@300";
}

test "a repeated late placement, a keyframe outside its clip and two writers run on the evaluator" {
	const late = only(
		planWaapi(
			nested(200, 1, [linearKeyframe("a", 0, 0), linearKeyframe("b", 400, 1)]),
			{
				...options(),
				repeat: 1,
			},
			[],
		),
	);
	assert late.route === TrackRoute.Style;
	const outside = only(
		planWaapi(
			nested(0, 1, [linearKeyframe("a", 0, 0), linearKeyframe("b", 500, 1)]),
			options(),
			[],
		),
	);
	assert outside.route === TrackRoute.Style;
	const doc: MotionDocument = {
		version: 1,
		root: "main",
		clips: [
			clip(
				"main",
				1000,
				[
					track(
						"box",
						"opacity",
						[linearKeyframe("a", 0, 0), linearKeyframe("b", 1000, 1)],
					),
				],
				[
					{
						clip: "child",
						start: 0,
						rate: 1,
						slots: [],
					},
				],
			),
			clip(
				"child",
				400,
				[track("box", "opacity", [linearKeyframe("a", 0, 1)])],
				[],
			),
		],
	};
	const plan = planWaapi(doc, options(), []);
	assert only(plan).route === TrackRoute.Style;
}

test "a track the browser cannot run is refused by name" {
	const unknown = single(
		[track("box", "progress", [linearKeyframe("a", 0, 0)])],
	);
	assert refusal(() => { planWaapi(unknown, options(), []); }) ===
		"motion: no browser binding for track box.progress";
	const wrongKind = single(
		[track("box", "backgroundColor", [linearKeyframe("a", 0, 0)])],
	);
	assert refusal(() => { planWaapi(wrongKind, options(), []); }) ===
		"motion: track box.backgroundColor holds a number but CSS backgroundColor takes a colour";
	const uniform = single(
		[
			track("box", "scale", [linearKeyframe("a", 0, 1)]),
			track("box", "scaleX", [linearKeyframe("a", 0, 1)]),
		],
	);
	assert refusal(() => { planWaapi(uniform, options(), []); }) ===
		"motion: box.scale and box.scaleX both write CSS scale: a uniform value and an axis have no exact merge";
}

function onlyRun(plan: WaapiPlan): CssRun {
	if (plan.runs.length !== 1) {
		throw new Error("one run: " + plan.runs.length.toString());
	}
	return plan.runs[0];
}

function ramp(property: string, times: float64[], values: float64[]): MotionTrack {
	const keys: MotionKeyframe[] = [];
	for (let i: int32 = 0; i < times.length; i += 1) {
		keys.push(linearKeyframe("k" + i.toString(), times[i], values[i]));
	}
	return track("box", property, keys);
}

function shape(run: CssRun): string {
	return run.keyframes.map(
		(k: WaapiKeyframe): string => k.offset.toString() + "=" + k.value + "@" +
			k.easing,
	).join(" | ");
}

test "translateX and translateY merge into one translate animation at the union of their offsets" {
	const run = onlyRun(
		planWaapi(
			single(
				[
					ramp("translateY", [0, 500, 1000], [0, 20, 40]),
					ramp("translateX", [0, 1000], [0, 100]),
				],
			),
			options(),
			[],
		),
	);
	assert run.route === TrackRoute.Waapi && run.css === "translate";
	assert run.properties.join(",") === "translateX,translateY";
	assert shape(run) ===
		"0=0px 0px@linear | 0.5=50px 20px@linear | 1=100px 40px@linear", shape(run);
}

test "a curve shared by both axes, or beside a constant axis, merges exactly" {
	const same = onlyRun(
		planWaapi(
			single(
				[
					track(
						"box",
						"scaleX",
						[key("a", 0, numberValue(1)), key("b", 1000, numberValue(2))],
					),
					track(
						"box",
						"scaleY",
						[key("a", 0, numberValue(1)), key("b", 1000, numberValue(3))],
					),
				],
			),
			options(),
			[],
		),
	);
	assert shape(same) ===
		"0=1 1@cubic-bezier(0.25, 0.9, 0.6, 0.1) | 1=2 3@linear", shape(same);
	const still = onlyRun(
		planWaapi(
			single(
				[
					ramp("translateX", [0, 1000], [5, 5]),
					track(
						"box",
						"translateY",
						[key("a", 0, numberValue(0)), key("b", 1000, numberValue(9))],
					),
				],
			),
			options(),
			[],
		),
	);
	assert shape(still) ===
		"0=5px 0px@cubic-bezier(0.25, 0.9, 0.6, 0.1) | 1=5px 9px@linear", shape(still);
}

test "axes whose curves split or differ have no exact merge and run together on the evaluator" {
	const split = planWaapi(
		single(
			[
				track(
					"box",
					"translateX",
					[key("a", 0, numberValue(0)), key("b", 1000, numberValue(100))],
				),
				ramp("translateY", [0, 500, 1000], [0, 20, 40]),
			],
		),
		options(),
		[],
	);
	assert onlyRun(split).route === TrackRoute.Style;
	assert split.tracks.every((t: RoutedTrack): boolean => t.route === TrackRoute.Style);
	const differ = planWaapi(
		single(
			[
				track(
					"box",
					"translateX",
					[key("a", 0, numberValue(0)), key("b", 1000, numberValue(100))],
				),
				ramp("translateY", [0, 1000], [0, 40]),
			],
		),
		options(),
		[],
	);
	assert onlyRun(differ).route === TrackRoute.Style;
}
