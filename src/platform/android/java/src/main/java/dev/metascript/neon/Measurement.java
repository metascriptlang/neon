package dev.metascript.neon;

import android.graphics.Matrix;
import android.view.View;
import android.view.ViewParent;

public final class Measurement {
	public static float[] inWindow(View view) {
		if (!view.isAttachedToWindow()) return null;
		float[] points = {0, 0, view.getWidth(), 0, view.getWidth(), view.getHeight(), 0, view.getHeight()};
		View current = view;
		while (true) {
			if (!current.isLaidOut() || current.isLayoutRequested() || current.getVisibility() != View.VISIBLE) return null;
			ViewParent parent = current.getParent();
			if (!(parent instanceof View)) break;
			View next = (View)parent;
			current.getMatrix().mapPoints(points);
			for (int i = 0; i < points.length; i += 2) {
				points[i] += current.getLeft() - next.getScrollX();
				points[i + 1] += current.getTop() - next.getScrollY();
			}
			current = next;
		}
		Matrix rootMatrix = current.getMatrix();
		rootMatrix.mapPoints(points);
		float[] rootOrigin = {0, 0};
		rootMatrix.mapPoints(rootOrigin);
		int[] windowOrigin = new int[2];
		current.getLocationInWindow(windowOrigin);
		float left = Float.POSITIVE_INFINITY, top = Float.POSITIVE_INFINITY;
		float right = Float.NEGATIVE_INFINITY, bottom = Float.NEGATIVE_INFINITY;
		for (int i = 0; i < points.length; i += 2) {
			float x = points[i] + windowOrigin[0] - rootOrigin[0];
			float y = points[i + 1] + windowOrigin[1] - rootOrigin[1];
			left = Math.min(left, x); top = Math.min(top, y);
			right = Math.max(right, x); bottom = Math.max(bottom, y);
		}
		return new float[]{left, top, right - left, bottom - top};
	}
}
