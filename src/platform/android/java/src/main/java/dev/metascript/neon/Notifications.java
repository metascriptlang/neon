package dev.metascript.neon;

import android.app.Activity;
import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import java.util.HashMap;
import java.util.Map;

final class Notifications {
	static final int REPLY = 9;
	static final int EVENT = 12;
	static final String EXTRA = "dev.metascript.neon.notification";
	private static final String FIELD = "\u001f";
	private static final String CHANNEL = "neon-default";
	private static final String SCHEDULED = "dev.metascript.neon.Notifications";
	private static final String DEFAULT_ACTION = "expo.modules.notifications.actions.DEFAULT";
	private static final long PRESENT_WAIT = 3000;

	private static final Map<String, String[]> awaiting = new HashMap<>();
	private static final Map<String, Runnable> timers = new HashMap<>();
	private static final Handler main = new Handler(Looper.getMainLooper());
	private static boolean decides;
	private static String lastResponse = "";

	private Notifications() {}

	static String call(Activity a, String name, String arg) {
		switch (name) {
			case "notification.install": install(a); return "";
			case "notification.schedule": {
				int split = arg.indexOf(FIELD);
				return schedule(a, arg.substring(split + 1).split(FIELD, -1));
			}
			case "notification.cancel": cancel(a, arg); return "";
			case "notification.cancelAll":
				for (String identifier : scheduled(a).getAll().keySet()) cancel(a, identifier);
				return "";
			case "notification.dismissAll": manager(a).cancelAll(); return "";
			case "notification.handler": decides = "1".equals(arg); return "";
			case "notification.present": present(a, arg.split(FIELD, -1)); return "";
			case "notification.last": return lastResponse;
			default: throw new IllegalArgumentException("Neon App.call: unknown command " + name);
		}
	}

	private static NotificationManager manager(Context context) {
		return (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
	}

	private static SharedPreferences scheduled(Context context) {
		return context.getApplicationContext().getSharedPreferences(SCHEDULED, Context.MODE_PRIVATE);
	}

	private static String record(String kind, String[] spec) {
		return String.join(FIELD, kind, spec[0], spec[1], spec[2], spec[3], spec[4], Long.toString(System.currentTimeMillis()));
	}

	private static void install(Activity a) {
		Intent intent = a.getIntent();
		String opened = intent == null ? null : intent.getStringExtra(EXTRA);
		if (opened != null) {
			lastResponse = record("response", opened.split(FIELD, -1)) + FIELD + DEFAULT_ACTION;
			intent.removeExtra(EXTRA);
		}
	}

	private static String schedule(Context context, String[] spec) {
		if (spec.length != 10) return "!Notifications: malformed request";
		String identifier = spec[0];
		double seconds = Double.parseDouble(spec[7]);
		double date = Double.parseDouble(spec[9]);
		if (seconds < 0 && date < 0) {
			deliver(context, spec);
			return identifier;
		}
		long when = date >= 0 ? (long) date : System.currentTimeMillis() + (long) (seconds * 1000);
		scheduled(context).edit().putString(identifier, String.join(FIELD, spec)).commit();
		AlarmManager alarms = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
		PendingIntent pending = alarm(context, spec, PendingIntent.FLAG_UPDATE_CURRENT);
		if ("1".equals(spec[8])) {
			alarms.setRepeating(AlarmManager.RTC_WAKEUP, when, (long) (seconds * 1000), pending);
			return identifier;
		}
		if (Build.VERSION.SDK_INT >= 31 && !alarms.canScheduleExactAlarms()) alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, when, pending);
		else alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, when, pending);
		// While the process lives a main-thread timer fires on time; the alarm, inexact without the
		// exact-alarm permission, covers a process that is gone by then.
		Context application = context.getApplicationContext();
		Runnable timer = () -> {
			timers.remove(identifier);
			cancel(application, identifier);
			deliver(application, spec);
		};
		timers.put(identifier, timer);
		main.postDelayed(timer, Math.max(0L, when - System.currentTimeMillis()));
		return identifier;
	}

	private static Intent alarmIntent(Context context, String identifier) {
		return new Intent(context, NotificationReceiver.class).setAction(EXTRA + "." + identifier);
	}

	private static PendingIntent alarm(Context context, String[] spec, int flags) {
		Intent intent = alarmIntent(context, spec[0]).putExtra(EXTRA, String.join(FIELD, spec));
		return PendingIntent.getBroadcast(context, spec[0].hashCode(), intent, flags | PendingIntent.FLAG_IMMUTABLE);
	}

	private static void cancel(Context context, String identifier) {
		Runnable timer = timers.remove(identifier);
		if (timer != null) main.removeCallbacks(timer);
		PendingIntent pending = PendingIntent.getBroadcast(context, identifier.hashCode(), alarmIntent(context, identifier),
			PendingIntent.FLAG_NO_CREATE | PendingIntent.FLAG_IMMUTABLE);
		if (pending != null) {
			((AlarmManager) context.getSystemService(Context.ALARM_SERVICE)).cancel(pending);
			pending.cancel();
		}
		scheduled(context).edit().remove(identifier).commit();
	}

	static void deliver(Context context, String[] spec) {
		if (!"1".equals(spec[8])) {
			Runnable timer = timers.remove(spec[0]);
			if (timer != null) main.removeCallbacks(timer);
			scheduled(context).edit().remove(spec[0]).commit();
		}
		if (!App.foreground()) {
			post(context, spec);
			return;
		}
		String identifier = spec[0];
		if (decides) {
			awaiting.put(identifier, spec);
			main.postDelayed(() -> awaiting.remove(identifier), PRESENT_WAIT);
		}
		App.event(EVENT, record("received", spec));
	}

	private static void present(Context context, String[] answer) {
		String[] spec = awaiting.remove(answer[0]);
		if (spec != null && "1".equals(answer[1])) post(context, spec);
	}

	@SuppressWarnings("deprecation")
	private static void post(Context context, String[] spec) {
		NotificationManager notifications = manager(context);
		Notification.Builder builder;
		if (Build.VERSION.SDK_INT >= 26) {
			if (notifications.getNotificationChannel(CHANNEL) == null) {
				notifications.createNotificationChannel(new NotificationChannel(CHANNEL, "Notifications", NotificationManager.IMPORTANCE_HIGH));
			}
			builder = new Notification.Builder(context, CHANNEL);
		} else {
			builder = new Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH);
		}
		int icon = context.getApplicationInfo().icon;
		builder.setSmallIcon(icon != 0 ? icon : android.R.drawable.ic_dialog_info).setAutoCancel(true);
		if (!spec[1].isEmpty()) builder.setContentTitle(spec[1]);
		if (!spec[2].isEmpty()) builder.setSubText(spec[2]);
		if (!spec[3].isEmpty()) builder.setContentText(spec[3]);
		double badge = Double.parseDouble(spec[6]);
		if (badge >= 0) builder.setNumber((int) badge);
		if (!"1".equals(spec[5])) builder.setDefaults(0);
		Intent open = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
		if (open != null) {
			open.putExtra(EXTRA, String.join(FIELD, spec));
			builder.setContentIntent(PendingIntent.getActivity(context, spec[0].hashCode(), open,
				PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));
		}
		notifications.notify(spec[0], 0, builder.build());
	}
}
