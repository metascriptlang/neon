package dev.metascript.neon;

import android.content.Context;
import android.content.SharedPreferences;

final class Storage {
	private static final String FIELD = "\u001f";
	private static final String FILE = "dev.metascript.neon.AsyncStorage";

	private Storage() {}

	private static SharedPreferences preferences(Context context) {
		return context.getApplicationContext().getSharedPreferences(FILE, Context.MODE_PRIVATE);
	}

	static String call(Context context, String name, String arg) {
		SharedPreferences preferences = preferences(context);
		switch (name) {
			case "storage.get": {
				String value = preferences.getString(arg, null);
				return value == null ? "" : "=" + value;
			}
			case "storage.set": {
				int split = arg.indexOf(FIELD);
				if (split < 0) throw new IllegalArgumentException("Neon storage.set: no value separator in the argument");
				preferences.edit().putString(arg.substring(0, split), arg.substring(split + 1)).commit();
				return "";
			}
			case "storage.remove": preferences.edit().remove(arg).commit(); return "";
			case "storage.clear": preferences.edit().clear().commit(); return "";
			case "storage.keys": return String.join(FIELD, preferences.getAll().keySet());
			default: throw new IllegalArgumentException("Neon App.call: unknown command " + name);
		}
	}
}
