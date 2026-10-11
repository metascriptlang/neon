@compile("../../ios/entry.m", "-fobjc-arc");

import { CatalogApp } from "../../components/catalog";
import { runApp } from "../../../src/platform/native/host";

runApp(CatalogApp);
