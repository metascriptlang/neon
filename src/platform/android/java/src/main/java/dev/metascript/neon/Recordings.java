package dev.metascript.neon;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.media.MediaRecorder;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import java.io.File;
import java.io.IOException;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

final class Recordings {
	static final int STATUS = 14;
	private static final String FIELD = "\u001f";
	private static final Handler main = new Handler(Looper.getMainLooper());
	private static final Map<String, Recording> recordings = new HashMap<>();
	private static final Set<String> COMMANDS = new HashSet<>(Arrays.asList("start", "pause", "stop", "status", "interval"));

	private static final class Recording implements Runnable {
		final String id;
		final File file;
		MediaRecorder recorder;
		int interval;
		boolean started;
		boolean recording;
		boolean done;
		long accumulated;
		long since;

		Recording(String id, File file, MediaRecorder recorder, int interval) {
			this.id = id;
			this.file = file;
			this.recorder = recorder;
			this.interval = interval;
		}

		@Override public void run() {
			if (!recording) return;
			App.event(STATUS, id + FIELD + status());
			main.postDelayed(this, interval);
		}

		long duration() {
			return accumulated + (recording ? SystemClock.elapsedRealtime() - since : 0);
		}

		String status() {
			return String.join(FIELD, done ? "0" : "1", recording ? "1" : "0", done ? "1" : "0",
				Long.toString(duration()), Uri.fromFile(file).toString(), "");
		}

		void tick() {
			main.removeCallbacks(this);
			if (recording) main.postDelayed(this, interval);
		}

		void release() {
			main.removeCallbacks(this);
			if (recorder != null) recorder.release();
			recorder = null;
		}

		void discard() {
			release();
			file.delete();
			recordings.remove(id);
		}
	}

	private Recordings() {}

	static String call(Activity a, String name, String arg) {
		if ("recording.prepare".equals(name)) return prepare(a, arg.split(FIELD, -1));
		String command = name.startsWith("recording.") ? name.substring("recording.".length()) : "";
		if (!COMMANDS.contains(command)) throw new IllegalArgumentException("Neon App.call: unknown command " + name);
		int split = arg.indexOf(FIELD);
		String id = split < 0 ? arg : arg.substring(0, split);
		double value = split < 0 ? 0 : Double.parseDouble(arg.substring(split + 1));
		Recording recording = recordings.get(id);
		if (recording == null) return "!Recording: no prepared recording " + id;
		return command(recording, command, value);
	}

	private static String command(Recording r, String command, double value) {
		switch (command) {
			case "start": {
				if (r.done) return "!Recording: the recording is already stopped";
				if (r.recording) break;
				try {
					if (!r.started) r.recorder.start();
					else if (Build.VERSION.SDK_INT >= 24) r.recorder.resume();
				} catch (RuntimeException e) {
					return "!Recording: cannot start the recorder: " + Capture.message(e);
				}
				r.started = true;
				r.recording = true;
				r.since = SystemClock.elapsedRealtime();
				r.tick();
				break;
			}
			case "pause": {
				if (Build.VERSION.SDK_INT < 24) return "!Recording.pauseAsync needs Android 7.0";
				if (!r.recording) break;
				try {
					r.recorder.pause();
				} catch (RuntimeException e) {
					return "!Recording: cannot pause the recorder: " + Capture.message(e);
				}
				r.accumulated = r.duration();
				r.recording = false;
				r.tick();
				break;
			}
			case "stop": {
				if (r.done) break;
				r.accumulated = r.duration();
				r.recording = false;
				if (!r.started) {
					r.discard();
					return "!Recording: the recording was too short to save";
				}
				try {
					r.recorder.stop();
				} catch (RuntimeException e) {
					r.discard();
					return "!Recording: the recording was too short to save";
				}
				r.release();
				r.done = true;
				break;
			}
			case "status": break;
			case "interval":
				r.interval = Math.max(16, (int) value);
				r.tick();
				break;
			default: throw new IllegalArgumentException("Neon App.call: unknown command recording." + command);
		}
		return r.status();
	}

	@SuppressWarnings("deprecation")
	private static MediaRecorder recorder(Context context) {
		return Build.VERSION.SDK_INT >= 31 ? new MediaRecorder(context) : new MediaRecorder();
	}

	private static String prepare(Activity a, String[] fields) {
		if (fields.length != 7) throw new IllegalArgumentException("Neon recording.prepare: malformed request " + String.join(FIELD, fields));
		String id = fields[1];
		if (!Permissions.granted(a, Manifest.permission.RECORD_AUDIO)) return "!Recording: the microphone permission is not granted";
		Recording old = recordings.get(id);
		if (old != null) {
			if (old.done) {
				old.release();
				recordings.remove(id);
			} else {
				old.discard();
			}
		}
		File file = new File(Capture.directory(a, "Audio"), "recording-" + UUID.randomUUID() + fields[2]);
		int sampleRate = (int) Double.parseDouble(fields[3]);
		int channels = (int) Double.parseDouble(fields[4]);
		int bitRate = (int) Double.parseDouble(fields[5]);
		int interval = Math.max(16, (int) Double.parseDouble(fields[6]));
		MediaRecorder recorder = recorder(a.getApplicationContext());
		try {
			recorder.setAudioSource(MediaRecorder.AudioSource.MIC);
			recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);
			recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);
			if (sampleRate > 0) recorder.setAudioSamplingRate(sampleRate);
			if (channels > 0) recorder.setAudioChannels(channels);
			if (bitRate > 0) recorder.setAudioEncodingBitRate(bitRate);
			recorder.setOutputFile(file.getPath());
			recorder.prepare();
		} catch (IOException | RuntimeException e) {
			recorder.release();
			file.delete();
			return "!Recording: cannot prepare the recorder: " + Capture.message(e);
		}
		Recording recording = new Recording(id, file, recorder, interval);
		recordings.put(id, recording);
		return recording.status();
	}
}
