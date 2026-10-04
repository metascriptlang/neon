package dev.metascript.neon;

import android.content.Context;
import android.graphics.Rect;
import android.os.Build;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewConfiguration;
import android.view.WindowInsets;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;
import android.widget.HorizontalScrollView;
import android.widget.ScrollView;
import android.widget.OverScroller;
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout;

public final class Scroll extends SwipeRefreshLayout {
	private ViewGroup scroller;
	private boolean horizontal, scrollEnabled = true, paging, refreshEnabled;
	private boolean desiredRefreshing;
	private boolean horizontalIndicator = true, verticalIndicator = true;
	private boolean dragging, momentum, activelyScrolling, preservingOffset, snapAligned;
	private int tag, stableFrames;
	private String dismissMode = "none", persistTaps = "never";
	private float downX, downY;
	private boolean keyboardCaptured;
	private final int touchSlop;
	private final OverScroller prediction;
	private final Rect visibleFrame = new Rect();

	public Scroll(Context context) {
		super(context);
		touchSlop = ViewConfiguration.get(context).getScaledTouchSlop();
		prediction = new OverScroller(context);
		setOnRefreshListener(() -> {
			emit(5);
			if (!desiredRefreshing) setRefreshing(false);
		});
		setOnChildScrollUpCallback((parent, child) -> !scrollEnabled || scroller.canScrollVertically(-1));
		replaceScroller(false);
		setEnabled(false);
	}

	public void setNeonTag(int value) { tag = value; }

	private void replaceScroller(boolean axis) {
		stopMomentum();
		View content = scroller != null && scroller.getChildCount() > 0 ? scroller.getChildAt(0) : null;
		int x = scroller == null ? 0 : scroller.getScrollX();
		int y = scroller == null ? 0 : scroller.getScrollY();
		if (content != null) scroller.removeView(content);
		if (scroller != null) removeView(scroller);
		horizontal = axis;
		scroller = axis ? new Horizontal(getContext()) : new Vertical(getContext());
		scroller.setHorizontalScrollBarEnabled(horizontalIndicator);
		scroller.setVerticalScrollBarEnabled(verticalIndicator);
		scroller.setFocusable(scrollEnabled);
		scroller.setOnScrollChangeListener((view, sx, sy, ox, oy) -> {
			activelyScrolling = true;
			emit(0);
		});
		addView(scroller, new ViewGroup.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT));
		if (content != null) scroller.addView(content);
		scroller.scrollTo(x, y);
	}

	public void addContent(View content) { scroller.addView(content); }
	public void setContentSize(int width, int height) {
		if (scroller.getChildCount() == 0) return;
		View content = scroller.getChildAt(0);
		ViewGroup.LayoutParams params = content.getLayoutParams();
		if (params.width == width && params.height == height) return;
		params.width = width;
		params.height = height;
		content.setLayoutParams(params);
	}

	public void setOption(String name, String value) {
		boolean yes = "true".equals(value);
		boolean defaultYes = value.isEmpty() || yes;
		switch (name) {
			case "horizontal": if (horizontal != yes) replaceScroller(yes); break;
			case "scrollEnabled": scrollEnabled = defaultYes; scroller.setFocusable(defaultYes); setEnabled(refreshEnabled && scrollEnabled); break;
			case "showsHorizontalScrollIndicator": horizontalIndicator = defaultYes; scroller.setHorizontalScrollBarEnabled(defaultYes); break;
			case "showsVerticalScrollIndicator": verticalIndicator = defaultYes; scroller.setVerticalScrollBarEnabled(defaultYes); break;
			case "pagingEnabled": paging = yes; break;
			case "keyboardDismissMode": dismissMode = value.isEmpty() ? "none" : value; break;
			case "keyboardShouldPersistTaps": persistTaps = value.isEmpty() ? "never" : value; break;
			case "refreshEnabled": refreshEnabled = yes; setEnabled(yes && scrollEnabled); break;
			case "refreshing": desiredRefreshing = yes; setRefreshing(yes); break;
			default: break;
		}
	}

	private void emit(int phase) {
		if (tag == 0) return;
		View content = scroller.getChildCount() == 0 ? null : scroller.getChildAt(0);
		scroll(tag, phase, scroller.getScrollX(), scroller.getScrollY(), getWidth(), getHeight(),
			content == null ? 0 : content.getWidth(), content == null ? 0 : content.getHeight());
	}

	private void beginDrag() {
		if (dragging) return;
		stopMomentum();
		dragging = true;
		if ("on-drag".equals(dismissMode)) dismissKeyboard();
		emit(1);
	}

	private void endDrag(MotionEvent event) {
		if (!dragging || (event.getActionMasked() != MotionEvent.ACTION_UP && event.getActionMasked() != MotionEvent.ACTION_CANCEL)) return;
		dragging = false;
		emit(2);
		if (event.getActionMasked() == MotionEvent.ACTION_UP) startMomentum();
	}

	private void startMomentum() {
		if (momentum) return;
		momentum = true;
		stableFrames = 0;
		snapAligned = false;
		activelyScrolling = false;
		emit(3);
		postOnAnimationDelayed(settle, 20);
	}

	// RN ReactScrollView.handlePostTouchScrolling waits for three stable
	// animation frames, including a zero-velocity page alignment after drag.
	private final Runnable settle = new Runnable() {
		@Override public void run() {
			if (!momentum) return;
			if (activelyScrolling) { activelyScrolling = false; stableFrames = 0; }
			else {
				stableFrames++;
				if (paging && !snapAligned) { snapAligned = true; snap(0); }
				if (stableFrames >= 3) { momentum = false; emit(4); return; }
			}
			postOnAnimationDelayed(this, 20);
		}
	};

	private void stopMomentum() {
		removeCallbacks(settle);
		if (momentum) { momentum = false; emit(4); }
		stableFrames = 0;
	}

	private void snap(int velocity) {
		int interval = horizontal ? scroller.getWidth() : scroller.getHeight();
		if (interval <= 0 || scroller.getChildCount() == 0) return;
		int current = horizontal ? scroller.getScrollX() : scroller.getScrollY();
		View content = scroller.getChildAt(0);
		int max = Math.max(0, (horizontal ? content.getWidth() : content.getHeight()) - interval);
		prediction.fling(0, current, 0, velocity, 0, 0, 0, max);
		int previousPage = (int)Math.floor((double)current / interval);
		int nextPage = (int)Math.ceil((double)current / interval);
		int currentPage = Math.round((float)current / interval);
		int targetPage = Math.round((float)prediction.getFinalY() / interval);
		if (velocity > 0 && nextPage == previousPage) nextPage++;
		else if (velocity < 0 && previousPage == nextPage) previousPage--;
		if (velocity > 0 && currentPage < nextPage && targetPage > previousPage) currentPage = nextPage;
		else if (velocity < 0 && currentPage > previousPage && targetPage < nextPage) currentPage = previousPage;
		int target = Math.min(max, Math.max(0, currentPage * interval));
		if (horizontal) ((HorizontalScrollView)scroller).smoothScrollTo(target, 0);
		else ((ScrollView)scroller).smoothScrollTo(0, target);
	}

	public void neonScrollTo(int x, int y, boolean animated) {
		stopMomentum();
		if (animated) {
			if (horizontal) ((HorizontalScrollView)scroller).smoothScrollTo(x, y);
			else ((ScrollView)scroller).smoothScrollTo(x, y);
			startMomentum();
		} else {
			scroller.scrollTo(x, y);
			if (horizontal) ((HorizontalScrollView)scroller).fling(0);
			else ((ScrollView)scroller).fling(0);
		}
	}

	private void dismissKeyboard() {
		View focused = getRootView().findFocus();
		if (!(focused instanceof EditText)) return;
		InputMethodManager manager = (InputMethodManager)getContext().getSystemService(Context.INPUT_METHOD_SERVICE);
		manager.hideSoftInputFromWindow(focused.getWindowToken(), 0);
		focused.clearFocus();
	}

	private boolean keyboardVisible() {
		if (Build.VERSION.SDK_INT >= 30) {
			WindowInsets insets = getRootWindowInsets();
			return insets != null && insets.isVisible(WindowInsets.Type.ime());
		}
		View root = getRootView();
		root.getWindowVisibleDisplayFrame(visibleFrame);
		return root.getHeight() - visibleFrame.bottom > 100 * getResources().getDisplayMetrics().density;
	}

	private View hit(View view, float x, float y) {
		if (view instanceof ViewGroup) {
			ViewGroup group = (ViewGroup)view;
			for (int i = group.getChildCount() - 1; i >= 0; i--) {
				View child = group.getChildAt(i);
				float cx = x + view.getScrollX() - child.getLeft();
				float cy = y + view.getScrollY() - child.getTop();
				if (child.getVisibility() == View.VISIBLE && cx >= 0 && cy >= 0 && cx < child.getWidth() && cy < child.getHeight()) return hit(child, cx, cy);
			}
		}
		return view;
	}

	@Override public boolean dispatchTouchEvent(MotionEvent event) {
		int action = event.getActionMasked();
		if (action == MotionEvent.ACTION_DOWN) {
			downX = event.getX(); downY = event.getY();
			stopMomentum();
			View focused = getRootView().findFocus();
			View target = hit(this, downX, downY);
			boolean handled = false;
			for (View ancestor = target; ancestor != this && ancestor != null; ancestor = ancestor.getParent() instanceof View ? (View)ancestor.getParent() : null) handled |= ancestor.isClickable();
			keyboardCaptured = keyboardVisible() && focused instanceof EditText && !(target instanceof EditText) &&
				("never".equals(persistTaps) || ("handled".equals(persistTaps) && !handled));
		}
		if (keyboardCaptured) {
			if (action == MotionEvent.ACTION_MOVE && Math.hypot(event.getX() - downX, event.getY() - downY) > touchSlop) {
				keyboardCaptured = false;
				MotionEvent down = MotionEvent.obtain(event);
				down.setAction(MotionEvent.ACTION_DOWN);
				super.dispatchTouchEvent(down);
				down.recycle();
			} else {
				if (action == MotionEvent.ACTION_UP) { dismissKeyboard(); keyboardCaptured = false; }
				if (action == MotionEvent.ACTION_CANCEL) keyboardCaptured = false;
				return true;
			}
		}
		return super.dispatchTouchEvent(event);
	}

	@Override protected void onDetachedFromWindow() {
		stopMomentum();
		dragging = false;
		super.onDetachedFromWindow();
	}

	public void dispose() { tag = 0; stopMomentum(); scroller.setOnScrollChangeListener(null); }

	private final class Vertical extends ScrollView {
		Vertical(Context context) { super(context); }
		@Override public boolean onInterceptTouchEvent(MotionEvent e) {
			if (!scrollEnabled) return false;
			boolean intercepted = super.onInterceptTouchEvent(e);
			if (intercepted) beginDrag();
			return intercepted;
		}
		@Override public boolean onTouchEvent(MotionEvent e) {
			if (!scrollEnabled) return false;
			boolean handled = super.onTouchEvent(e);
			endDrag(e);
			return handled;
		}
		@Override public boolean executeKeyEvent(KeyEvent event) {
			int key = event.getKeyCode();
			if (!scrollEnabled && (key == KeyEvent.KEYCODE_DPAD_UP || key == KeyEvent.KEYCODE_DPAD_DOWN)) return false;
			return super.executeKeyEvent(event);
		}
		@Override public void fling(int velocity) { if (paging && velocity != 0) snap(velocity); else super.fling(velocity); }
		@Override public void scrollTo(int x, int y) { if (!preservingOffset) super.scrollTo(x, y); }
		@Override protected void onLayout(boolean changed, int l, int t, int r, int b) {
			preservingOffset = dragging || momentum;
			super.onLayout(changed, l, t, r, b);
			preservingOffset = false;
		}
	}

	private final class Horizontal extends HorizontalScrollView {
		Horizontal(Context context) { super(context); }
		@Override public boolean onInterceptTouchEvent(MotionEvent e) {
			if (!scrollEnabled) return false;
			boolean intercepted = super.onInterceptTouchEvent(e);
			if (intercepted) beginDrag();
			return intercepted;
		}
		@Override public boolean onTouchEvent(MotionEvent e) {
			if (!scrollEnabled) return false;
			boolean handled = super.onTouchEvent(e);
			endDrag(e);
			return handled;
		}
		@Override public boolean executeKeyEvent(KeyEvent event) {
			int key = event.getKeyCode();
			if (!scrollEnabled && (key == KeyEvent.KEYCODE_DPAD_LEFT || key == KeyEvent.KEYCODE_DPAD_RIGHT)) return false;
			return super.executeKeyEvent(event);
		}
		@Override public boolean canScrollHorizontally(int direction) {
			return scrollEnabled && super.canScrollHorizontally(direction);
		}
		@Override public void fling(int velocity) { if (paging && velocity != 0) snap(velocity); else super.fling(velocity); }
		@Override public void scrollTo(int x, int y) { if (!preservingOffset) super.scrollTo(x, y); }
		@Override protected void onLayout(boolean changed, int l, int t, int r, int b) {
			preservingOffset = dragging || momentum;
			super.onLayout(changed, l, t, r, b);
			preservingOffset = false;
		}
	}

	static native void scroll(int tag, int phase, int x, int y, int width, int height, int contentWidth, int contentHeight);
}
