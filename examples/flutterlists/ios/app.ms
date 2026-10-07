@compile("../../ios/entry.m", "-fobjc-arc");

import { FlutterLists } from "../../components/flutterLists";
import { runApp } from "../../../src/platform/native/host";

runApp(FlutterLists);
