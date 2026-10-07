package dev.metascript.neon;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.ImageFormat;
import android.graphics.Matrix;
import android.graphics.RectF;
import android.graphics.SurfaceTexture;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureFailure;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.CaptureResult;
import android.hardware.camera2.TotalCaptureResult;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.media.ExifInterface;
import android.media.Image;
import android.media.ImageReader;
import android.net.Uri;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.util.Base64;
import android.util.Size;
import android.view.Display;
import android.view.Surface;
import android.view.TextureView;
import android.view.WindowManager;
import android.widget.FrameLayout;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.util.ArrayDeque;
import java.util.Arrays;
import java.util.UUID;
import java.util.concurrent.ConcurrentLinkedQueue;

final class CameraPreview extends FrameLayout implements Control, TextureView.SurfaceTextureListener {
	private static final String FIELD = "\u001f";
	private static final int READY = 30;
	private static final int MOUNT_ERROR = 31;
	private static final int PICTURE = 32;
	private static final int PREVIEW_LONG = 1920;
	private static final int PREVIEW_SHORT = 1080;
	private static final long METERING_TIMEOUT = 1500;

	private static final class Shot {
		final String id;
		final double quality;
		final boolean base64;
		boolean mirror;

		Shot(String id, double quality, boolean base64) {
			this.id = id;
			this.quality = quality;
			this.base64 = base64;
		}
	}

	private final TextureView texture;
	private final Handler main = new Handler(Looper.getMainLooper());
	private final CameraManager manager;
	private final File cache;
	private final ArrayDeque<Shot> waiting = new ArrayDeque<>();
	private final ConcurrentLinkedQueue<Shot> capturing = new ConcurrentLinkedQueue<>();
	private HandlerThread thread;
	private Handler background;
	private int tag;
	private String facing = "back";
	private String flash = "off";
	private boolean active = true;
	private boolean mirror;
	private boolean attached;
	private boolean visible = true;
	private boolean failed;
	private boolean opening;
	private boolean paused;
	private int generation;
	private CameraDevice device;
	private CameraCaptureSession session;
	private ImageReader reader;
	private Surface surface;
	private CaptureRequest.Builder preview;
	private Size previewSize;
	private int sensorOrientation;
	private boolean front;
	private boolean flashAvailable;
	private boolean continuousFocus;
	private Shot metering;
	private boolean precaptureStarted;
	private final Runnable meteringTimeout = this::metered;

	private final CameraCaptureSession.CaptureCallback meteringCallback = new CameraCaptureSession.CaptureCallback() {
		@Override public void onCaptureCompleted(CameraCaptureSession s, CaptureRequest request, TotalCaptureResult result) {
			if (metering == null || s != session) return;
			Integer ae = result.get(CaptureResult.CONTROL_AE_STATE);
			if (!precaptureStarted) {
				if (ae == null || ae == CaptureResult.CONTROL_AE_STATE_PRECAPTURE || ae == CaptureResult.CONTROL_AE_STATE_FLASH_REQUIRED) {
					precaptureStarted = true;
				}
			} else if (ae == null || ae != CaptureResult.CONTROL_AE_STATE_PRECAPTURE) {
				metered();
			}
		}
	};

	CameraPreview(Context context) {
		super(context);
		setBackgroundColor(0xff000000);
		manager = (CameraManager) context.getSystemService(Context.CAMERA_SERVICE);
		cache = context.getCacheDir();
		texture = new TextureView(context);
		texture.setSurfaceTextureListener(this);
		addView(texture, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
	}

	@Override public void setNeonTag(int value) {
		tag = value;
		refresh();
	}

	private void emit(int phase, String value) {
		main.post(() -> { if (tag != 0) Props.control(tag, phase, value, 0, 0); });
	}

	private void refresh() {
		boolean wanted = attached && visible && active && tag != 0 && texture.isAvailable();
		if (!wanted) {
			close();
			return;
		}
		if (device != null || opening || failed) return;
		open();
	}

	private void broken(String message) {
		close();
		failed = true;
		emit(MOUNT_ERROR, message);
	}

	private String find(boolean wantFront) throws CameraAccessException {
		int lens = wantFront ? CameraCharacteristics.LENS_FACING_FRONT : CameraCharacteristics.LENS_FACING_BACK;
		for (String id : manager.getCameraIdList()) {
			Integer facing = manager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING);
			if (facing != null && facing == lens) return id;
		}
		return null;
	}

	private void open() {
		if (getContext().checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
			broken("Camera permission not granted");
			return;
		}
		boolean wantFront = "front".equals(facing);
		String id;
		CameraCharacteristics characteristics;
		try {
			id = find(wantFront);
			if (id == null) {
				broken("No camera is available on this device");
				return;
			}
			characteristics = manager.getCameraCharacteristics(id);
		} catch (CameraAccessException | RuntimeException e) {
			broken(Capture.message(e));
			return;
		}
		StreamConfigurationMap map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
		if (map == null) {
			broken("The camera reports no output sizes");
			return;
		}
		Integer sensor = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION);
		sensorOrientation = sensor == null ? 0 : sensor;
		front = wantFront;
		Boolean flashes = characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE);
		flashAvailable = flashes != null && flashes;
		int[] focusModes = characteristics.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES);
		continuousFocus = false;
		if (focusModes != null) {
			for (int mode : focusModes) continuousFocus |= mode == CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE;
		}
		previewSize = previewSize(map.getOutputSizes(SurfaceTexture.class));
		Size still = stillSize(map.getOutputSizes(ImageFormat.JPEG));
		if (previewSize == null || still == null) {
			broken("The camera reports no output sizes");
			return;
		}
		startThread();
		reader = ImageReader.newInstance(still.getWidth(), still.getHeight(), ImageFormat.JPEG, 2);
		reader.setOnImageAvailableListener(this::saved, background);
		final int mine = ++generation;
		opening = true;
		try {
			manager.openCamera(id, new CameraDevice.StateCallback() {
				@Override public void onOpened(CameraDevice camera) {
					if (mine != generation) {
						camera.close();
						return;
					}
					opening = false;
					device = camera;
					startSession(mine);
				}

				@Override public void onDisconnected(CameraDevice camera) {
					camera.close();
					if (mine == generation) broken("The camera was disconnected");
				}

				@Override public void onError(CameraDevice camera, int error) {
					camera.close();
					if (mine == generation) broken("The camera failed with error " + error);
				}
			}, main);
		} catch (CameraAccessException | RuntimeException e) {
			broken(Capture.message(e));
		}
	}

	@SuppressWarnings("deprecation")
	private void startSession(int mine) {
		SurfaceTexture st = texture.getSurfaceTexture();
		if (st == null || reader == null) {
			close();
			return;
		}
		st.setDefaultBufferSize(previewSize.getWidth(), previewSize.getHeight());
		surface = new Surface(st);
		fit();
		try {
			preview = device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
			preview.addTarget(surface);
			controls(preview);
			device.createCaptureSession(Arrays.asList(surface, reader.getSurface()), new CameraCaptureSession.StateCallback() {
				@Override public void onConfigured(CameraCaptureSession s) {
					if (mine != generation) {
						s.close();
						return;
					}
					session = s;
					repeat(null);
					if (session != null) emit(READY, "");
				}

				@Override public void onConfigureFailed(CameraCaptureSession s) {
					if (mine == generation) broken("The camera preview could not be configured");
				}
			}, main);
		} catch (CameraAccessException | RuntimeException e) {
			broken(Capture.message(e));
		}
	}

	private void controls(CaptureRequest.Builder builder) {
		builder.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO);
		if (continuousFocus) builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
		if (!flashAvailable || "off".equals(flash)) {
			builder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON);
			builder.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_OFF);
		} else {
			builder.set(CaptureRequest.CONTROL_AE_MODE, "on".equals(flash)
				? CaptureRequest.CONTROL_AE_MODE_ON_ALWAYS_FLASH : CaptureRequest.CONTROL_AE_MODE_ON_AUTO_FLASH);
		}
	}

	private void repeat(CameraCaptureSession.CaptureCallback callback) {
		if (session == null || preview == null) return;
		try {
			if (paused) session.stopRepeating();
			else session.setRepeatingRequest(preview.build(), callback, main);
		} catch (CameraAccessException | RuntimeException e) {
			broken(Capture.message(e));
		}
	}

	private void close() {
		generation++;
		opening = false;
		failed = false;
		main.removeCallbacks(meteringTimeout);
		metering = null;
		precaptureStarted = false;
		for (Shot shot : waiting) emit(PICTURE, shot.id + FIELD + "error" + FIELD + "The camera closed before the picture was taken");
		waiting.clear();
		for (Shot shot; (shot = capturing.poll()) != null;) {
			emit(PICTURE, shot.id + FIELD + "error" + FIELD + "The camera closed before the picture was taken");
		}
		CameraCaptureSession s = session;
		CameraDevice d = device;
		ImageReader r = reader;
		Surface f = surface;
		session = null;
		device = null;
		reader = null;
		surface = null;
		preview = null;
		if (s == null && d == null && r == null && f == null) return;
		Runnable shut = () -> {
			if (s != null) s.close();
			if (d != null) d.close();
			if (r != null) r.close();
			if (f != null) f.release();
		};
		if (background != null) background.post(shut);
		else shut.run();
	}

	private void startThread() {
		if (thread != null) return;
		thread = new HandlerThread("NeonCamera");
		thread.start();
		background = new Handler(thread.getLooper());
	}

	private void stopThread() {
		if (thread == null) return;
		thread.quitSafely();
		thread = null;
		background = null;
	}

	@SuppressWarnings("deprecation")
	private int displayDegrees() {
		Display display = getDisplay();
		if (display == null) display = ((WindowManager) getContext().getSystemService(Context.WINDOW_SERVICE)).getDefaultDisplay();
		return display.getRotation() * 90;
	}

	private Size previewSize(Size[] sizes) {
		if (sizes == null || sizes.length == 0) return null;
		int width = texture.getWidth();
		int height = texture.getHeight();
		boolean sideways = (sensorOrientation + displayDegrees()) % 180 != 0;
		double aspect = width > 0 && height > 0 ? (sideways ? height / (double) width : width / (double) height) : 4 / 3.0;
		Size best = null;
		double bestDifference = Double.MAX_VALUE;
		for (Size size : sizes) {
			int longSide = Math.max(size.getWidth(), size.getHeight());
			int shortSide = Math.min(size.getWidth(), size.getHeight());
			if (longSide > PREVIEW_LONG || shortSide > PREVIEW_SHORT) continue;
			double difference = Math.abs(size.getWidth() / (double) size.getHeight() - aspect);
			boolean closer = difference < bestDifference - 0.01;
			boolean larger = Math.abs(difference - bestDifference) <= 0.01 && best != null
				&& (long) size.getWidth() * size.getHeight() > (long) best.getWidth() * best.getHeight();
			if (best == null || closer || larger) {
				best = size;
				bestDifference = difference;
			}
		}
		return best != null ? best : sizes[0];
	}

	private static Size stillSize(Size[] sizes) {
		if (sizes == null || sizes.length == 0) return null;
		Size best = null;
		Size largest = null;
		for (Size size : sizes) {
			long area = (long) size.getWidth() * size.getHeight();
			if (largest == null || area > (long) largest.getWidth() * largest.getHeight()) largest = size;
			if (Math.max(size.getWidth(), size.getHeight()) > Picture.MAX_SIDE) continue;
			if (best == null || area > (long) best.getWidth() * best.getHeight()) best = size;
		}
		return best != null ? best : largest;
	}

	private void fit() {
		int width = texture.getWidth();
		int height = texture.getHeight();
		Matrix matrix = new Matrix();
		if (width > 0 && height > 0 && previewSize != null) {
			int rotation = displayDegrees();
			boolean sensorSideways = sensorOrientation % 180 != 0;
			float naturalWidth = sensorSideways ? previewSize.getHeight() : previewSize.getWidth();
			float naturalHeight = sensorSideways ? previewSize.getWidth() : previewSize.getHeight();
			float cx = width / 2f;
			float cy = height / 2f;
			if (rotation % 180 != 0) {
				RectF view = new RectF(0, 0, width, height);
				RectF buffer = new RectF(0, 0, naturalWidth, naturalHeight);
				buffer.offset(cx - buffer.centerX(), cy - buffer.centerY());
				matrix.setRectToRect(view, buffer, Matrix.ScaleToFit.FILL);
				float scale = Math.max(height / naturalWidth, width / naturalHeight);
				matrix.postScale(scale, scale, cx, cy);
				matrix.postRotate(rotation == 90 ? -90 : 90, cx, cy);
			} else {
				float scale = Math.max(width / naturalWidth, height / naturalHeight);
				matrix.setScale(scale * naturalWidth / width, scale * naturalHeight / height, cx, cy);
				if (rotation == 180) matrix.postRotate(180, cx, cy);
			}
		}
		texture.setTransform(matrix);
	}

	private int jpegOrientation() {
		int degrees = displayDegrees();
		return front ? (sensorOrientation + degrees) % 360 : (sensorOrientation - degrees + 360) % 360;
	}

	private void takePicture(String argument) {
		String[] fields = argument.split(FIELD, -1);
		String id = fields[0];
		double quality = fields.length > 1 && !fields[1].isEmpty() ? Double.parseDouble(fields[1]) : 1;
		boolean base64 = fields.length > 2 && "1".equals(fields[2]);
		if (session == null) {
			emit(PICTURE, id + FIELD + "error" + FIELD + "The camera is not ready");
			return;
		}
		waiting.add(new Shot(id, Math.max(0, Math.min(1, quality)), base64));
		if (waiting.size() == 1 && metering == null && capturing.isEmpty()) next();
	}

	private void next() {
		Shot shot = waiting.peek();
		if (shot == null || session == null || metering != null || !capturing.isEmpty()) return;
		if (!flashAvailable || "off".equals(flash)) {
			still(shot);
			return;
		}
		metering = shot;
		precaptureStarted = false;
		try {
			preview.set(CaptureRequest.CONTROL_AE_PRECAPTURE_TRIGGER, CaptureRequest.CONTROL_AE_PRECAPTURE_TRIGGER_START);
			session.capture(preview.build(), meteringCallback, main);
			preview.set(CaptureRequest.CONTROL_AE_PRECAPTURE_TRIGGER, CaptureRequest.CONTROL_AE_PRECAPTURE_TRIGGER_IDLE);
		} catch (CameraAccessException | RuntimeException e) {
			broken(Capture.message(e));
			return;
		}
		repeat(meteringCallback);
		main.postDelayed(meteringTimeout, METERING_TIMEOUT);
	}

	private void metered() {
		Shot shot = metering;
		if (shot == null) return;
		main.removeCallbacks(meteringTimeout);
		metering = null;
		precaptureStarted = false;
		repeat(null);
		if (session != null) still(shot);
	}

	private void still(Shot shot) {
		waiting.remove(shot);
		shot.mirror = front && mirror;
		try {
			CaptureRequest.Builder builder = device.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE);
			builder.addTarget(reader.getSurface());
			controls(builder);
			builder.set(CaptureRequest.JPEG_ORIENTATION, jpegOrientation());
			builder.set(CaptureRequest.JPEG_QUALITY, (byte) Math.max(1, Math.min(100, Math.round(shot.quality * 100))));
			capturing.add(shot);
			session.capture(builder.build(), new CameraCaptureSession.CaptureCallback() {
				@Override public void onCaptureFailed(CameraCaptureSession s, CaptureRequest request, CaptureFailure failure) {
					if (!capturing.remove(shot)) return;
					emit(PICTURE, shot.id + FIELD + "error" + FIELD + "The camera failed to take the picture (reason " + failure.getReason() + ")");
					next();
				}
			}, main);
		} catch (CameraAccessException | RuntimeException e) {
			capturing.remove(shot);
			emit(PICTURE, shot.id + FIELD + "error" + FIELD + Capture.message(e));
			next();
		}
	}

	private void saved(ImageReader source) {
		Image image = source.acquireNextImage();
		if (image == null) return;
		Shot shot = capturing.poll();
		byte[] bytes;
		try {
			ByteBuffer buffer = image.getPlanes()[0].getBuffer();
			bytes = new byte[buffer.remaining()];
			buffer.get(bytes);
		} finally {
			image.close();
		}
		main.post(this::next);
		if (shot == null) return;
		String reply;
		try {
			reply = store(bytes, shot);
		} catch (IOException | RuntimeException | OutOfMemoryError e) {
			reply = shot.id + FIELD + "error" + FIELD + Capture.message(e);
		}
		emit(PICTURE, reply);
	}

	private String store(byte[] bytes, Shot shot) throws IOException {
		File directory = new File(cache, "Camera");
		directory.mkdirs();
		File file = new File(directory, UUID.randomUUID() + ".jpg");
		try (OutputStream out = new FileOutputStream(file)) { out.write(bytes); }
		int orientation = Picture.orientation(file.getPath());
		boolean turned = orientation != ExifInterface.ORIENTATION_NORMAL && orientation != ExifInterface.ORIENTATION_UNDEFINED;
		int width;
		int height;
		if (turned || shot.mirror) {
			Bitmap bitmap = BitmapFactory.decodeFile(file.getPath());
			if (bitmap == null) throw new IOException("cannot decode the captured JPEG");
			bitmap = Picture.orient(bitmap, orientation, shot.mirror);
			try (OutputStream out = new FileOutputStream(file)) {
				bitmap.compress(Bitmap.CompressFormat.JPEG, (int) Math.max(1, Math.min(100, Math.round(shot.quality * 100))), out);
			} finally {
				width = bitmap.getWidth();
				height = bitmap.getHeight();
				bitmap.recycle();
			}
		} else {
			BitmapFactory.Options bounds = new BitmapFactory.Options();
			bounds.inJustDecodeBounds = true;
			BitmapFactory.decodeFile(file.getPath(), bounds);
			width = bounds.outWidth;
			height = bounds.outHeight;
		}
		String base64 = shot.base64 ? Base64.encodeToString(Capture.bytes(file), Base64.NO_WRAP) : "";
		return String.join(FIELD, shot.id, "ok", Uri.fromFile(file).toString(), Integer.toString(width), Integer.toString(height), base64);
	}

	@Override protected void onAttachedToWindow() {
		super.onAttachedToWindow();
		attached = true;
		refresh();
	}

	@Override protected void onDetachedFromWindow() {
		attached = false;
		close();
		stopThread();
		super.onDetachedFromWindow();
	}

	@Override protected void onWindowVisibilityChanged(int visibility) {
		super.onWindowVisibilityChanged(visibility);
		visible = visibility == VISIBLE;
		refresh();
	}

	@Override protected void onSizeChanged(int width, int height, int oldWidth, int oldHeight) {
		super.onSizeChanged(width, height, oldWidth, oldHeight);
		fit();
	}

	@Override public void onSurfaceTextureAvailable(SurfaceTexture st, int width, int height) { refresh(); }

	@Override public void onSurfaceTextureSizeChanged(SurfaceTexture st, int width, int height) { fit(); }

	@Override public boolean onSurfaceTextureDestroyed(SurfaceTexture st) {
		close();
		return true;
	}

	@Override public void onSurfaceTextureUpdated(SurfaceTexture st) {}

	@Override public void setProp(String name, String value) {
		switch (name) {
			case "facing":
				if (value.equals(facing)) return;
				facing = value;
				close();
				refresh();
				break;
			case "flash":
				flash = value;
				if (preview != null) {
					controls(preview);
					repeat(metering != null ? meteringCallback : null);
				}
				break;
			case "active": {
				boolean next = !"false".equals(value);
				if (next == active) return;
				active = next;
				close();
				refresh();
				break;
			}
			case "mirror": mirror = "true".equals(value); break;
			case "command": {
				int cut = value.indexOf('\u001f');
				String command = cut < 0 ? value : value.substring(0, cut);
				String argument = cut < 0 ? "" : value.substring(cut + 1);
				switch (command) {
					case "takePicture": takePicture(argument); break;
					case "pausePreview":
						paused = true;
						repeat(null);
						break;
					case "resumePreview":
						paused = false;
						repeat(null);
						break;
					default: throw new IllegalArgumentException("CameraView has no command \"" + command + "\"");
				}
				break;
			}
			default: break;
		}
	}
}
