@compile("../../ios/entry.m", "-fobjc-arc");

import { BookingForm } from "../../components/controls";
import { runApp } from "../../../src/platform/native/host";

runApp(BookingForm);
