package dev.metascript.neon;

import android.app.Activity;

final class Modules {
	private Modules() {}

	static String call(Activity a, String name, String arg) {
		int dot = name.indexOf('.');
		String domain = dot < 0 ? name : name.substring(0, dot);
		switch (domain) {
			case "storage": return Storage.call(a, name, arg);
			case "netinfo": return NetInfo.call(a, name, arg);
			case "permission":
			case "permissionsAndroid": return Permissions.call(a, name, arg);
			case "location": return Geolocation.call(a, name, arg);
			case "haptics":
			case "device":
			case "locale": return Device.call(a, name, arg);
			default: throw new IllegalArgumentException("Neon App.call: unknown command " + name);
		}
	}
}
