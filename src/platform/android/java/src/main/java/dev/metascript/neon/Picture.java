package dev.metascript.neon;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.RenderEffect;
import android.graphics.Shader;
import android.graphics.drawable.BitmapDrawable;
import android.os.Build;
import android.util.Base64;
import android.util.LruCache;
import android.widget.ImageView;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class Picture extends ImageView {
	private static final ExecutorService POOL = Executors.newFixedThreadPool(3);
	private static final LruCache<String, Bitmap> CACHE = new LruCache<String, Bitmap>(24 * 1024 * 1024) {
		@Override protected int sizeOf(String key, Bitmap value) { return value.getByteCount(); }
	};

	private int tag;
	private int request;
	private String uri = "";
	private Bitmap bitmap;
	private boolean repeat;
	private ScaleType scale = ScaleType.CENTER_CROP;

	interface SizeDone { void done(int width, int height, String error); }

	// Image.getSize / Image.prefetch: loads into the views' cache, answers on the main thread.
	static void size(Context context, String uri, SizeDone done) {
		Bitmap cached = CACHE.get(uri);
		android.os.Handler main = new android.os.Handler(android.os.Looper.getMainLooper());
		if (cached != null) {
			main.post(() -> done.done(cached.getWidth(), cached.getHeight(), ""));
			return;
		}
		POOL.execute(() -> {
			try {
				Bitmap loaded = fetch(context, uri);
				main.post(() -> {
					CACHE.put(uri, loaded);
					done.done(loaded.getWidth(), loaded.getHeight(), "");
				});
			} catch (Exception e) {
				String message = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
				main.post(() -> done.done(0, 0, message));
			}
		});
	}

	// RN resizeMode repeat tiles the bitmap over the view; every other mode is a scale type.
	private void show() {
		if (bitmap == null) {
			setImageDrawable(null);
			return;
		}
		if (repeat) {
			BitmapDrawable tiled = new BitmapDrawable(getResources(), bitmap);
			tiled.setTileModeXY(Shader.TileMode.REPEAT, Shader.TileMode.REPEAT);
			setScaleType(ScaleType.FIT_XY);
			setImageDrawable(tiled);
		} else {
			setScaleType(scale);
			setImageBitmap(bitmap);
		}
	}

	private void blur(float radius) {
		if (Build.VERSION.SDK_INT < 31) return;
		float px = radius * getResources().getDisplayMetrics().density;
		setRenderEffect(px > 0 ? RenderEffect.createBlurEffect(px, px, Shader.TileMode.CLAMP) : null);
	}

	public Picture(Context context) {
		super(context);
		setScaleType(ScaleType.CENTER_CROP);
		setClipToOutline(true);
	}

	public void setNeonTag(int value) { tag = value; }

	public void setProp(String name, String v) {
		switch (name) {
			case "source": load(v); break;
			case "resizeMode":
				switch (v) {
					case "contain": scale = ScaleType.FIT_CENTER; break;
					case "stretch": scale = ScaleType.FIT_XY; break;
					case "center": scale = ScaleType.CENTER_INSIDE; break;
					default: scale = ScaleType.CENTER_CROP; break;
				}
				repeat = "repeat".equals(v);
				setScaleType(scale);
				show();
				break;
			case "blurRadius": blur(v.isEmpty() ? 0 : Float.parseFloat(v)); break;
			default: break;
		}
	}

	private void emit(int phase, String value, int width, int height) {
		if (tag != 0) Props.control(tag, phase, value, width, height);
	}

	private void load(String next) {
		if (next.equals(uri)) return;
		uri = next;
		final int mine = ++request;
		bitmap = null;
		show();
		if (next.isEmpty()) return;
		Bitmap cached = CACHE.get(next);
		if (cached != null) {
			bitmap = cached;
			show();
			post(() -> { if (mine == request) emit(5, "", cached.getWidth(), cached.getHeight()); });
			return;
		}
		final Context context = getContext();
		POOL.execute(() -> {
			try {
				Bitmap bitmap = fetch(context, next);
				post(() -> {
					if (mine != request) return;
					CACHE.put(next, bitmap);
					this.bitmap = bitmap;
					show();
					emit(5, "", bitmap.getWidth(), bitmap.getHeight());
				});
			} catch (Exception e) {
				String message = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
				post(() -> { if (mine == request) emit(6, message, 0, 0); });
			}
		});
	}

	private static Bitmap decode(InputStream in, String uri) throws IOException {
		Bitmap bitmap = BitmapFactory.decodeStream(in);
		if (bitmap == null) throw new IOException("cannot decode image " + uri);
		return bitmap;
	}

	private static Bitmap fetch(Context context, String uri) throws IOException {
		if (uri.startsWith("data:")) {
			int comma = uri.indexOf(',');
			if (comma < 0) throw new IOException("malformed data URI");
			byte[] bytes = Base64.decode(uri.substring(comma + 1), Base64.DEFAULT);
			Bitmap bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
			if (bitmap == null) throw new IOException("cannot decode data URI");
			return bitmap;
		}
		if (uri.startsWith("asset:/")) {
			try (InputStream in = context.getAssets().open(uri.substring("asset:/".length()))) { return decode(in, uri); }
		}
		HttpURLConnection connection = (HttpURLConnection)new URL(uri).openConnection();
		connection.setConnectTimeout(10000);
		connection.setReadTimeout(15000);
		connection.setInstanceFollowRedirects(true);
		try {
			int status = connection.getResponseCode();
			if (status < 200 || status >= 300) throw new IOException("HTTP " + status);
			try (InputStream in = connection.getInputStream()) { return decode(in, uri); }
		} finally {
			connection.disconnect();
		}
	}
}
