@compile("../../ios/entry.m", "-fobjc-arc");

import { ScrollList } from "../../components/scrollList";
import { runApp } from "../../../src/platform/native/host";

runApp(ScrollList);
