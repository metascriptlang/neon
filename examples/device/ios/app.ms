@compile("../../ios/entry.m", "-fobjc-arc");

import { DeviceDemo } from "../../components/device";
import { runApp } from "../../../src/platform/native/host";

runApp(DeviceDemo);
