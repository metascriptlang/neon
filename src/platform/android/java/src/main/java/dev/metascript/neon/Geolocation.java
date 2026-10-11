package dev.metascript.neon;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import java.util.HashMap;
import java.util.Map;

final class Geolocation {
	static final int REPLY = 9;
	static final int LOCATION = 11;
	private static final String FIELD = "\u001f";

	private static final Map<String, LocationListener> watches = new HashMap<>();
	private static final Handler main = new Handler(Looper.getMainLooper());

	private static final class Request {
		final boolean highAccuracy;
		final long timeout;
		final long maximumAge;
		final float distanceFilter;
		final long interval;

		Request(String encoded) {
			String[] fields = encoded.split(FIELD, -1);
			if (fields.length != 5) throw new IllegalArgumentException("Neon location: malformed request " + encoded);
			highAccuracy = "1".equals(fields[0]);
			timeout = (long) Double.parseDouble(fields[1]);
			maximumAge = (long) Double.parseDouble(fields[2]);
			distanceFilter = (float) Double.parseDouble(fields[3]);
			interval = (long) Double.parseDouble(fields[4]);
		}
	}

	private abstract static class Listener implements LocationListener {
		@Override public void onProviderEnabled(String provider) {}
		@Override public void onProviderDisabled(String provider) {}
		@SuppressWarnings("deprecation")
		@Override public void onStatusChanged(String provider, int status, Bundle extras) {}
	}

	private Geolocation() {}

	static String call(Activity a, String name, String arg) {
		int split = arg.indexOf(FIELD);
		String id = split < 0 ? arg : arg.substring(0, split);
		String rest = split < 0 ? "" : arg.substring(split + 1);
		switch (name) {
			case "location.current": return current(a, id, new Request(rest));
			case "location.watch": watch(a, id, new Request(rest)); return "";
			case "location.clear": clear(a, id); return "";
			default: throw new IllegalArgumentException("Neon App.call: unknown command " + name);
		}
	}

	private static LocationManager manager(Context context) {
		return (LocationManager) context.getApplicationContext().getSystemService(Context.LOCATION_SERVICE);
	}

	private static boolean fine(Context context) {
		return Permissions.granted(context, Manifest.permission.ACCESS_FINE_LOCATION);
	}

	private static boolean permitted(Context context) {
		return fine(context) || Permissions.granted(context, Manifest.permission.ACCESS_COARSE_LOCATION);
	}

	private static String provider(Context context, LocationManager manager, boolean highAccuracy) {
		boolean gps = fine(context) && manager.isProviderEnabled(LocationManager.GPS_PROVIDER);
		boolean network = manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER);
		if (highAccuracy && gps) return LocationManager.GPS_PROVIDER;
		if (network) return LocationManager.NETWORK_PROVIDER;
		if (gps) return LocationManager.GPS_PROVIDER;
		if (Build.VERSION.SDK_INT >= 31 && manager.isProviderEnabled(LocationManager.FUSED_PROVIDER)) return LocationManager.FUSED_PROVIDER;
		return null;
	}

	private static String number(boolean present, double value) {
		return present ? Double.toString(value) : "";
	}

	static String encode(Location l) {
		boolean vertical = Build.VERSION.SDK_INT >= 26 && l.hasVerticalAccuracy();
		return "ok" + FIELD + l.getLatitude() + FIELD + l.getLongitude()
			+ FIELD + number(l.hasAltitude(), l.getAltitude())
			+ FIELD + number(l.hasAccuracy(), l.getAccuracy())
			+ FIELD + number(vertical, vertical ? l.getVerticalAccuracyMeters() : 0)
			+ FIELD + number(l.hasBearing(), l.getBearing())
			+ FIELD + number(l.hasSpeed(), l.getSpeed())
			+ FIELD + l.getTime();
	}

	private static String error(int code, String message) {
		return "error" + FIELD + code + FIELD + message;
	}

	private static long ageMillis(Location l) {
		return (SystemClock.elapsedRealtimeNanos() - l.getElapsedRealtimeNanos()) / 1_000_000L;
	}

	@SuppressWarnings("MissingPermission")
	private static Location lastKnown(LocationManager manager) {
		Location best = null;
		for (String provider : manager.getProviders(true)) {
			Location l = manager.getLastKnownLocation(provider);
			if (l != null && (best == null || l.getElapsedRealtimeNanos() > best.getElapsedRealtimeNanos())) best = l;
		}
		return best;
	}

	@SuppressWarnings("MissingPermission")
	private static String current(Activity a, String id, Request request) {
		if (!permitted(a)) return error(1, "Location permission was not granted.");
		LocationManager manager = manager(a);
		String provider = provider(a, manager, request.highAccuracy);
		if (provider == null) return error(2, "No location provider is enabled.");
		Location last = lastKnown(manager);
		if (last != null && (request.maximumAge < 0 || ageMillis(last) <= request.maximumAge)) return encode(last);
		boolean[] done = { false };
		Runnable[] timeout = { null };
		LocationListener listener = new Listener() {
			@Override public void onLocationChanged(Location l) {
				if (done[0]) return;
				done[0] = true;
				manager.removeUpdates(this);
				if (timeout[0] != null) main.removeCallbacks(timeout[0]);
				App.event(REPLY, id + FIELD + encode(l));
			}
		};
		manager.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper());
		if (request.timeout >= 0) {
			timeout[0] = () -> {
				if (done[0]) return;
				done[0] = true;
				manager.removeUpdates(listener);
				App.event(REPLY, id + FIELD + error(3, "Location request timed out."));
			};
			main.postDelayed(timeout[0], request.timeout);
		}
		return "";
	}

	@SuppressWarnings("MissingPermission")
	private static void watch(Activity a, String id, Request request) {
		if (!permitted(a)) {
			main.post(() -> App.event(LOCATION, id + FIELD + error(1, "Location permission was not granted.")));
			return;
		}
		LocationManager manager = manager(a);
		String provider = provider(a, manager, request.highAccuracy);
		if (provider == null) {
			main.post(() -> App.event(LOCATION, id + FIELD + error(2, "No location provider is enabled.")));
			return;
		}
		LocationListener listener = new Listener() {
			@Override public void onLocationChanged(Location l) {
				if (watches.containsKey(id)) App.event(LOCATION, id + FIELD + encode(l));
			}
		};
		watches.put(id, listener);
		manager.requestLocationUpdates(provider, Math.max(0L, request.interval), Math.max(0f, request.distanceFilter), listener, Looper.getMainLooper());
	}

	private static void clear(Activity a, String id) {
		LocationListener listener = watches.remove(id);
		if (listener != null) manager(a).removeUpdates(listener);
	}
}
