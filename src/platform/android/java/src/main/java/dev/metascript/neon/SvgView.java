package dev.metascript.neon;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.DashPathEffect;
import android.graphics.LinearGradient;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RadialGradient;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.view.View;
import java.net.URLDecoder;

// <Svg>: draws the display list of src/components/svg/scene.ms (encodeScene), in dp.
final class SvgView extends View implements Control {
	private String[] tokens = new String[0];
	private int at;

	SvgView(Context context) {
		super(context);
		setWillNotDraw(false);
		setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_AUTO);
	}

	@Override public void setNeonTag(int value) {}

	@Override public void setProp(String name, String value) {
		if (!"displayList".equals(name)) return;
		tokens = value.isEmpty() ? new String[0] : value.split(" ");
		invalidate();
	}

	@Override protected void onMeasure(int widthSpec, int heightSpec) {
		setMeasuredDimension(MeasureSpec.getSize(widthSpec), MeasureSpec.getSize(heightSpec));
	}

	private float number() {
		return at < tokens.length ? Float.parseFloat(tokens[at++]) : 0f;
	}

	private String word() {
		return at < tokens.length ? tokens[at++] : "";
	}

	private static int argb(float r, float g, float b, float a) {
		return ((int)Math.round(a * 255) << 24) | ((int)r << 16) | ((int)g << 8) | (int)b;
	}

	private static Matrix matrix(float a, float b, float c, float d, float e, float f) {
		Matrix m = new Matrix();
		m.setValues(new float[] { a, c, e, b, d, f, 0, 0, 1 });
		return m;
	}

	// A paint from the list: null for none, a colour, or a gradient shader in user space.
	private Paint paint(Paint.Style style) {
		String kind = word();
		if ("n".equals(kind)) return null;
		Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
		p.setStyle(style);
		if ("c".equals(kind)) {
			float r = number(), g = number(), b = number(), a = number();
			p.setColor(argb(r, g, b, a));
			return p;
		}
		boolean linear = "l".equals(kind);
		Matrix space = matrix(number(), number(), number(), number(), number(), number());
		float[] coords = new float[linear ? 4 : 5];
		for (int k = 0; k < coords.length; k++) coords[k] = number();
		int count = (int)number();
		int[] colors = new int[count];
		float[] offsets = new float[count];
		for (int s = 0; s < count; s++) {
			offsets[s] = number();
			float r = number(), g = number(), b = number(), a = number();
			colors[s] = argb(r, g, b, a);
		}
		Shader shader = linear
			? new LinearGradient(coords[0], coords[1], coords[2], coords[3], colors, offsets, Shader.TileMode.CLAMP)
			: new RadialGradient(coords[0], coords[1], Math.max(coords[2], 1e-6f), colors, offsets, Shader.TileMode.CLAMP);
		shader.setLocalMatrix(space);
		p.setShader(shader);
		return p;
	}

	// The viewBox to view mapping of SVG 1.1 §7.8 (align 0 none, 1..9 xMinYMin..xMaxYMax).
	private static Matrix viewBox(float width, float height, float vx, float vy, float vw, float vh, int align, int slice) {
		float sx = width / vw, sy = height / vh;
		if (align == 0) return matrix(sx, 0, 0, sy, -vx * sx, -vy * sy);
		float s = slice == 1 ? Math.max(sx, sy) : Math.min(sx, sy);
		int ax = (align - 1) % 3, ay = (align - 1) / 3;
		return matrix(s, 0, 0, s, -vx * s + (width - vw * s) * ax / 2f, -vy * s + (height - vh * s) * ay / 2f);
	}

	private void text(Canvas canvas, Matrix m) {
		int anchor = (int)number();
		int count = (int)number();
		float[][] places = new float[count][];
		String[] texts = new String[count];
		Paint[] paints = new Paint[count];
		float[] widths = new float[count];
		for (int r = 0; r < count; r++) {
			float[] p = new float[6];
			for (int k = 0; k < 6; k++) p[k] = number();
			float size = number();
			boolean bold = number() > 0;
			float red = number(), green = number(), blue = number(), alpha = number();
			String raw = word();
			String text;
			try {
				text = URLDecoder.decode(raw, "UTF-8");
			} catch (Exception e) {
				text = raw;
			}
			Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
			paint.setTextSize(size);
			paint.setTypeface(bold ? Typeface.DEFAULT_BOLD : Typeface.DEFAULT);
			paint.setColor(argb(red, green, blue, alpha));
			places[r] = p;
			texts[r] = text;
			paints[r] = paint;
			widths[r] = paint.measureText(text);
		}
		// A chunk starts at every run with its own x; the anchor shifts the whole chunk.
		float[] shifts = new float[count];
		int start = 0;
		for (int r = 0; r <= count; r++) {
			if (r == count || (r > start && places[r][0] > 0)) {
				float width = 0;
				for (int k = start; k < r; k++) width += widths[k];
				float shift = anchor == 1 ? width / 2 : anchor == 2 ? width : 0;
				for (int k = start; k < r; k++) shifts[k] = shift;
				start = r;
			}
		}
		canvas.save();
		canvas.concat(m);
		float penX = 0, penY = 0;
		for (int r = 0; r < count; r++) {
			float[] p = places[r];
			if (p[0] > 0) penX = p[1];
			if (p[2] > 0) penY = p[3];
			penX += p[4];
			penY += p[5];
			canvas.drawText(texts[r], penX - shifts[r], penY, paints[r]);
			penX += widths[r];
		}
		canvas.restore();
	}

	@Override protected void onDraw(Canvas canvas) {
		if (tokens.length == 0) return;
		float density = getResources().getDisplayMetrics().density;
		canvas.save();
		canvas.clipRect(0, 0, getWidth(), getHeight());
		canvas.scale(density, density);
		at = 0;
		Matrix m = new Matrix();
		Path path = new Path();
		Paint fill = null;
		Paint stroke = null;
		boolean evenOdd = false;
		float width = 1, miter = 4;
		Paint.Cap cap = Paint.Cap.BUTT;
		Paint.Join join = Paint.Join.MITER;
		DashPathEffect dash = null;
		while (at < tokens.length) {
			String op = tokens[at++];
			switch (op) {
				case "V": {
					float vx = number(), vy = number(), vw = number(), vh = number();
					int align = (int)number(), slice = (int)number();
					canvas.concat(viewBox(getWidth() / density, getHeight() / density, vx, vy, vw, vh, align, slice));
					break;
				}
				case "X": m = matrix(number(), number(), number(), number(), number(), number()); break;
				case "M": { float x = number(), y = number(); path.moveTo(x, y); break; }
				case "L": { float x = number(), y = number(); path.lineTo(x, y); break; }
				case "C": {
					float x1 = number(), y1 = number(), x2 = number(), y2 = number(), x = number(), y = number();
					path.cubicTo(x1, y1, x2, y2, x, y);
					break;
				}
				case "Q": {
					float x1 = number(), y1 = number(), x = number(), y = number();
					path.quadTo(x1, y1, x, y);
					break;
				}
				case "Z": path.close(); break;
				case "F": fill = paint(Paint.Style.FILL); break;
				case "S": stroke = paint(Paint.Style.STROKE); break;
				case "E": evenOdd = number() > 0; break;
				case "W": {
					width = number();
					int c = (int)number(), j = (int)number();
					cap = c == 1 ? Paint.Cap.ROUND : c == 2 ? Paint.Cap.SQUARE : Paint.Cap.BUTT;
					join = j == 1 ? Paint.Join.ROUND : j == 2 ? Paint.Join.BEVEL : Paint.Join.MITER;
					miter = number();
					break;
				}
				case "D": {
					int count = (int)number();
					float[] intervals = new float[count];
					for (int k = 0; k < count; k++) intervals[k] = number();
					float offset = number();
					dash = count >= 2 ? new DashPathEffect(intervals, offset) : null;
					break;
				}
				case "O": {
					path.setFillType(evenOdd ? Path.FillType.EVEN_ODD : Path.FillType.WINDING);
					canvas.save();
					canvas.concat(m);
					if (fill != null) canvas.drawPath(path, fill);
					if (stroke != null && width > 0) {
						stroke.setStrokeWidth(width);
						stroke.setStrokeCap(cap);
						stroke.setStrokeJoin(join);
						stroke.setStrokeMiter(miter);
						stroke.setPathEffect(dash);
						canvas.drawPath(path, stroke);
					}
					canvas.restore();
					path = new Path();
					break;
				}
				case "K": {
					Path placed = new Path();
					path.setFillType(evenOdd ? Path.FillType.EVEN_ODD : Path.FillType.WINDING);
					path.transform(m, placed);
					canvas.save();
					canvas.clipPath(placed);
					path = new Path();
					break;
				}
				case "k": canvas.restore(); break;
				case "G": canvas.saveLayerAlpha(null, Math.round(number() * 255)); break;
				case "g": canvas.restore(); break;
				case "T": text(canvas, m); break;
				default: throw new IllegalStateException("<Svg> display list has an unknown op \"" + op + "\"");
			}
		}
		canvas.restore();
	}
}
