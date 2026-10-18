package dev.metascript.neon;

import android.content.Context;
import android.util.Base64;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;

public final class Controls {
	private Controls() {}

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

	static String number(double v) {
		if (v == Math.rint(v) && Math.abs(v) < 1e15) return Long.toString((long)v);
		return Double.toString(v);
	}
}
