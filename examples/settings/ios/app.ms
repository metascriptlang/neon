@compile("../../ios/entry.m", "-fobjc-arc");

import { SettingsApp } from "../../components/settings";
import { runApp } from "../../../src/platform/native/host";

runApp(SettingsApp);
