package dev.metascript.neon;

import androidx.core.content.FileProvider;

// Its own class name, so the manifest merger never collides with an app's FileProvider.
public final class CaptureFiles extends FileProvider {
	static String authority(android.content.Context context) {
		return context.getPackageName() + ".neon.capture";
	}
}
