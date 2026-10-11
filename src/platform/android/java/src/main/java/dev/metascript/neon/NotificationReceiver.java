package dev.metascript.neon;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public final class NotificationReceiver extends BroadcastReceiver {
	@Override public void onReceive(Context context, Intent intent) {
		String spec = intent.getStringExtra(Notifications.EXTRA);
		if (spec != null) Notifications.deliver(context, spec.split("\u001f", -1));
	}
}
