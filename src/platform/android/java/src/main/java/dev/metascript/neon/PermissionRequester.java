package dev.metascript.neon;

import android.app.Fragment;
import android.os.Bundle;

// The platform Fragment receives onRequestPermissionsResult without the activity forwarding it;
// Ion's MainActivity extends Activity and forwards nothing.
@SuppressWarnings("deprecation")
public final class PermissionRequester extends Fragment {
	@Override public void onCreate(Bundle saved) {
		super.onCreate(saved);
		Bundle arguments = getArguments();
		if (saved != null || arguments == null) return;
		requestPermissions(arguments.getStringArray("permissions"), arguments.getInt("code"));
	}

	@Override public void onRequestPermissionsResult(int code, String[] permissions, int[] results) {
		Permissions.Done done = Permissions.pending.get(code);
		Permissions.pending.remove(code);
		getFragmentManager().beginTransaction().remove(this).commitAllowingStateLoss();
		if (done != null) done.granted(permissions, results);
	}
}
