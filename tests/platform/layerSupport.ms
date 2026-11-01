import { ConformanceCase, ConformanceSupport } from "pulse/src/conformance";

// native.ms planLayers: a player that repeats with a repeat delay is not handable.
const REPEAT_DELAY: string[] = ["time.repeat"];
// NativeRuns.alignAll hands a run over only while the player runs; these stay paused.
const PAUSED_PLAYERS: string[] = ["seek.silent", "seek.events"];
// neon.ms useAnimatedValue: a value that is not Replace runs through signals, not the layer.
const NOT_REPLACE: string[] = ["contention.blend", "contention.none"];
// NativeElementValue.animate hands over spring and timing only.
const UNHANDED_SPECS: string[] = ["decay", "sequence"];
// The reads are derived values Pulse computes on the app thread.
const DERIVED_READS: string[] = ["derived", "derived.color"];

export function layerSupport(testCase: ConformanceCase): ConformanceSupport {
	const name = testCase.name;
	const evaluated = REPEAT_DELAY.includes(name) || PAUSED_PLAYERS.includes(name) ||
		NOT_REPLACE.includes(name) || UNHANDED_SPECS.includes(name) || DERIVED_READS.includes(name);
	return evaluated ? ConformanceSupport.Evaluator : ConformanceSupport.Engine;
}
