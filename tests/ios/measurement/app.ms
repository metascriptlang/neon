@compile("../../../examples/ios/entry.m", "-fobjc-arc");

import { MeasurementApp } from "../../platform/measurementApp";
import { runApp } from "../../../src/platform/native/host";

runApp(MeasurementApp);
