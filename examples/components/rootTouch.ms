import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { Show } from "../../src/macros/ui/flow";
import { NeonEvent } from "../../src/render/event";
import { View, Text, Pressable, ScrollView } from "../../src/components/primitives";
import { Switch } from "../../src/components/switch";
import { PanResponder, PanResponderGestureState } from "../../src/components/panResponder";

when (ios) {
	import { rootTouchCancel } from "../rootTouch/ios/rootTouchHarness.h";
}

export function RootTouchFixture(): NeonNode {
	let grants: int32 = 0;
	let releases: int32 = 0;
	let capturedChanges: int32 = 0;
	let plainChanges: int32 = 0;
	const [status, setStatus] = createSignal("grants 0 releases 0 captured 0 plain 0");
	const report = (): void => {
		setStatus(`grants ${grants} releases ${releases} captured ${capturedChanges} plain ${plainChanges}`);
	};
	let presses: int32 = 0;
	let pressIns: int32 = 0;
	let pressOuts: int32 = 0;
	let innerPresses: int32 = 0;
	let outerPresses: int32 = 0;
	let scrollStarts: int32 = 0;
	let scrollMoves: int32 = 0;
	let scrollEnds: int32 = 0;
	const [routes, setRoutes] = createSignal("press 0 in 0 out 0 inner 0 outer 0 scrollStart 0 scrollMove 0 scrollEnd 0");
	const reportRoutes = (): void => {
		setRoutes(`press ${presses} in ${pressIns} out ${pressOuts} inner ${innerPresses} outer ${outerPresses} scrollStart ${scrollStarts} scrollMove ${scrollMoves} scrollEnd ${scrollEnds}`);
	};
	let scrollPresses: int32 = 0;
	let scrollIns: int32 = 0;
	let scrollLongs: int32 = 0;
	let scrollOuts: int32 = 0;
	const [scrollPressStatus, setScrollPressStatus] = createSignal("scrollPress 0 in 0 long 0 out 0");
	const reportScrollPress = (): void => {
		setScrollPressStatus(`scrollPress ${scrollPresses} in ${scrollIns} long ${scrollLongs} out ${scrollOuts}`);
	};
	let cancelStarts: int32 = 0;
	let cancels: int32 = 0;
	let cancelEnds: int32 = 0;
	const [cancelStatus, setCancelStatus] = createSignal("cancelStart 0 cancel 0 end 0");
	const reportCancel = (): void => {
		setCancelStatus(`cancelStart ${cancelStarts} cancel ${cancels} end ${cancelEnds}`);
	};
	let cleanupStarts: int32 = 0;
	let cleanupEnds: int32 = 0;
	const [cleanupVisible, setCleanupVisible] = createSignal(true);
	const [cleanupStatus, setCleanupStatus] = createSignal("cleanupStart 0 end 0");
	const reportCleanup = (): void => { setCleanupStatus(`cleanupStart ${cleanupStarts} end ${cleanupEnds}`); };
	const pan = PanResponder.create({
		onStartShouldSetPanResponderCapture: (e: NeonEvent, g: PanResponderGestureState): boolean => true,
		onPanResponderGrant: (e: NeonEvent, g: PanResponderGestureState): void => { grants += 1; report(); },
		onPanResponderRelease: (e: NeonEvent, g: PanResponderGestureState): void => { releases += 1; report(); },
	});
	return element(<View style={{ flex: 1, padding: 24, backgroundColor: "#ffffff", gap: 12 }}>
		<Text>{status()}</Text>
		<View {...pan.panHandlers} style={{ height: 80, justifyContent: "center" }}>
			<Switch accessibilityLabel="captured-switch" value={false}
				onValueChange={(value: boolean): void => { capturedChanges += 1; report(); }} />
		</View>
		<Switch accessibilityLabel="plain-switch" value={false}
			onValueChange={(value: boolean): void => { plainChanges += 1; report(); }} />
		<Text style={{ fontSize: 11 }}>{routes()}</Text>
		<Pressable accessibilityLabel="root-press" accessibilityRole="button" hitSlop={20}
			style={{ width: 120, height: 48, alignSelf: "center", transform: "translateX(20px)", backgroundColor: "#dddddd" }}
			onPress={(e: NeonEvent): void => { presses += 1; reportRoutes(); }}
			onPressIn={(e: NeonEvent): void => { pressIns += 1; reportRoutes(); }}
			onPressOut={(e: NeonEvent): void => { pressOuts += 1; reportRoutes(); }}>
			<View accessibilityLabel="root-press-child" onLayout={(e: NeonEvent): void => {}}
				style={{ flex: 1, justifyContent: "center", alignItems: "center" }}>
				<Text>press child</Text>
			</View>
		</Pressable>
		<Text style={{ fontSize: 18 }} onPress={(e: NeonEvent): void => { outerPresses += 1; reportRoutes(); }}>
			<Text onPress={(e: NeonEvent): void => { innerPresses += 1; reportRoutes(); }}>inner</Text> outer
		</Text>
		<Text>{scrollPressStatus()}</Text>
		<View style={{ height: 110 }}
			onTouchStart={(e: NeonEvent): void => { scrollStarts += 1; reportRoutes(); }}
			onTouchMove={(e: NeonEvent): void => { scrollMoves += 1; reportRoutes(); }}
			onTouchEnd={(e: NeonEvent): void => { scrollEnds += 1; reportRoutes(); }}>
			<ScrollView style={{ flex: 1 }}>
				<Pressable accessibilityLabel="scroll-press" accessibilityRole="button"
					style={{ height: 44, backgroundColor: "#dddddd" }}
					onPress={(): void => { scrollPresses += 1; reportScrollPress(); }}
					onPressIn={(): void => { scrollIns += 1; reportScrollPress(); }}
					onPressOut={(): void => { scrollOuts += 1; reportScrollPress(); }}
					onLongPress={(): void => { scrollLongs += 1; reportScrollPress(); }}>
					<Text>scroll press target</Text>
				</Pressable>
				<Text style={{ height: 60 }}>scroll first</Text>
				<View style={{ height: 380 }} />
				<Text style={{ height: 60 }}>scroll last</Text>
			</ScrollView>
		</View>
		<Text>{cancelStatus()}</Text>
		<View accessibilityLabel="cancel-target" accessible={true} style={{ height: 48, backgroundColor: "#dddddd" }}
			onTouchStart={(e: NeonEvent): void => { cancelStarts += 1; reportCancel(); }}
			onTouchMove={(e: NeonEvent): void => { when (ios) { rootTouchCancel(); } }}
			onTouchCancel={(e: NeonEvent): void => { cancels += 1; reportCancel(); }}
			onTouchEnd={(e: NeonEvent): void => { cancelEnds += 1; reportCancel(); }}><Text>cancel target</Text></View>
		<Text>{cleanupStatus()}</Text>
		<Show when={cleanupVisible()}>
			<View accessibilityLabel="cleanup-target" accessible={true} style={{ height: 32 }}
				onTouchStart={(e: NeonEvent): void => { cleanupStarts += 1; reportCleanup(); setCleanupVisible(false); }}
				onTouchEnd={(e: NeonEvent): void => { cleanupEnds += 1; reportCleanup(); }}><Text>cleanup target</Text></View>
		</Show>
		<Pressable accessibilityLabel="restore-target" accessibilityRole="button" style={{ height: 32 }}
			onPress={(e: NeonEvent): void => { setCleanupVisible(true); }}><Text>restore target</Text></Pressable>
	</View>);
}
