import { Accessor, createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { Style } from "../../src/render/style";
import { View, Text, ScrollView } from "../../src/components/primitives";
import { Button } from "../../src/components/button";
import { Slider } from "../../src/components/slider";
import { Picker, PickerItem } from "../../src/components/picker";
import { DateTimePicker } from "../../src/components/dateTimePicker";
import { Checkbox } from "../../src/components/checkbox";
import { RadioGroup, RadioOption } from "../../src/components/radio";
import { SegmentedControl } from "../../src/components/segmentedControl";
import { Chip } from "../../src/components/chip";
import { Card, CardTitle, CardContent } from "../../src/components/card";
import { Avatar } from "../../src/components/avatar";
import { Badge } from "../../src/components/badge";
import { Divider } from "../../src/components/divider";
import { Snackbar } from "../../src/components/snackbar";
import { Toast, ToastHost } from "../../src/components/toast";
import { Tooltip } from "../../src/components/tooltip";
import { Dialog, DialogAction } from "../../src/components/dialog";
import { BottomSheet } from "../../src/components/bottomSheet";
import { ProgressBar } from "../../src/components/progressBar";
import { Show } from "../../src/macros/ui/flow";

const ROOMS: PickerItem[] = [
	{ label: "Standard", value: "standard" },
	{ label: "Deluxe", value: "deluxe" },
	{ label: "Suite", value: "suite" },
];

const PAYMENTS: RadioOption[] = [
	{ label: "Card", value: "card" },
	{ label: "Cash", value: "cash" },
	{ label: "Transfer", value: "transfer" },
];

const TRIPS: string[] = ["Leisure", "Business"];
const PREFERENCES: string[] = ["Sea view", "Quiet", "High floor"];
const BOOKING_MS: int32 = 1500;

const label: Style = { color: "#49454f", fontSize: 13 };
const value: Style = { color: "#1c1b1f", fontSize: 16 };
const section: Style = { gap: 8, paddingLeft: 16, paddingRight: 16, paddingTop: 12, paddingBottom: 12 };
const row: Style = { flexDirection: "row", alignItems: "center", gap: 12 };

function roomLabel(room: string): string {
	for (const r of ROOMS) {
		if (r.value === room) { return r.label; }
	}
	return room;
}

function Field(props: { title: Accessor<string>; children: NeonNode }): NeonNode {
	return <View style={section}>
		<Text style={label} accessibilityRole="header">{props.title()}</Text>
		{props.children}
	</View>;
}

export function BookingForm(): NeonNode {
	const [checkIn, setCheckIn] = createSignal("2026-10-09");
	const [arrival, setArrival] = createSignal("15:00");
	const [guests, setGuests] = createSignal(2.0 as float64);
	const [room, setRoom] = createSignal("standard");
	const [trip, setTrip] = createSignal(0 as int32);
	const [breakfast, setBreakfast] = createSignal(false);
	const [parking, setParking] = createSignal(false);
	const [payment, setPayment] = createSignal("card");
	const [prefs, setPrefs] = createSignal([] as string[]);
	const [status, setStatus] = createSignal("idle");
	const [confirming, setConfirming] = createSignal(false);
	const [details, setDetails] = createSignal(false);
	const [booked, setBooked] = createSignal(false);

	const guestCount = (): int32 => Math.round(guests()) as int32;
	const extras = (): string => {
		let out = "";
		if (breakfast()) { out = "breakfast"; }
		if (parking()) { out += out === "" ? "parking" : ", parking"; }
		return out === "" ? "none" : out;
	};
	const togglePref = (p: string): void => {
		const next: string[] = [];
		let had = false;
		for (const q of prefs()) {
			if (q === p) { had = true; } else { next.push(q); }
		}
		if (!had) { next.push(p); }
		setPrefs(next);
	};
	const hasPref = (p: string): boolean => prefs().indexOf(p) >= 0;
	const summary = (): string => `${roomLabel(room())} for ${guestCount()} guests from ${checkIn()} ${arrival()}`;
	const confirm = (): void => {
		setConfirming(false);
		setStatus("booking");
		setTimeout((): void => {
			setStatus("booked");
			setBooked(true);
		}, BOOKING_MS);
	};
	const undo = (): void => {
		setBooked(false);
		setStatus("cancelled");
		Toast.show({ text1: "Booking cancelled", text2: summary(), type: "info" });
	};

	return <View style={{ flex: 1, backgroundColor: "#fef7ff" }}>
		<View style={{ paddingLeft: 16, paddingRight: 16, paddingTop: 12, paddingBottom: 8, gap: 4 }}>
			<Text style={{ color: "#1c1b1f", fontSize: 26, fontWeight: "bold" }} accessibilityRole="header">Neon booking</Text>
			<Text style={label}>{`status ${status()}`}</Text>
			<Show when={status() === "booking"}>
				<ProgressBar indeterminate={true} color="#6750a4" accessibilityLabel="Booking in progress" />
			</Show>
		</View>
		<ScrollView style={{ flex: 1 }}>
			<Card style={{ marginLeft: 16, marginRight: 16, marginTop: 4 }}>
				<View style={{ ...row, paddingLeft: 16, paddingTop: 16 }}>
					<Avatar label="SH" backgroundColor="#6750a4" accessibilityLabel="Seaside Hotel" />
					<View style={{ flex: 1 }}>
						<CardTitle title="Seaside Hotel" subtitle="Da Nang, 4 stars" />
					</View>
					<View style={{ paddingRight: 16 }}>
						<Badge value={`${guestCount()}`} accessibilityLabel={`${guestCount()} guests`} />
					</View>
				</View>
				<CardContent>
					<Text style={value}>{summary()}</Text>
				</CardContent>
			</Card>
			<Field title="Check-in">
				<View style={row}>
					<DateTimePicker value={checkIn()} minimumDate="2026-10-01" accessibilityLabel="Check-in date"
						onChange={(v: string): void => { setCheckIn(v); }} />
					<DateTimePicker value={arrival()} mode="time" accessibilityLabel="Arrival time"
						onChange={(v: string): void => { setArrival(v); }} />
				</View>
				<Text style={value}>{`check-in ${checkIn()} at ${arrival()}`}</Text>
			</Field>
			<Divider inset={true} />
			<Field title="Guests">
				<View style={row}>
					<Text style={{ ...value, flex: 1 }}>{`guests ${guestCount()}`}</Text>
					<Tooltip title="Up to 8 guests per room">
						<Text style={{ color: "#6750a4", fontSize: 16 }} accessibilityLabel="Guest limit">ⓘ</Text>
					</Tooltip>
				</View>
				<Slider value={guests()} minimumValue={1} maximumValue={8} step={1} accessibilityLabel="Guests"
					minimumTrackTintColor="#6750a4" onValueChange={(v: float64): void => { setGuests(v); }} />
			</Field>
			<Divider inset={true} />
			<Field title="Room">
				<Picker items={ROOMS} selectedValue={room()} prompt="Room type" accessibilityLabel="Room type"
					onValueChange={(v: string, i: int32): void => { setRoom(v); }} />
				<Text style={value}>{`room ${roomLabel(room())}`}</Text>
			</Field>
			<Field title="Trip">
				<SegmentedControl values={TRIPS} selectedIndex={trip()} accessibilityLabel="Trip type"
					onChange={(i: int32): void => { setTrip(i); }} />
				<Text style={value}>{`trip ${TRIPS[trip()]}`}</Text>
			</Field>
			<Field title="Extras">
				<View style={row}>
					<Checkbox value={breakfast()} accessibilityLabel="Breakfast" onValueChange={(v: boolean): void => { setBreakfast(v); }} />
					<Text style={value}>Breakfast</Text>
				</View>
				<View style={row}>
					<Checkbox value={parking()} accessibilityLabel="Parking" onValueChange={(v: boolean): void => { setParking(v); }} />
					<Text style={value}>Parking</Text>
				</View>
				<Text style={value}>{`extras ${extras()}`}</Text>
			</Field>
			<Field title="Payment">
				<RadioGroup options={PAYMENTS} value={payment()} accessibilityLabel="Payment"
					onValueChange={(v: string): void => { setPayment(v); }} />
				<Text style={value}>{`payment ${payment()}`}</Text>
			</Field>
			<Field title="Preferences">
				<View style={{ ...row, flexWrap: "wrap", gap: 8 }}>
					<Chip label={PREFERENCES[0]} selected={hasPref(PREFERENCES[0])} onPress={(e: NeonEvent): void => { togglePref(PREFERENCES[0]); }} />
					<Chip label={PREFERENCES[1]} selected={hasPref(PREFERENCES[1])} onPress={(e: NeonEvent): void => { togglePref(PREFERENCES[1]); }} />
					<Chip label={PREFERENCES[2]} selected={hasPref(PREFERENCES[2])} onPress={(e: NeonEvent): void => { togglePref(PREFERENCES[2]); }} />
				</View>
				<Text style={value}>{`prefs ${prefs().length === 0 ? "none" : prefs().join(", ")}`}</Text>
			</Field>
			<View style={{ ...row, padding: 16, justifyContent: "flex-end" }}>
				<Button title="Details" color="#625b71" onPress={(e: NeonEvent): void => { setDetails(true); }} />
				<Button title="Book" color="#6750a4" disabled={status() === "booking"} onPress={(e: NeonEvent): void => { setConfirming(true); }} />
			</View>
		</ScrollView>
		<Snackbar visible={booked()} message={`Booked ${summary()}`} actionLabel="Undo" duration={8000}
			onActionPress={(): void => { undo(); }} onDismiss={(): void => { setBooked(false); }} />
		<BottomSheet visible={details()} onDismiss={(): void => { setDetails(false); }}>
			<View style={{ paddingLeft: 24, paddingRight: 24, gap: 8 }}>
				<Text style={{ color: "#1c1b1f", fontSize: 20, fontWeight: "bold" }} accessibilityRole="header">Booking details</Text>
				<Text style={value}>{`details ${summary()}`}</Text>
				<Text style={value}>{`extras ${extras()} · payment ${payment()}`}</Text>
				<Button title="Close" color="#6750a4" onPress={(e: NeonEvent): void => { setDetails(false); }} />
			</View>
		</BottomSheet>
		<Dialog visible={confirming()} title="Confirm booking" onDismiss={(): void => { setConfirming(false); }}
			actions={<View style={row}>
				<DialogAction label="Cancel" onPress={(): void => { setConfirming(false); }} />
				<DialogAction label="Confirm" onPress={(): void => { confirm(); }} />
			</View>}>
			<Text style={value}>{`confirm ${summary()}`}</Text>
		</Dialog>
		<ToastHost />
	</View>;
}
