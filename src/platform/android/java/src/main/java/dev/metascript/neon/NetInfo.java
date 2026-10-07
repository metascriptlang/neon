package dev.metascript.neon;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

final class NetInfo {
	static final int EVENT = 10;
	private static final String FIELD = "\u001f";

	private static ConnectivityManager.NetworkCallback callback;
	private static String published = "";

	private NetInfo() {}

	static String call(Context context, String name, String arg) {
		ConnectivityManager manager = (ConnectivityManager) context.getApplicationContext().getSystemService(Context.CONNECTIVITY_SERVICE);
		switch (name) {
			case "netinfo.watch":
				if (callback == null) watch(manager);
				return publishedNow(manager);
			case "netinfo.fetch": return publishedNow(manager);
			default: throw new IllegalArgumentException("Neon App.call: unknown command " + name);
		}
	}

	private static String publishedNow(ConnectivityManager manager) {
		published = state(manager);
		return published;
	}

	private static String type(NetworkCapabilities caps) {
		if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return "vpn";
		if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return "wifi";
		if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) return "cellular";
		if (caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) return "ethernet";
		if (caps.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH)) return "bluetooth";
		return "other";
	}

	static String state(ConnectivityManager manager) {
		Network network = manager.getActiveNetwork();
		NetworkCapabilities caps = network == null ? null : manager.getNetworkCapabilities(network);
		if (caps == null) return "none" + FIELD + "0" + FIELD + "0" + FIELD + "0";
		boolean connected = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
			&& (Build.VERSION.SDK_INT < 28 || caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_SUSPENDED));
		boolean reachable = connected && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED);
		boolean metered = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED);
		return type(caps) + FIELD + (connected ? "1" : "0") + FIELD + (reachable ? "1" : "0") + FIELD + (metered ? "1" : "0");
	}

	private static void watch(ConnectivityManager manager) {
		Handler main = new Handler(Looper.getMainLooper());
		Runnable publish = () -> {
			String next = state(manager);
			if (next.equals(published)) return;
			published = next;
			App.event(EVENT, next);
		};
		callback = new ConnectivityManager.NetworkCallback() {
			@Override public void onAvailable(Network network) { main.post(publish); }
			@Override public void onLost(Network network) { main.post(publish); }
			@Override public void onCapabilitiesChanged(Network network, NetworkCapabilities caps) { main.post(publish); }
		};
		if (Build.VERSION.SDK_INT >= 24) manager.registerDefaultNetworkCallback(callback);
		else manager.registerNetworkCallback(new NetworkRequest.Builder().build(), callback);
	}
}
