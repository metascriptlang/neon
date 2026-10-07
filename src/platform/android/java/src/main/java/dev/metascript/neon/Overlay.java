package dev.metascript.neon;

import android.app.Activity;
import android.content.Context;
import android.os.Build;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.widget.FrameLayout;
import android.window.OnBackInvokedCallback;
import android.window.OnBackInvokedDispatcher;

// A Modal's layer over the app: it takes every touch that misses its children,
// and the system back (key on older releases, OnBackInvokedCallback where back
// is predictive) becomes control phase 7, RN's onRequestClose.
public final class Overlay extends FrameLayout {
	private int tag;
	private String animation = "none";
	private Object backCallback;

	public Overlay(Context context) {
		super(context);
		setClickable(true);
		setFocusable(true);
		setFocusableInTouchMode(true);
	}

	public void setNeonTag(int value) { tag = value; }

	public void setProp(String name, String value) {
		if ("animationType".equals(name)) animation = value.isEmpty() ? "none" : value;
	}

	private void requestClose() {
		if (tag != 0) Props.control(tag, 7, "", 0, 0);
	}

	@Override public boolean onTouchEvent(MotionEvent event) {
		super.onTouchEvent(event);
		return true;
	}

	@Override public boolean dispatchKeyEvent(KeyEvent event) {
		if (event.getKeyCode() == KeyEvent.KEYCODE_BACK) {
			if (event.getAction() == KeyEvent.ACTION_UP && !event.isCanceled()) requestClose();
			return true;
		}
		return super.dispatchKeyEvent(event);
	}

	@Override protected void onAttachedToWindow() {
		super.onAttachedToWindow();
		requestFocus();
		Activity activity = SystemBars.activity(this);
		if (Build.VERSION.SDK_INT >= 33 && activity != null) {
			OnBackInvokedCallback callback = this::requestClose;
			activity.getOnBackInvokedDispatcher().registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_OVERLAY, callback);
			backCallback = callback;
		}
		if ("fade".equals(animation)) {
			setAlpha(0f);
			animate().alpha(1f).setDuration(300).start();
		} else if ("slide".equals(animation)) {
			setTranslationY(getResources().getDisplayMetrics().heightPixels);
			animate().translationY(0f).setDuration(300).start();
		}
	}

	@Override protected void onDetachedFromWindow() {
		Activity activity = SystemBars.activity(this);
		if (Build.VERSION.SDK_INT >= 33 && activity != null && backCallback != null) {
			activity.getOnBackInvokedDispatcher().unregisterOnBackInvokedCallback((OnBackInvokedCallback)backCallback);
			backCallback = null;
		}
		super.onDetachedFromWindow();
	}
}
