import { niAppCall } from "./app.h";
import { requestReply } from "./deviceServices";
import { TextSlot } from "../../api/replySlot";
import {
	CaptureServices, PickReply, PickRequest, PickedAsset, RecordingSetup, RecordingState, SoundSetup, SoundState,
	idleRecording, unloadedSound,
} from "../../api/captureServices";

const FIELD = "\u001f";
const RECORD = "\u001e";

function call(name: string, arg: string): string {
	const reply: string = niAppCall(name, arg);
	return reply;
}

async function ask(name: string, arg: string): Promise<string> {
	const slot = new TextSlot();
	requestReply(name, arg, (reply: string): void => { slot.settle(reply); });
	return await slot.wait();
}

function flag(value: boolean): string {
	return value ? "1" : "0";
}

function refusal(reply: string): string {
	return reply.startsWith("!") ? reply.substring(1, reply.length) : "";
}

function amount(text: string): number {
	return text === "" ? -1 : parseFloat(text);
}

export function decodeAsset(record: string): PickedAsset {
	const fields = record.split(FIELD);
	if (fields.length !== 9) { throw new Error("ImagePicker: the host sent a malformed asset: " + record); }
	return {
		uri: fields[0],
		width: amount(fields[1]),
		height: amount(fields[2]),
		type: fields[3],
		fileName: fields[4],
		fileSize: amount(fields[5]),
		mimeType: fields[6],
		duration: amount(fields[7]),
		base64: fields[8],
	};
}

export function decodePick(reply: string): PickReply {
	const error = refusal(reply);
	if (error !== "") { return { canceled: false, assets: [], error }; }
	if (reply === "canceled") { return { canceled: true, assets: [], error: "" }; }
	const records = reply.split(RECORD);
	if (records[0] !== "ok") { throw new Error("ImagePicker: the host sent a malformed result: " + reply); }
	const assets: PickedAsset[] = [];
	for (let i = 1; i < records.length; i += 1) { assets.push(decodeAsset(records[i])); }
	return { canceled: assets.length === 0, assets, error: "" };
}

async function pickMedia(request: PickRequest): Promise<PickReply> {
	const reply = await ask("capture.pick", [
		flag(request.camera), flag(request.images), flag(request.videos), flag(request.allowsEditing),
		request.quality.toString(), flag(request.base64), flag(request.multiple), request.selectionLimit.toString(),
		request.cameraType,
	].join(FIELD));
	return decodePick(reply);
}

export function decodeSound(value: string): SoundState {
	const error = refusal(value);
	if (error !== "") { return unloadedSound(error); }
	const fields = value.split(FIELD);
	if (fields.length !== 11) { throw new Error("Sound: the host sent a malformed status: " + value); }
	return {
		isLoaded: fields[0] === "1",
		isPlaying: fields[1] === "1",
		isBuffering: fields[2] === "1",
		positionMillis: parseFloat(fields[3]),
		durationMillis: parseFloat(fields[4]),
		didJustFinish: fields[5] === "1",
		isLooping: fields[6] === "1",
		volume: parseFloat(fields[7]),
		isMuted: fields[8] === "1",
		rate: parseFloat(fields[9]),
		error: fields[10],
	};
}

interface SoundWatch {
	id: int32;
	update: (state: SoundState) => void;
}

const sounds: SoundWatch[] = [];

function forgetSound(id: int32): void {
	for (let i = 0; i < sounds.length; i += 1) {
		if (sounds[i].id === id) {
			sounds.splice(i, 1);
			return;
		}
	}
}

async function soundLoad(id: int32, setup: SoundSetup, update: (state: SoundState) => void): Promise<SoundState> {
	forgetSound(id);
	sounds.push({ id, update });
	const state = decodeSound(await ask("sound.load", [
		id.toString(), setup.uri, flag(setup.shouldPlay), setup.volume.toString(), flag(setup.isLooping),
		flag(setup.isMuted), setup.positionMillis.toString(), setup.rate.toString(),
		setup.progressUpdateIntervalMillis.toString(),
	].join(FIELD)));
	if (!state.isLoaded) { forgetSound(id); }
	return state;
}

function soundCommand(id: int32, command: string, value: number): SoundState {
	const state = decodeSound(call("sound." + command, id.toString() + FIELD + value.toString()));
	if (command === "unload") { forgetSound(id); }
	return state;
}

export function onSoundEvent(value: string): void {
	const split = value.indexOf(FIELD);
	const id = parseInt(value.substring(0, split)) as int32;
	const state = decodeSound(value.substring(split + 1, value.length));
	for (const watch of sounds.slice(0, sounds.length)) {
		if (watch.id === id) { watch.update(state); }
	}
}

async function audioMode(allowsRecording: boolean, playsInSilentMode: boolean): Promise<string> {
	return refusal(call("audio.mode", flag(allowsRecording) + FIELD + flag(playsInSilentMode)));
}

export function decodeRecording(value: string): RecordingState {
	const error = refusal(value);
	if (error !== "") { return idleRecording(error); }
	const fields = value.split(FIELD);
	if (fields.length !== 6) { throw new Error("Recording: the host sent a malformed status: " + value); }
	return {
		canRecord: fields[0] === "1",
		isRecording: fields[1] === "1",
		isDoneRecording: fields[2] === "1",
		durationMillis: parseFloat(fields[3]),
		uri: fields[4],
		error: fields[5],
	};
}

interface RecordingWatch {
	id: int32;
	update: (state: RecordingState) => void;
}

const recordings: RecordingWatch[] = [];

function forgetRecording(id: int32): void {
	for (let i = 0; i < recordings.length; i += 1) {
		if (recordings[i].id === id) {
			recordings.splice(i, 1);
			return;
		}
	}
}

async function recordingPrepare(id: int32, setup: RecordingSetup, update: (state: RecordingState) => void): Promise<RecordingState> {
	forgetRecording(id);
	recordings.push({ id, update });
	const state = decodeRecording(await ask("recording.prepare", [
		id.toString(), setup.extension, setup.sampleRate.toString(), setup.numberOfChannels.toString(),
		setup.bitRate.toString(), setup.progressUpdateIntervalMillis.toString(),
	].join(FIELD)));
	if (state.error !== "") { forgetRecording(id); }
	return state;
}

async function recordingCommand(id: int32, command: string, value: number): Promise<RecordingState> {
	const state = decodeRecording(call("recording." + command, id.toString() + FIELD + value.toString()));
	if (command === "stop") { forgetRecording(id); }
	return state;
}

export function onRecordingEvent(value: string): void {
	const split = value.indexOf(FIELD);
	const id = parseInt(value.substring(0, split)) as int32;
	const state = decodeRecording(value.substring(split + 1, value.length));
	for (const watch of recordings.slice(0, recordings.length)) {
		if (watch.id === id) { watch.update(state); }
	}
}

export const nativeCaptureServices: CaptureServices = {
	pickMedia,
	soundLoad,
	soundCommand,
	audioMode,
	recordingPrepare,
	recordingCommand,
};
