// Pulse's conformance suite on real Core Animation, read from each view's presentation layer.
//   msc build examples/macosNative/ionConformance.ms --output=out/macosIonConformance
//   out/macosIonConformance    prints the adapter's table and exits with the failure count

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { MotionConformance } from "../layerMotion/conformance";
import { exit } from "std/process";

const options = nativeWindowOptions("Neon conformance on Core Animation", 400, 200);
options.topmost = true;
exit(runNativeWindow(options, MotionConformance, null));
