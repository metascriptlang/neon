@compile("../../ios/entry.m", "-fobjc-arc");

import { Motion } from "../../components/motion";
import { runApp } from "../../../src/platform/native/host";

runApp(Motion);
