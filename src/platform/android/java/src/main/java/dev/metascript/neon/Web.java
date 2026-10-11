package dev.metascript.neon;

import android.content.Context;
import android.graphics.Bitmap;
import android.os.Handler;
import android.os.Looper;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import org.json.JSONObject;

final class Web extends WebView implements Control {
	private int tag;
	private boolean intercept;
	private boolean failed;
	private String decision = "allow";
	private final Handler main = new Handler(Looper.getMainLooper());

	static final class Bridge {
		private final java.lang.ref.WeakReference<Web> owner;

		Bridge(Web web) { owner = new java.lang.ref.WeakReference<>(web); }

		@JavascriptInterface public void postMessage(String data) {
			Web web = owner.get();
			if (web == null) return;
			String text = data == null ? "" : data;
			web.main.post(() -> { if (web.tag != 0) Props.control(web.tag, 11, text, 0, 0); });
		}
	}

	Web(Context context) {
		super(context);
		getSettings().setJavaScriptEnabled(true);
		getSettings().setDomStorageEnabled(true);
		addJavascriptInterface(new Bridge(this), "ReactNativeWebView");
		setBackgroundColor(0xffffffff);
		setWebViewClient(new WebViewClient() {
			@Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
				return ask(request.getUrl().toString(), request.isForMainFrame(), request.hasGesture() ? "click" : "other");
			}

			@SuppressWarnings("deprecation")
			@Override public boolean shouldOverrideUrlLoading(WebView view, String url) {
				return ask(url, true, "other");
			}

			@Override public void onPageStarted(WebView view, String url, Bitmap favicon) {
				failed = false;
				emit(10, url, true);
			}

			@Override public void onPageFinished(WebView view, String url) {
				if (!failed) emit(5, url, false);
			}

			@Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
				if (!request.isForMainFrame() || tag == 0) return;
				failed = true;
				Props.control(tag, 6, error.getErrorCode() + "\u001f" + error.getDescription() + "\u001f" + request.getUrl(), 0, 0);
			}
		});
	}

	private boolean ask(String url, boolean top, String type) {
		if (!intercept || !top || tag == 0) return false;
		decision = "allow";
		Props.control(tag, 12, url + "\u001f" + type + "\u001ftrue", 0, 0);
		return "block".equals(decision);
	}

	private void emit(int phase, String url, boolean loading) {
		if (tag == 0) return;
		String title = getTitle() == null ? "" : getTitle();
		Props.control(tag, phase, (url == null ? "" : url) + "\u001f" + title + "\u001f" + loading + "\u001f" + canGoBack() + "\u001f" + canGoForward(), 0, 0);
	}

	@Override public void setNeonTag(int value) { tag = value; }

	private void source(String value) {
		String[] fields = value.split("\u001f", -1);
		if ("html".equals(fields[0])) {
			String base = fields.length > 2 ? fields[2] : "";
			loadDataWithBaseURL(base.isEmpty() ? null : base, fields.length > 1 ? fields[1] : "", "text/html; charset=utf-8", "UTF-8", null);
			return;
		}
		if (fields.length > 1 && !fields[1].isEmpty()) loadUrl(fields[1]);
	}

	private void command(String value) {
		int cut = value.indexOf('\u001f');
		String name = cut < 0 ? value : value.substring(0, cut);
		String argument = cut < 0 ? "" : value.substring(cut + 1);
		switch (name) {
			case "goBack": goBack(); break;
			case "goForward": goForward(); break;
			case "reload": reload(); break;
			case "stopLoading": stopLoading(); break;
			case "requestFocus": requestFocus(); break;
			case "injectJavaScript": evaluateJavascript(argument, null); break;
			case "postMessage":
				evaluateJavascript("(function () { window.dispatchEvent(new MessageEvent('message', { data: " + JSONObject.quote(argument) + " })); })();", null);
				break;
			default: throw new IllegalArgumentException("WebView has no command \"" + name + "\"");
		}
	}

	@Override public void setProp(String name, String value) {
		switch (name) {
			case "source": source(value); break;
			case "javaScriptEnabled": getSettings().setJavaScriptEnabled(!"false".equals(value)); break;
			case "interceptLoads": intercept = "true".equals(value); break;
			case "loadDecision": decision = value; break;
			case "command": command(value); break;
			default: break;
		}
	}
}
