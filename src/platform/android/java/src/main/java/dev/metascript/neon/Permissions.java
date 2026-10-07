package dev.metascript.neon;

import android.Manifest;
import android.app.Activity;
import android.app.FragmentManager;
import android.app.NotificationManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.os.Build;
import android.util.SparseArray;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

final class Permissions {
	static final int REPLY = 9;
	private static final String FIELD = "\u001f";
	private static final String ASKED = "dev.metascript.neon.Permissions";
	private static final String TAG = "dev.metascript.neon.PermissionRequester";

	interface Done {
		void granted(String[] permissions, int[] results);
	}

	static final SparseArray<Done> pending = new SparseArray<>();
	private static int nextCode = 1;

	private Permissions() {}

	static String call(Activity a, String name, String arg) {
		switch (name) {
			case "permission.check": return status(a, logical(after(arg)));
			case "permission.request": return request(a, before(arg), after(arg));
			case "permissionsAndroid.check": return granted(a, arg) ? "1" : "0";
			case "permissionsAndroid.rationale": return a.shouldShowRequestPermissionRationale(arg) ? "1" : "0";
			case "permissionsAndroid.request": return requestRaw(a, before(arg), after(arg).split(","));
			default: throw new IllegalArgumentException("Neon App.call: unknown command " + name);
		}
	}

	private static String before(String arg) {
		int split = arg.indexOf(FIELD);
		return split < 0 ? arg : arg.substring(0, split);
	}

	private static String after(String arg) {
		int split = arg.indexOf(FIELD);
		return split < 0 ? "" : arg.substring(split + 1);
	}

	static boolean granted(Context context, String permission) {
		return context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED;
	}

	private static SharedPreferences asked(Context context) {
		return context.getApplicationContext().getSharedPreferences(ASKED, Context.MODE_PRIVATE);
	}

	private static String[] logical(String name) {
		switch (name) {
			case "camera": return new String[] { Manifest.permission.CAMERA };
			case "microphone": return new String[] { Manifest.permission.RECORD_AUDIO };
			case "location": return new String[] { Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION };
			case "notifications":
				return Build.VERSION.SDK_INT >= 33 ? new String[] { Manifest.permission.POST_NOTIFICATIONS } : new String[0];
			default: throw new IllegalArgumentException("Neon Permissions: unknown permission " + name);
		}
	}

	private static String reply(String status, boolean canAskAgain) {
		return status + FIELD + (canAskAgain ? "1" : "0");
	}

	static String status(Activity a, String[] permissions) {
		if (permissions.length == 0) {
			NotificationManager notifications = (NotificationManager) a.getSystemService(Context.NOTIFICATION_SERVICE);
			return notifications.areNotificationsEnabled() ? reply("granted", false) : reply("denied", false);
		}
		boolean any = false;
		boolean all = true;
		boolean everAsked = false;
		boolean rationale = false;
		for (String permission : permissions) {
			boolean has = granted(a, permission);
			any |= has;
			all &= has;
			everAsked |= asked(a).getBoolean(permission, false);
			rationale |= a.shouldShowRequestPermissionRationale(permission);
		}
		boolean location = permissions.length == 2 && permissions[1].equals(Manifest.permission.ACCESS_COARSE_LOCATION);
		if (location ? any : all) return reply("granted", false);
		if (!everAsked) return reply("undetermined", true);
		return reply("denied", rationale);
	}

	private static String undeclared(Activity a, String[] permissions) {
		List<String> declared;
		try {
			PackageInfo info = a.getPackageManager().getPackageInfo(a.getPackageName(), PackageManager.GET_PERMISSIONS);
			declared = info.requestedPermissions == null ? new ArrayList<>() : Arrays.asList(info.requestedPermissions);
		} catch (PackageManager.NameNotFoundException e) {
			throw new IllegalStateException("Neon Permissions: the app's own package is not found", e);
		}
		for (String permission : permissions) {
			if (!declared.contains(permission)) return permission;
		}
		return null;
	}

	private static void ask(Activity a, String[] permissions, Done done) {
		SharedPreferences.Editor editor = asked(a).edit();
		for (String permission : permissions) editor.putBoolean(permission, true);
		editor.commit();
		int code = nextCode++ & 0xff;
		pending.put(code, done);
		FragmentManager fragments = a.getFragmentManager();
		PermissionRequester requester = new PermissionRequester();
		android.os.Bundle arguments = new android.os.Bundle();
		arguments.putStringArray("permissions", permissions);
		arguments.putInt("code", code);
		requester.setArguments(arguments);
		fragments.beginTransaction().add(requester, TAG + code).commit();
		fragments.executePendingTransactions();
	}

	private static String request(Activity a, String id, String name) {
		String[] permissions = logical(name);
		String now = status(a, permissions);
		if (now.startsWith("granted") || permissions.length == 0) return now;
		String missing = undeclared(a, permissions);
		if (missing != null) {
			return "!Permissions.request(" + name + "): add <uses-permission android:name=\"" + missing + "\" /> to the app's AndroidManifest.xml";
		}
		ask(a, permissions, (asked, results) -> App.event(REPLY, id + FIELD + status(a, permissions)));
		return "";
	}

	private static String requestRaw(Activity a, String id, String[] permissions) {
		boolean all = true;
		for (String permission : permissions) all &= granted(a, permission);
		if (all) {
			String[] results = new String[permissions.length];
			Arrays.fill(results, "granted");
			return String.join(FIELD, results);
		}
		String missing = undeclared(a, permissions);
		if (missing != null) {
			return "!PermissionsAndroid.request: add <uses-permission android:name=\"" + missing + "\" /> to the app's AndroidManifest.xml";
		}
		ask(a, permissions, (asked, results) -> {
			String[] answers = new String[permissions.length];
			for (int i = 0; i < permissions.length; i++) {
				if (granted(a, permissions[i])) answers[i] = "granted";
				else answers[i] = a.shouldShowRequestPermissionRationale(permissions[i]) ? "denied" : "never_ask_again";
			}
			App.event(REPLY, id + FIELD + String.join(FIELD, answers));
		});
		return "";
	}
}
