package dev.metascript.neon;

import android.content.Context;
import android.view.View;

public final class Controls {
	private Controls() {}

	public static View create(Context context, String kind) {
		switch (kind) {
			case "webview": return new Web(context);
			case "video": return new Movie(context);
			case "svg": return new SvgView(context);
			case "camera": return new CameraPreview(context);
			default: throw new IllegalArgumentException("niControlCreate has no control \"" + kind + "\"");
		}
	}

	static String number(double v) {
		if (v == Math.rint(v) && Math.abs(v) < 1e15) return Long.toString((long)v);
		return Double.toString(v);
	}
}
