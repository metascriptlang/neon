package dev.metascript.neon;

import android.content.Context;
import android.content.res.Configuration;
import android.os.Build;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;

public final class Environment extends View {
	private int keyboard = -1;
	private int dark = -1;

	private Environment(Context context) {
		super(context);
	}

	public static void install(ViewGroup root) {
		Environment probe = new Environment(root.getContext());
		root.addView(probe, new ViewGroup.LayoutParams(0, 0));
		root.getViewTreeObserver().addOnGlobalLayoutListener(probe::publish);
	}

	public static int colorScheme(Context context) {
		int night = context.getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK;
		return night == Configuration.UI_MODE_NIGHT_YES ? 1 : 0;
	}

	private int keyboardHeight() {
		WindowInsets insets = getRootWindowInsets();
		if (insets == null) return 0;
		if (Build.VERSION.SDK_INT >= 30) {
			int ime = insets.getInsets(WindowInsets.Type.ime()).bottom;
			int bars = insets.getInsets(WindowInsets.Type.navigationBars()).bottom;
			return Math.max(0, ime - bars);
		}
		return 0;
	}

	private void publish() {
		int nextKeyboard = keyboardHeight();
		int nextDark = colorScheme(getContext());
		if (nextKeyboard == keyboard && nextDark == dark) return;
		keyboard = nextKeyboard;
		dark = nextDark;
		changed(keyboard, dark);
	}

	@Override protected void onConfigurationChanged(Configuration config) {
		super.onConfigurationChanged(config);
		publish();
	}

	@Override public WindowInsets onApplyWindowInsets(WindowInsets insets) {
		post(this::publish);
		return super.onApplyWindowInsets(insets);
	}

	static native void changed(int keyboardHeight, int dark);
}
