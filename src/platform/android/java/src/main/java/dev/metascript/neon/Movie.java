package dev.metascript.neon;

import android.content.Context;
import android.graphics.Matrix;
import android.graphics.SurfaceTexture;
import android.media.MediaPlayer;
import android.media.PlaybackParams;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;
import android.view.Surface;
import android.view.TextureView;
import android.widget.FrameLayout;
import android.widget.MediaController;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;

final class Movie extends FrameLayout implements Control, TextureView.SurfaceTextureListener {
	private int tag;
	private final TextureView texture;
	private final Handler main = new Handler(Looper.getMainLooper());
	private MediaPlayer player;
	private Surface surface;
	private MediaController controller;
	private String source = "";
	private boolean prepared;
	private boolean paused;
	private boolean muted;
	private boolean repeat;
	private float volume = 1;
	private float rate = 1;
	private int every = 250;
	private int buffered;
	private String mode = "contain";
	private int videoWidth;
	private int videoHeight;

	private final Runnable tick = new Runnable() {
		@Override public void run() {
			if (player == null || !prepared) return;
			if (player.isPlaying()) progress();
			main.postDelayed(this, every);
		}
	};

	Movie(Context context) {
		super(context);
		setBackgroundColor(0xff000000);
		texture = new TextureView(context);
		texture.setSurfaceTextureListener(this);
		addView(texture, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
	}

	@Override public void setNeonTag(int value) { tag = value; }

	private void emit(int phase, String value) {
		if (tag != 0) Props.control(tag, phase, value, 0, 0);
	}

	private static String seconds(int millis) { return Controls.number(millis / 1000.0); }

	private void progress() {
		int duration = player.getDuration();
		emit(13, seconds(player.getCurrentPosition()) + "\u001f" + seconds(duration * buffered / 100) + "\u001f" + seconds(duration));
	}

	// Native players take files, not data: URIs, and the app bundles no asset files, so a data:
	// URI is decoded once into the cache directory.
	static String playable(Context context, String uri) throws IOException {
		if (!uri.startsWith("data:")) return uri;
		int comma = uri.indexOf(',');
		String header = comma < 0 ? "" : uri.substring(5, comma);
		if (comma < 0 || !header.endsWith(";base64")) throw new IOException("the data: URI is not base64");
		String mime = header.substring(0, header.indexOf(';'));
		String extension = mime.equals("video/quicktime") ? "mov" : mime.equals("audio/mpeg") ? "mp3" : mime.startsWith("audio/") ? "m4a" : "mp4";
		File file = new File(context.getCacheDir(), "neon-media-" + Integer.toHexString(uri.hashCode()) + "-" + uri.length() + "." + extension);
		if (!file.exists()) {
			byte[] bytes = Base64.decode(uri.substring(comma + 1), Base64.DEFAULT);
			try (FileOutputStream out = new FileOutputStream(file)) { out.write(bytes); }
		}
		return file.getAbsolutePath();
	}

	private void release() {
		main.removeCallbacks(tick);
		prepared = false;
		if (player != null) {
			player.release();
			player = null;
		}
	}

	private void load() {
		release();
		buffered = 0;
		if (source.isEmpty()) return;
		final String uri = source;
		main.post(() -> emit(10, uri));
		MediaPlayer next = new MediaPlayer();
		player = next;
		next.setOnPreparedListener(mp -> {
			if (mp != player) return;
			prepared = true;
			videoWidth = mp.getVideoWidth();
			videoHeight = mp.getVideoHeight();
			fit();
			emit(5, seconds(mp.getDuration()) + "\u001f" + seconds(mp.getCurrentPosition()) + "\u001f" + videoWidth + "\u001f" + videoHeight);
			apply();
		});
		next.setOnVideoSizeChangedListener((mp, width, height) -> {
			videoWidth = width;
			videoHeight = height;
			fit();
		});
		next.setOnBufferingUpdateListener((mp, percent) -> buffered = percent);
		next.setOnCompletionListener(mp -> {
			if (mp != player || repeat) return;
			progress();
			emit(14, "");
		});
		next.setOnSeekCompleteListener(mp -> { if (mp == player && prepared) progress(); });
		next.setOnErrorListener((mp, what, extra) -> {
			emit(6, what + "\u001fMediaPlayer error " + what + " (" + extra + ")");
			return true;
		});
		try {
			String path = playable(getContext(), uri);
			if (path.startsWith("/")) {
				next.setDataSource(path);
				buffered = 100;
			} else {
				next.setDataSource(getContext(), Uri.parse(path));
				if (path.startsWith("file:")) buffered = 100;
			}
			if (surface != null) next.setSurface(surface);
			next.prepareAsync();
		} catch (IOException | RuntimeException e) {
			String message = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
			main.post(() -> emit(6, "0\u001f" + message));
		}
	}

	private void apply() {
		if (player == null || !prepared) return;
		float level = muted ? 0 : volume;
		player.setVolume(level, level);
		player.setLooping(repeat);
		if (paused) {
			if (player.isPlaying()) player.pause();
			main.removeCallbacks(tick);
			return;
		}
		if (Build.VERSION.SDK_INT >= 23) player.setPlaybackParams(new PlaybackParams().setSpeed(rate));
		if (!player.isPlaying()) player.start();
		main.removeCallbacks(tick);
		main.postDelayed(tick, every);
	}

	private void fit() {
		int width = getWidth();
		int height = getHeight();
		Matrix matrix = new Matrix();
		if (width > 0 && height > 0 && videoWidth > 0 && videoHeight > 0 && !"stretch".equals(mode)) {
			float fitX = width / (float)videoWidth;
			float fitY = height / (float)videoHeight;
			float scale = "cover".equals(mode) ? Math.max(fitX, fitY) : Math.min(fitX, fitY);
			matrix.setScale(videoWidth * scale / width, videoHeight * scale / height, width / 2f, height / 2f);
		}
		texture.setTransform(matrix);
	}

	@Override protected void onSizeChanged(int width, int height, int oldWidth, int oldHeight) {
		super.onSizeChanged(width, height, oldWidth, oldHeight);
		fit();
	}

	@Override protected void onAttachedToWindow() {
		super.onAttachedToWindow();
		if (player == null && !source.isEmpty()) load();
	}

	@Override protected void onDetachedFromWindow() {
		release();
		if (controller != null) controller.hide();
		super.onDetachedFromWindow();
	}

	@Override public void onSurfaceTextureAvailable(SurfaceTexture st, int width, int height) {
		surface = new Surface(st);
		if (player != null) player.setSurface(surface);
	}

	@Override public void onSurfaceTextureSizeChanged(SurfaceTexture st, int width, int height) { fit(); }

	@Override public boolean onSurfaceTextureDestroyed(SurfaceTexture st) {
		if (player != null) player.setSurface(null);
		if (surface != null) surface.release();
		surface = null;
		return true;
	}

	@Override public void onSurfaceTextureUpdated(SurfaceTexture st) {}

	private void controls(boolean shown) {
		if (!shown) {
			if (controller != null) controller.hide();
			controller = null;
			setOnClickListener(null);
			return;
		}
		if (controller != null) return;
		controller = new MediaController(getContext());
		controller.setMediaPlayer(new MediaController.MediaPlayerControl() {
			@Override public void start() { if (player != null && prepared) player.start(); main.postDelayed(tick, every); }
			@Override public void pause() { if (player != null && prepared) player.pause(); }
			@Override public int getDuration() { return player != null && prepared ? player.getDuration() : 0; }
			@Override public int getCurrentPosition() { return player != null && prepared ? player.getCurrentPosition() : 0; }
			@Override public void seekTo(int pos) { if (player != null && prepared) player.seekTo(pos); }
			@Override public boolean isPlaying() { return player != null && prepared && player.isPlaying(); }
			@Override public int getBufferPercentage() { return buffered; }
			@Override public boolean canPause() { return true; }
			@Override public boolean canSeekBackward() { return true; }
			@Override public boolean canSeekForward() { return true; }
			@Override public int getAudioSessionId() { return player != null ? player.getAudioSessionId() : 0; }
		});
		controller.setAnchorView(this);
		setOnClickListener(v -> { if (controller != null) controller.show(); });
	}

	private void seek(double seconds) {
		if (player == null || !prepared) return;
		long millis = Math.round(seconds * 1000);
		if (Build.VERSION.SDK_INT >= 26) player.seekTo(millis, MediaPlayer.SEEK_CLOSEST);
		else player.seekTo((int)millis);
	}

	private static float parse(String v, float fallback) {
		try { return Float.parseFloat(v); } catch (NumberFormatException e) { return fallback; }
	}

	@Override public void setProp(String name, String value) {
		switch (name) {
			case "source":
				if (value.equals(source)) return;
				source = value;
				load();
				break;
			case "paused": paused = "true".equals(value); apply(); break;
			case "muted": muted = "true".equals(value); apply(); break;
			case "volume": volume = Math.max(0, Math.min(1, parse(value, 1))); apply(); break;
			case "rate": rate = parse(value, 1); apply(); break;
			case "repeat": repeat = "true".equals(value); apply(); break;
			case "controls": controls("true".equals(value)); break;
			case "progressUpdateInterval": every = Math.max(16, (int)parse(value, 250)); break;
			case "resizeMode": mode = value; fit(); break;
			case "command": {
				int cut = value.indexOf('\u001f');
				String command = cut < 0 ? value : value.substring(0, cut);
				switch (command) {
					case "seek": seek(Double.parseDouble(value.substring(cut + 1))); break;
					case "pause": if (player != null && prepared) player.pause(); break;
					case "resume": if (player != null && prepared) { player.start(); main.postDelayed(tick, every); } break;
					default: throw new IllegalArgumentException("Video has no command \"" + command + "\"");
				}
				break;
			}
			default: break;
		}
	}
}
