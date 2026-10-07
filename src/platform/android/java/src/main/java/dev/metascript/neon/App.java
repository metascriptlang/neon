package dev.metascript.neon;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.Application;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.ComponentCallbacks2;
import android.content.Context;
import android.content.Intent;
import android.content.res.Configuration;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.provider.Settings;
import android.util.DisplayMetrics;
import android.view.KeyEvent;
import android.view.View;
import android.view.Window;
import android.view.accessibility.AccessibilityManager;
import android.view.inputmethod.InputMethodManager;
import android.window.OnBackInvokedCallback;
import android.window.OnBackInvokedDispatcher;
import java.lang.reflect.Proxy;

public final class App {
	static final int APP_STATE = 0;
	static final int BACK_PRESS = 1;
	static final int ALERT = 2;
	static final int SCREEN_READER = 3;
	static final int URL = 4;
	static final int SHARE = 5;
	static final int MEMORY_WARNING = 6;
	static final int REDUCE_MOTION = 7;
	static final int IMAGE_SIZE = 8;

	private static final String FIELD = "\u001f";
	private static final String RECORD = "\u001e";

	private static Activity activity;
	private static String state = "active";

	private App() {}

	static native int event(int kind, String value);

	public static String call(Context context, String name, String arg) {
		if (activity == null && context instanceof Activity) attach((Activity) context);
		Activity a = activity;
		if (a == null) return "";
		switch (name) {
			case "platform": return Integer.toString(Build.VERSION.SDK_INT);
			case "isPad": return "0";
			case "pixelRatio": return Float.toString(a.getResources().getDisplayMetrics().density);
			case "fontScale": return Float.toString(a.getResources().getConfiguration().fontScale);
			case "screen": return screen(a);
			case "appState": return state;
			case "keyboard.dismiss": dismissKeyboard(a); return "";
			case "alert": return alert(a, arg);
			case "linking.open": return open(a, new Intent(Intent.ACTION_VIEW, Uri.parse(arg)));
			case "linking.canOpen": return canOpen(a, arg);
			case "linking.initial": return initialUrl(a);
			case "linking.settings":
				return open(a, new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + a.getPackageName())));
			case "share": return share(a, arg);
			case "vibrate": vibrate(a, arg); return "";
			case "vibrate.cancel": vibrator(a).cancel(); return "";
			case "clipboard.get": return clipboardText(a);
			case "clipboard.set": clipboard(a).setPrimaryClip(ClipData.newPlainText("text", arg)); return "";
			case "a11y.screenReader": return accessibility(a).isTouchExplorationEnabled() ? "1" : "0";
			case "a11y.reduceMotion": return reduceMotion(a) ? "1" : "0";
			case "a11y.announce": a.getWindow().getDecorView().announceForAccessibility(arg); return "";
			case "exitApp": a.onBackPressed(); return "";
			case "image.size": {
				String[] fields = arg.split(FIELD, -1);
				if (fields.length < 2) return "";
				final String id = fields[0];
				Picture.size(a, fields[1], (width, height, error) -> event(IMAGE_SIZE, id + FIELD + width + FIELD + height + FIELD + error));
				return "";
			}
			default: return Modules.call(a, name, arg);
		}
	}

	private static void attach(Activity a) {
		activity = a;
		a.getApplication().registerActivityLifecycleCallbacks(new Lifecycle());
		a.registerComponentCallbacks(new ComponentCallbacks2() {
			@Override public void onTrimMemory(int level) {
				if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) event(MEMORY_WARNING, "");
			}
			@Override public void onConfigurationChanged(Configuration config) {}
			@Override public void onLowMemory() { event(MEMORY_WARNING, ""); }
		});
		accessibility(a).addTouchExplorationStateChangeListener(enabled -> event(SCREEN_READER, enabled ? "1" : "0"));
		interceptBack(a);
	}

	// Predictive back (targetSdk 36 on Android 16) never dispatches KEYCODE_BACK; without
	// it the OnBackInvokedCallback is ignored and the key reaches the window callback.
	private static void interceptBack(Activity a) {
		if (Build.VERSION.SDK_INT >= 33) {
			OnBackInvokedCallback callback = () -> {
				if (event(BACK_PRESS, "") == 0) a.onBackPressed();
			};
			a.getOnBackInvokedDispatcher().registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, callback);
		}
		Window window = a.getWindow();
		Window.Callback original = window.getCallback();
		window.setCallback((Window.Callback) Proxy.newProxyInstance(
			Window.Callback.class.getClassLoader(),
			new Class<?>[] { Window.Callback.class },
			(proxy, method, args) -> {
				if ("dispatchKeyEvent".equals(method.getName()) && args[0] instanceof KeyEvent) {
					KeyEvent key = (KeyEvent) args[0];
					if (key.getKeyCode() == KeyEvent.KEYCODE_BACK && key.getAction() == KeyEvent.ACTION_UP && !key.isCanceled()) {
						if (event(BACK_PRESS, "") != 0) return true;
					}
				}
				return method.invoke(original, args);
			}));
	}

	private static final class Lifecycle implements Application.ActivityLifecycleCallbacks {
		private void publish(Activity a, String next) {
			if (a != activity || next.equals(state)) return;
			state = next;
			event(APP_STATE, next);
		}
		@Override public void onActivityResumed(Activity a) { publish(a, "active"); }
		@Override public void onActivityPaused(Activity a) { publish(a, "background"); }
		@Override public void onActivityCreated(Activity a, Bundle saved) {}
		@Override public void onActivityStarted(Activity a) {}
		@Override public void onActivityStopped(Activity a) {}
		@Override public void onActivitySaveInstanceState(Activity a, Bundle out) {}
		@Override public void onActivityDestroyed(Activity a) {
			if (a == activity) activity = null;
		}
	}

	private static String screen(Activity a) {
		DisplayMetrics metrics = new DisplayMetrics();
		a.getWindowManager().getDefaultDisplay().getRealMetrics(metrics);
		return (metrics.widthPixels / metrics.density) + FIELD + (metrics.heightPixels / metrics.density);
	}

	private static void dismissKeyboard(Activity a) {
		View focused = a.getCurrentFocus();
		InputMethodManager ime = (InputMethodManager) a.getSystemService(Context.INPUT_METHOD_SERVICE);
		View anchor = focused != null ? focused : a.getWindow().getDecorView();
		ime.hideSoftInputFromWindow(anchor.getWindowToken(), 0);
		if (focused != null) focused.clearFocus();
	}

	private static String alert(Activity a, String arg) {
		String[] parts = arg.split(RECORD, -1);
		String[] head = parts[0].split(FIELD, -1);
		String id = head[0];
		AlertDialog.Builder builder = new AlertDialog.Builder(a);
		if (!head[1].isEmpty()) builder.setTitle(head[1]);
		if (!head[2].isEmpty()) builder.setMessage(head[2]);
		builder.setCancelable("1".equals(head[3]));
		int count = Math.min(3, parts.length - 1);
		for (int i = 0; i < count; i++) {
			final int index = i;
			String text = parts[1 + i].split(FIELD, -1)[0];
			int fromEnd = count - 1 - i;
			if (fromEnd == 0) builder.setPositiveButton(text, (dialog, which) -> event(ALERT, id + FIELD + index));
			else if (fromEnd == 1) builder.setNegativeButton(text, (dialog, which) -> event(ALERT, id + FIELD + index));
			else builder.setNeutralButton(text, (dialog, which) -> event(ALERT, id + FIELD + index));
		}
		builder.setOnCancelListener(dialog -> event(ALERT, id + FIELD + "-1"));
		builder.show();
		return "";
	}

	private static String open(Activity a, Intent intent) {
		try {
			a.startActivity(intent);
			return "1";
		} catch (ActivityNotFoundException | SecurityException e) {
			return "0";
		}
	}

	private static String canOpen(Activity a, String url) {
		Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
		return intent.resolveActivity(a.getPackageManager()) != null ? "1" : "0";
	}

	private static String initialUrl(Activity a) {
		Intent intent = a.getIntent();
		Uri data = intent != null ? intent.getData() : null;
		return data != null ? data.toString() : "";
	}

	private static String share(Activity a, String arg) {
		String[] fields = arg.split(FIELD, -1);
		String title = fields[0];
		String message = fields[1];
		String url = fields[2];
		Intent send = new Intent(Intent.ACTION_SEND);
		send.setType("text/plain");
		if (!title.isEmpty()) send.putExtra(Intent.EXTRA_SUBJECT, title);
		String text = message.isEmpty() ? url : url.isEmpty() ? message : message + " " + url;
		send.putExtra(Intent.EXTRA_TEXT, text);
		Intent chooser = Intent.createChooser(send, title.isEmpty() ? null : title);
		return "1".equals(open(a, chooser)) ? "sharedAction" : "dismissedAction";
	}

	private static Vibrator vibrator(Activity a) {
		return (Vibrator) a.getSystemService(Context.VIBRATOR_SERVICE);
	}

	private static void vibrate(Activity a, String arg) {
		String[] fields = arg.split(FIELD, -1);
		boolean repeat = "1".equals(fields[0]);
		String[] steps = fields[1].isEmpty() ? new String[0] : fields[1].split(",");
		long[] pattern = new long[steps.length];
		for (int i = 0; i < steps.length; i++) pattern[i] = Long.parseLong(steps[i].trim());
		if (pattern.length == 0) return;
		Vibrator vibrator = vibrator(a);
		if (Build.VERSION.SDK_INT >= 26) vibrator.vibrate(VibrationEffect.createWaveform(pattern, repeat ? 0 : -1));
		else vibrator.vibrate(pattern, repeat ? 0 : -1);
	}

	private static ClipboardManager clipboard(Activity a) {
		return (ClipboardManager) a.getSystemService(Context.CLIPBOARD_SERVICE);
	}

	private static String clipboardText(Activity a) {
		ClipData clip = clipboard(a).getPrimaryClip();
		if (clip == null || clip.getItemCount() == 0) return "";
		CharSequence text = clip.getItemAt(0).coerceToText(a);
		return text != null ? text.toString() : "";
	}

	private static AccessibilityManager accessibility(Activity a) {
		return (AccessibilityManager) a.getSystemService(Context.ACCESSIBILITY_SERVICE);
	}

	private static boolean reduceMotion(Activity a) {
		float scale = Settings.Global.getFloat(a.getContentResolver(), Settings.Global.TRANSITION_ANIMATION_SCALE, 1f);
		return scale == 0f;
	}
}
