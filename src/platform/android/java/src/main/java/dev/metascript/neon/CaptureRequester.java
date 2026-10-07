package dev.metascript.neon;

import android.app.Fragment;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.os.Bundle;

// The platform Fragment receives onActivityResult without the activity forwarding it;
// Ion's MainActivity extends Activity and forwards nothing.
@SuppressWarnings("deprecation")
public final class CaptureRequester extends Fragment {
	@Override public void onCreate(Bundle saved) {
		super.onCreate(saved);
		Bundle arguments = getArguments();
		if (saved != null || arguments == null) return;
		int code = arguments.getInt("code");
		try {
			startActivityForResult((Intent) arguments.getParcelable("intent"), code);
		} catch (ActivityNotFoundException | SecurityException e) {
			leave();
			Capture.failed(code, e);
		}
	}

	@Override public void onActivityResult(int code, int result, Intent data) {
		leave();
		Capture.result(code, result, data);
	}

	private void leave() {
		getFragmentManager().beginTransaction().remove(this).commitAllowingStateLoss();
	}
}
