package dev.metascript.neon;

import android.app.Activity;
import android.content.Context;
import android.media.AudioAttributes;
import android.media.MediaPlayer;
import android.media.PlaybackParams;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import java.io.IOException;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

final class Sounds {
	static final int REPLY = 9;
	static final int STATUS = 13;
	private static final String FIELD = "\u001f";
	private static final Handler main = new Handler(Looper.getMainLooper());
	private static final Map<String, Sound> sounds = new HashMap<>();
	private static final Set<String> COMMANDS = new HashSet<>(Arrays.asList(
		"play", "pause", "stop", "seek", "volume", "loop", "mute", "rate", "interval", "status", "unload"));

	private static final class Sound implements Runnable {
		final String id;
		final String uri;
		final MediaPlayer player = new MediaPlayer();
		String request;
		boolean prepared;
		boolean buffering;
		boolean finished;
		boolean looping;
		boolean muted;
		double volume = 1;
		double rate = 1;
		int interval = 500;
		String error = "";

		Sound(String id, String uri) {
			this.id = id;
			this.uri = uri;
		}

		@Override public void run() {
			if (!prepared) return;
			if (player.isPlaying()) App.event(STATUS, id + FIELD + status());
			main.postDelayed(this, interval);
		}

		String status() {
			boolean playing = prepared && player.isPlaying();
			int duration = prepared ? Math.max(0, player.getDuration()) : 0;
			int position = !prepared ? 0 : finished ? duration : player.getCurrentPosition();
			return String.join(FIELD, prepared ? "1" : "0", playing ? "1" : "0", buffering ? "1" : "0",
				Integer.toString(position), Integer.toString(duration), finished ? "1" : "0", looping ? "1" : "0",
				Controls.number(volume), muted ? "1" : "0", Controls.number(rate), error);
		}

		void apply() {
			float level = muted ? 0 : (float) volume;
			player.setVolume(level, level);
			player.setLooping(looping);
		}

		void speed() {
			if (Build.VERSION.SDK_INT >= 23) player.setPlaybackParams(new PlaybackParams().setSpeed((float) rate));
		}

		void play() {
			speed();
			if (!player.isPlaying()) player.start();
		}

		void seek(long millis) {
			if (Build.VERSION.SDK_INT >= 26) player.seekTo(millis, MediaPlayer.SEEK_CLOSEST);
			else player.seekTo((int) millis);
		}

		void answer(String reply) {
			String id = request;
			request = null;
			if (id != null) main.post(() -> App.event(REPLY, id + FIELD + reply));
		}

		void release() {
			prepared = false;
			main.removeCallbacks(this);
			player.release();
		}

		void fail(String message) {
			sounds.remove(id);
			release();
			if (request != null) {
				answer("!Sound.loadAsync: cannot load " + uri + ": " + message);
				return;
			}
			error = message;
			App.event(STATUS, id + FIELD + status());
		}
	}

	private Sounds() {}

	static String call(Activity a, String name, String arg) {
		if ("audio.mode".equals(name)) return "";
		if ("sound.load".equals(name)) return load(a.getApplicationContext(), arg.split(FIELD, -1));
		String command = name.startsWith("sound.") ? name.substring("sound.".length()) : "";
		if (!COMMANDS.contains(command)) throw new IllegalArgumentException("Neon App.call: unknown command " + name);
		int split = arg.indexOf(FIELD);
		String id = split < 0 ? arg : arg.substring(0, split);
		double value = split < 0 ? 0 : Double.parseDouble(arg.substring(split + 1));
		Sound sound = sounds.get(id);
		if (sound == null || (!sound.prepared && !"unload".equals(command))) return "!Sound: no loaded sound " + id;
		return command(sound, command, value);
	}

	private static String command(Sound sound, String command, double value) {
		MediaPlayer player = sound.player;
		switch (command) {
			case "play": sound.play(); break;
			case "pause": if (player.isPlaying()) player.pause(); break;
			case "stop":
				if (player.isPlaying()) player.pause();
				sound.seek(0);
				break;
			case "seek": sound.seek((long) value); break;
			case "volume": sound.volume = Math.max(0, Math.min(1, value)); sound.apply(); break;
			case "loop": sound.looping = value != 0; sound.apply(); break;
			case "mute": sound.muted = value != 0; sound.apply(); break;
			case "rate":
				sound.rate = value;
				if (player.isPlaying()) sound.speed();
				break;
			case "interval":
				sound.interval = Math.max(16, (int) value);
				main.removeCallbacks(sound);
				main.postDelayed(sound, sound.interval);
				break;
			case "status": break;
			case "unload":
				sounds.remove(sound.id);
				sound.release();
				sound.answer("!Sound.loadAsync: the sound was unloaded before it loaded");
				break;
			default: throw new IllegalArgumentException("Neon App.call: unknown command sound." + command);
		}
		return sound.status();
	}

	private static String load(Context context, String[] fields) {
		if (fields.length != 10) throw new IllegalArgumentException("Neon sound.load: malformed request " + String.join(FIELD, fields));
		String request = fields[0];
		String id = fields[1];
		String uri = fields[2];
		boolean play = "1".equals(fields[3]);
		long position = (long) Double.parseDouble(fields[7]);
		Sound old = sounds.remove(id);
		if (old != null) {
			old.release();
			old.answer("!Sound.loadAsync: the sound was replaced before it loaded");
		}
		Sound sound = new Sound(id, uri);
		sound.volume = Math.max(0, Math.min(1, Double.parseDouble(fields[4])));
		sound.looping = "1".equals(fields[5]);
		sound.muted = "1".equals(fields[6]);
		sound.rate = Double.parseDouble(fields[8]);
		sound.interval = Math.max(16, (int) Double.parseDouble(fields[9]));
		MediaPlayer player = sound.player;
		player.setAudioAttributes(new AudioAttributes.Builder()
			.setUsage(AudioAttributes.USAGE_MEDIA)
			.setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
			.build());
		player.setOnPreparedListener(mp -> {
			if (sounds.get(id) != sound) return;
			sound.prepared = true;
			sound.apply();
			if (position > 0) sound.seek(position);
			if (play) sound.play();
			main.postDelayed(sound, sound.interval);
			sound.answer(sound.status());
		});
		player.setOnErrorListener((mp, what, extra) -> {
			if (sounds.get(id) == sound) sound.fail("MediaPlayer error " + what + " (" + extra + ")");
			return true;
		});
		player.setOnInfoListener((mp, what, extra) -> {
			if (what == MediaPlayer.MEDIA_INFO_BUFFERING_START) sound.buffering = true;
			else if (what == MediaPlayer.MEDIA_INFO_BUFFERING_END) sound.buffering = false;
			return false;
		});
		player.setOnCompletionListener(mp -> {
			if (sounds.get(id) != sound || sound.looping) return;
			sound.finished = true;
			App.event(STATUS, id + FIELD + sound.status());
			sound.finished = false;
		});
		try {
			String source = Movie.playable(context, uri);
			if (source.startsWith("/")) player.setDataSource(source);
			else player.setDataSource(context, Uri.parse(source));
		} catch (IOException | RuntimeException e) {
			player.release();
			return "!Sound.loadAsync: cannot load " + uri + ": " + Capture.message(e);
		}
		sound.request = request;
		sounds.put(id, sound);
		player.prepareAsync();
		return "";
	}
}
