package dev.metascript.neon;

import android.Manifest;
import android.app.Activity;
import android.app.FragmentManager;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.ext.SdkExtensions;
import android.provider.MediaStore;
import android.provider.OpenableColumns;
import android.util.Base64;
import android.webkit.MimeTypeMap;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class Capture {
	static final int REPLY = 9;
	private static final String FIELD = "\u001f";
	private static final String RECORD = "\u001e";
	private static final String TAG = "dev.metascript.neon.CaptureRequester";
	private static final ExecutorService WORK = Executors.newSingleThreadExecutor();
	private static final Handler main = new Handler(Looper.getMainLooper());

	private static Request pending;
	private static int nextCode = 1;

	private static final class Request {
		final Context context;
		final String id;
		final int code;
		final boolean camera;
		final boolean images;
		final boolean videos;
		final double quality;
		final boolean base64;
		final boolean multiple;
		final int limit;
		final boolean front;
		File output;

		Request(Context context, String[] fields, int code) {
			this.context = context;
			this.code = code;
			id = fields[0];
			camera = "1".equals(fields[1]);
			images = "1".equals(fields[2]);
			videos = "1".equals(fields[3]);
			quality = Math.max(0, Math.min(1, Double.parseDouble(fields[5])));
			base64 = "1".equals(fields[6]);
			multiple = "1".equals(fields[7]);
			limit = (int) Double.parseDouble(fields[8]);
			front = "front".equals(fields[9]);
		}

		String source() {
			return camera ? "ImagePicker.launchCameraAsync" : "ImagePicker.launchImageLibraryAsync";
		}
	}

	private Capture() {}

	static String call(Activity a, String name, String arg) {
		if (!"capture.pick".equals(name)) throw new IllegalArgumentException("Neon App.call: unknown command " + name);
		String[] fields = arg.split(FIELD, -1);
		if (fields.length != 10) throw new IllegalArgumentException("Neon capture.pick: malformed request " + arg);
		if (pending != null) return "!ImagePicker: another picker is already open";
		Request request = new Request(a.getApplicationContext(), fields, nextCode++ & 0xff);
		Intent intent;
		if (request.camera) {
			if (Permissions.undeclared(a, new String[] { Manifest.permission.CAMERA }) == null && !Permissions.granted(a, Manifest.permission.CAMERA)) {
				return "!ImagePicker.launchCameraAsync: Missing camera permission";
			}
			boolean video = request.videos && !request.images;
			intent = new Intent(video ? MediaStore.ACTION_VIDEO_CAPTURE : MediaStore.ACTION_IMAGE_CAPTURE);
			if (intent.resolveActivity(a.getPackageManager()) == null) {
				return "!ImagePicker.launchCameraAsync: no camera app is available on this device";
			}
			request.output = new File(directory(a, "ImagePicker"), UUID.randomUUID() + (video ? ".mp4" : ".jpg"));
			intent.putExtra(MediaStore.EXTRA_OUTPUT, CaptureFiles.getUriForFile(a, CaptureFiles.authority(a), request.output));
			intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION | Intent.FLAG_GRANT_READ_URI_PERMISSION);
			if (request.front) {
				intent.putExtra("android.intent.extras.CAMERA_FACING", 1);
				intent.putExtra("android.intent.extras.LENS_FACING_FRONT", 1);
				intent.putExtra("android.intent.extra.USE_FRONT_CAMERA", true);
			}
		} else {
			intent = library(request);
		}
		pending = request;
		CaptureRequester requester = new CaptureRequester();
		Bundle arguments = new Bundle();
		arguments.putParcelable("intent", intent);
		arguments.putInt("code", request.code);
		requester.setArguments(arguments);
		FragmentManager fragments = a.getFragmentManager();
		fragments.beginTransaction().add(requester, TAG + request.code).commit();
		fragments.executePendingTransactions();
		return "";
	}

	private static boolean photoPicker() {
		if (Build.VERSION.SDK_INT >= 33) return true;
		return Build.VERSION.SDK_INT >= 30 && SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) >= 2;
	}

	private static Intent library(Request request) {
		String type = request.images && !request.videos ? "image/*" : request.videos && !request.images ? "video/*" : null;
		if (photoPicker()) {
			Intent intent = new Intent(MediaStore.ACTION_PICK_IMAGES);
			if (type != null) intent.setType(type);
			if (request.multiple) {
				int most = MediaStore.getPickImagesMaxLimit();
				int limit = request.limit > 0 ? Math.min(request.limit, most) : most;
				if (limit > 1) intent.putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, limit);
			}
			return intent;
		}
		Intent intent = new Intent(Intent.ACTION_GET_CONTENT).addCategory(Intent.CATEGORY_OPENABLE);
		if (type != null) {
			intent.setType(type);
		} else {
			intent.setType("*/*");
			intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[] { "image/*", "video/*" });
		}
		if (request.multiple && request.limit != 1) intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
		return intent;
	}

	private static void answer(String id, String reply) {
		main.post(() -> App.event(REPLY, id + FIELD + reply));
	}

	static void failed(int code, RuntimeException e) {
		Request request = pending;
		if (request == null || request.code != code) return;
		pending = null;
		if (request.output != null) request.output.delete();
		if (e instanceof SecurityException && request.camera) answer(request.id, "!ImagePicker.launchCameraAsync: Missing camera permission");
		else if (e instanceof ActivityNotFoundException && request.camera) answer(request.id, "!ImagePicker.launchCameraAsync: no camera app is available on this device");
		else if (e instanceof ActivityNotFoundException) answer(request.id, "!ImagePicker.launchImageLibraryAsync: no app can pick media on this device");
		else answer(request.id, "!" + request.source() + ": " + message(e));
	}

	static void result(int code, int result, Intent data) {
		Request request = pending;
		if (request == null || request.code != code) return;
		pending = null;
		if (result != Activity.RESULT_OK) {
			if (request.output != null) request.output.delete();
			answer(request.id, "canceled");
			return;
		}
		WORK.execute(() -> {
			String reply;
			try {
				reply = request.camera ? fromCamera(request, data) : fromLibrary(request, picked(data));
			} catch (IOException | RuntimeException | OutOfMemoryError e) {
				reply = "!" + request.source() + ": cannot read the picked media: " + message(e);
			}
			answer(request.id, reply);
		});
	}

	static String message(Throwable e) {
		return e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
	}

	static File directory(Context context, String name) {
		File directory = new File(context.getCacheDir(), name);
		directory.mkdirs();
		return directory;
	}

	static byte[] bytes(File file) throws IOException {
		try (InputStream in = new FileInputStream(file)) {
			ByteArrayOutputStream out = new ByteArrayOutputStream((int) Math.max(0, file.length()));
			byte[] buffer = new byte[65536];
			for (int n; (n = in.read(buffer)) > 0;) out.write(buffer, 0, n);
			return out.toByteArray();
		}
	}

	private static List<Uri> picked(Intent data) {
		List<Uri> uris = new ArrayList<>();
		if (data == null) return uris;
		ClipData clip = data.getClipData();
		if (clip != null) {
			for (int i = 0; i < clip.getItemCount(); i++) {
				Uri uri = clip.getItemAt(i).getUri();
				if (uri != null) uris.add(uri);
			}
		}
		if (uris.isEmpty() && data.getData() != null) uris.add(data.getData());
		return uris;
	}

	private static void copy(ContentResolver resolver, Uri uri, File file) throws IOException {
		try (InputStream in = resolver.openInputStream(uri); OutputStream out = new FileOutputStream(file)) {
			if (in == null) throw new FileNotFoundException("cannot open " + uri);
			byte[] buffer = new byte[65536];
			for (int n; (n = in.read(buffer)) > 0;) out.write(buffer, 0, n);
		}
	}

	private static String displayName(ContentResolver resolver, Uri uri) {
		if ("file".equals(uri.getScheme())) return uri.getLastPathSegment();
		try (Cursor cursor = resolver.query(uri, new String[] { OpenableColumns.DISPLAY_NAME }, null, null, null)) {
			if (cursor != null && cursor.moveToFirst() && !cursor.isNull(0)) return cursor.getString(0);
		} catch (RuntimeException e) {
			return null;
		}
		return null;
	}

	private static String extension(String mime, String name, boolean video) {
		String known = mime == null ? null : MimeTypeMap.getSingleton().getExtensionFromMimeType(mime);
		if (known != null) return known;
		int dot = name == null ? -1 : name.lastIndexOf('.');
		if (dot >= 0 && dot < name.length() - 1) return name.substring(dot + 1);
		return video ? "mp4" : "jpg";
	}

	private static String fromCamera(Request request, Intent data) throws IOException {
		File file = request.output;
		if (file.length() == 0) {
			Uri returned = data == null ? null : data.getData();
			if (returned == null) {
				file.delete();
				return "!ImagePicker.launchCameraAsync: the camera app returned no picture";
			}
			copy(request.context.getContentResolver(), returned, file);
		}
		boolean video = file.getName().endsWith(".mp4");
		return "ok" + RECORD + asset(request, file, file.getName(), video ? "video/mp4" : "image/jpeg");
	}

	private static String fromLibrary(Request request, List<Uri> uris) throws IOException {
		ContentResolver resolver = request.context.getContentResolver();
		File directory = directory(request.context, "ImagePicker");
		StringBuilder reply = new StringBuilder("ok");
		int count = 0;
		for (Uri uri : uris) {
			if ((request.limit > 0 && count >= request.limit) || (!request.multiple && count >= 1)) break;
			String mime = resolver.getType(uri);
			String name = displayName(resolver, uri);
			boolean video = mime != null && mime.startsWith("video/");
			File file = new File(directory, UUID.randomUUID() + "." + extension(mime, name, video));
			copy(resolver, uri, file);
			String type = mime != null ? mime : video ? "video/mp4" : "image/jpeg";
			reply.append(RECORD).append(asset(request, file, name != null ? name : file.getName(), type));
			count++;
		}
		return count == 0 ? "canceled" : reply.toString();
	}

	private static String asset(Request request, File file, String name, String mime) throws IOException {
		if (mime.startsWith("video/")) return video(file, name, mime);
		int width;
		int height;
		if (request.quality < 1) {
			Bitmap bitmap = Picture.local(request.context, file.getPath());
			File jpeg = new File(file.getParentFile(), UUID.randomUUID() + ".jpg");
			try (OutputStream out = new FileOutputStream(jpeg)) {
				if (!bitmap.compress(Bitmap.CompressFormat.JPEG, (int) Math.round(request.quality * 100), out)) {
					throw new IOException("cannot encode " + name + " as JPEG");
				}
			} finally {
				width = bitmap.getWidth();
				height = bitmap.getHeight();
				bitmap.recycle();
			}
			file.delete();
			file = jpeg;
			mime = "image/jpeg";
		} else {
			BitmapFactory.Options bounds = new BitmapFactory.Options();
			bounds.inJustDecodeBounds = true;
			BitmapFactory.decodeFile(file.getPath(), bounds);
			boolean swap = Picture.swaps(Picture.orientation(file.getPath()));
			width = swap ? bounds.outHeight : bounds.outWidth;
			height = swap ? bounds.outWidth : bounds.outHeight;
		}
		String base64 = request.base64 ? Base64.encodeToString(bytes(file), Base64.NO_WRAP) : "";
		return String.join(FIELD, Uri.fromFile(file).toString(), size(width), size(height), "image", name,
			Long.toString(file.length()), mime, "", base64);
	}

	private static String size(int pixels) {
		return pixels > 0 ? Integer.toString(pixels) : "";
	}

	private static String video(File file, String name, String mime) {
		String uri = Uri.fromFile(file).toString();
		String bytes = Long.toString(file.length());
		MediaMetadataRetriever retriever = new MediaMetadataRetriever();
		try {
			retriever.setDataSource(file.getPath());
			String width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH);
			String height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT);
			String rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION);
			if ("90".equals(rotation) || "270".equals(rotation)) {
				String turned = width;
				width = height;
				height = turned;
			}
			String duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION);
			String detected = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE);
			if (detected != null && detected.startsWith("video/")) mime = detected;
			return String.join(FIELD, uri, orEmpty(width), orEmpty(height), "video", name, bytes, mime, orEmpty(duration), "");
		} catch (RuntimeException unreadable) {
			return String.join(FIELD, uri, "", "", "video", name, bytes, mime, "", "");
		} finally {
			try { retriever.release(); } catch (IOException ignored) {}
		}
	}

	private static String orEmpty(String value) {
		return value == null ? "" : value;
	}
}
