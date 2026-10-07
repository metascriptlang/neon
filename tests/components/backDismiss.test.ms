// The Android back button closes a shown Dialog or BottomSheet (react-native-paper Modal).

import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Text, View } from "../../src/components/primitives";
import { Dialog } from "../../src/components/dialog";
import { BottomSheet } from "../../src/components/bottomSheet";
import { dispatchHardwareBackPress } from "../../src/api/backHandler";

test "Dialog and BottomSheet close on the Android back button while shown, and only then" {
	const [dialog, setDialog] = createSignal(false);
	const [sheet, setSheet] = createSignal(false);
	const [locked, setLocked] = createSignal(false);
	const [log, setLog] = createSignal("");
	const root: MockNode = mockNode("root");
	render(element(<View>
		<Dialog visible={dialog()} title="Delete?" dismissable={!locked()} onDismiss={(): void => { setLog(log() + "dialog;"); setDialog(false); }} />
		<BottomSheet visible={sheet()} onDismiss={(): void => { setLog(log() + "sheet;"); setSheet(false); }}><Text>Share</Text></BottomSheet>
	</View>), mockHost(), root as unknown as HostNode);
	const idle = dispatchHardwareBackPress();
	setDialog(true);
	const closed = dispatchHardwareBackPress();
	setSheet(true);
	const sheetClosed = dispatchHardwareBackPress();
	setLocked(true);
	setDialog(true);
	const held = dispatchHardwareBackPress();
	const stillOpen = dialog();
	setDialog(false);
	const after = dispatchHardwareBackPress();
	assert !idle && !after, `the platform default runs while nothing is shown: ${idle} ${after}`;
	assert closed && sheetClosed && held, "a shown overlay consumes the back press";
	assert log() === "dialog;sheet;", "each closes through its onDismiss: " + log();
	assert stillOpen, "a non-dismissable dialog stays";
}
