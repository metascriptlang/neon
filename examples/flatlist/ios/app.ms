@compile("../../ios/entry.m", "-fobjc-arc");

import { ListAcceptance } from "../../components/bigList";
import { runApp } from "../../../src/platform/native/host";

runApp(ListAcceptance);
