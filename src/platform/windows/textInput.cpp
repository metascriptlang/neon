#include <windows.h>
#include <richedit.h>
#include <textserv.h>
#include <d2d1_1.h>
#include <dwrite.h>
#include <wrl/client.h>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "textInput.h"
#include "handoff.h"
#include "must.h"

using Microsoft::WRL::ComPtr;

class ITextServices2 : public ITextServices {
public:
	virtual HRESULT TxGetNaturalSize2(DWORD dwAspect, HDC hdcDraw, HDC hicTargetDev, DVTARGETDEVICE *ptd, DWORD dwMode,
		const SIZEL *psizelExtent, LONG *pwidth, LONG *pheight, LONG *pascent) = 0;
	virtual HRESULT TxDrawD2D(ID2D1RenderTarget *pRenderTarget, LPCRECTL lprcBounds, LPRECT lprcUpdate, LONG lViewId) = 0;
};

namespace {

const IID kTextServices2 = {0x8d33f741, 0xcf58, 0x11ce, {0xa8, 0x9d, 0x00, 0xaa, 0x00, 0x6c, 0xad, 0xc5}};
const IID kTextHost = {0x13e670f4, 0x1a5a, 0x11cf, {0xab, 0xeb, 0x00, 0xaa, 0x00, 0xb6, 0x5e, 0xa1}};
const UINT kSetDpi = WM_USER + 328;
const WPARAM kColorEmojiTypography = 0x1000 | 0x2000;
const DWORD kD2DDirectWrite = 0x1000000;
const DWORD kD2DSimpleTypography = 0x2000000;
const float kTwipsPerDip = 15;
const float kUnboundedHeight = 1e6f;

PCreateTextServices createTextServices() {
	static PCreateTextServices create = nullptr;
	if (create) return create;
	HMODULE library = LoadLibraryW(L"Msftedit.dll");
	if (!library) must(HRESULT_FROM_WIN32(GetLastError()), "LoadLibrary(Msftedit.dll)");
	create = (PCreateTextServices)GetProcAddress(library, "CreateTextServices");
	if (!create) must(HRESULT_FROM_WIN32(GetLastError()), "GetProcAddress(CreateTextServices)");
	return create;
}

IDWriteFactory *writeFactory() {
	static IDWriteFactory *shared = nullptr;
	if (!shared) {
		must(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), (IUnknown **)&shared), "DWriteCreateFactory");
	}
	return shared;
}

[[noreturn]] void refuse(const char *what, const char *value) {
	fprintf(stderr, "neon windows bridge: %s \"%s\"\n", what, value);
	fflush(stderr);
	abort();
}

std::wstring widen(const char *utf8, const char *what) {
	std::wstring wide;
	size_t bytes = strlen(utf8);
	if (bytes == 0) return wide;
	int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, (int)bytes, nullptr, 0);
	if (length == 0) refuse(what, "invalid UTF-8");
	wide.resize((size_t)length);
	MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, (int)bytes, &wide[0], length);
	return wide;
}

std::string narrow(const std::wstring &wide) {
	std::string utf8;
	if (wide.empty()) return utf8;
	int length = WideCharToMultiByte(CP_UTF8, 0, wide.data(), (int)wide.size(), nullptr, 0, nullptr, nullptr);
	utf8.resize((size_t)length);
	WideCharToMultiByte(CP_UTF8, 0, wide.data(), (int)wide.size(), &utf8[0], length, nullptr, nullptr);
	return utf8;
}

std::wstring paragraphsAsCarriageReturns(std::wstring text) {
	for (wchar_t &c : text) if (c == L'\n') c = L'\r';
	return text;
}

int hexDigit(char c) {
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

Color parseColor(const char *css, const char *what) {
	size_t n = strlen(css);
	if (n < 4 || css[0] != '#' || (n != 4 && n != 7 && n != 9)) refuse(what, css);
	int digits[8];
	for (size_t i = 1; i < n; i++) {
		digits[i - 1] = hexDigit(css[i]);
		if (digits[i - 1] < 0) refuse(what, css);
	}
	if (n == 4) return Color{digits[0] * 17 / 255.0f, digits[1] * 17 / 255.0f, digits[2] * 17 / 255.0f, 1};
	float a = n == 9 ? (digits[6] * 16 + digits[7]) / 255.0f : 1;
	return Color{(digits[0] * 16 + digits[1]) / 255.0f, (digits[2] * 16 + digits[3]) / 255.0f, (digits[4] * 16 + digits[5]) / 255.0f, a};
}

COLORREF colorRef(Color c) {
	return RGB((int)lroundf(c.r * 255), (int)lroundf(c.g * 255), (int)lroundf(c.b * 255));
}

bool noSoftKeyboardOrCorrectionProc(const char *name) {
	return !strcmp(name, "autoCorrect") || !strcmp(name, "keyboardType") || !strcmp(name, "returnKeyType");
}

bool flag(const char *value, const char *name) {
	if (!strcmp(value, "true")) return true;
	if (!strcmp(value, "false") || value[0] == '\0') return false;
	char what[96];
	snprintf(what, sizeof what, "TextInput %s is not true or false:", name);
	refuse(what, value);
}

}

TextInput::TextInput(TextInputSink *sink, void *owner, bool multiline)
	: sink(sink), owner(owner), multiline(multiline), blurOnSubmit(!multiline) {
	memset(&charFormat, 0, sizeof charFormat);
	memset(&paraFormat, 0, sizeof paraFormat);
	SetFormat();
	IUnknown *unknown = nullptr;
	must(createTextServices()(nullptr, this, &unknown), "CreateTextServices");
	must(unknown->QueryInterface(kTextServices2, (void **)&services), "ITextServices2");
	unknown->Release();
	Send(EM_SETTEXTMODE, TM_PLAINTEXT, 0, "EM_SETTEXTMODE");
	Send(EM_SETEVENTMASK, 0, ENM_CHANGE | ENM_SELCHANGE, "EM_SETEVENTMASK");
	Send(EM_SETTYPOGRAPHYOPTIONS, kColorEmojiTypography, kColorEmojiTypography, "EM_SETTYPOGRAPHYOPTIONS");
	Send(EM_LIMITTEXT, maxLength, 0, "EM_LIMITTEXT");
}

TextInput::~TextInput() {
	sink = nullptr;
	if (services) {
		services->OnTxInPlaceDeactivate();
		services->Release();
	}
	if (caret) {
		if (parentVisual) parentVisual->Remove(caret);
		delete caret;
	}
}

LRESULT TextInput::Send(UINT message, WPARAM wParam, LPARAM lParam, const char *what) {
	LRESULT result = 0;
	HRESULT hr = services->TxSendMessage(message, wParam, lParam, &result);
	if (FAILED(hr)) must(hr, what);
	return result;
}

void TextInput::Dirty() {
	paintDirty = true;
	if (sink) sink->InputDirty(this);
}

RECT TextInput::Client() const {
	RECT rc;
	rc.left = (LONG)lroundf(insetLeft * scale);
	rc.top = (LONG)lroundf(insetTop * scale);
	rc.right = drawnWidth - (LONG)lroundf(insetRight * scale);
	rc.bottom = drawnHeight - (LONG)lroundf(insetBottom * scale);
	if (rc.right < rc.left) rc.right = rc.left;
	if (rc.bottom < rc.top) rc.bottom = rc.top;
	return rc;
}

DWORD TextInput::PropertyBits() const {
	DWORD bits = TXTBIT_RICHTEXT | TXTBIT_WORDWRAP | kD2DDirectWrite | kD2DSimpleTypography;
	if (multiline) bits |= TXTBIT_MULTILINE;
	if (readOnly) bits |= TXTBIT_READONLY;
	if (secure) bits |= TXTBIT_USEPASSWORD;
	return bits;
}

void TextInput::ChangeBits(DWORD mask) {
	writing += 1;
	must(services->OnTxPropertyBitsChange(mask, PropertyBits() & mask), "OnTxPropertyBitsChange");
	writing -= 1;
	Dirty();
}

void TextInput::SetFormat() {
	memset(&charFormat, 0, sizeof charFormat);
	charFormat.cbSize = sizeof charFormat;
	charFormat.dwMask = CFM_SIZE | CFM_WEIGHT | CFM_BOLD | CFM_FACE | CFM_OFFSET | CFM_CHARSET;
	charFormat.yHeight = (LONG)lroundf(size * kTwipsPerDip);
	charFormat.wWeight = bold ? FW_BOLD : FW_NORMAL;
	if (bold) charFormat.dwEffects |= CFE_BOLD;
	wcsncpy(charFormat.szFaceName, family.c_str(), LF_FACESIZE - 1);
	charFormat.bPitchAndFamily = FF_DONTCARE;
	charFormat.bCharSet = DEFAULT_CHARSET;
	memset(&paraFormat, 0, sizeof paraFormat);
	paraFormat.cbSize = sizeof paraFormat;
	paraFormat.dwMask = PFM_ALIGNMENT;
	paraFormat.wAlignment = alignment;
}

bool TextInput::SetProp(const char *name, const char *value) {
	if (!strcmp(name, "value")) {
		std::wstring wide = paragraphsAsCarriageReturns(widen(value, "TextInput value received"));
		if (wide != paragraphsAsCarriageReturns(widen(Text().c_str(), "TextInput text"))) {
			Write(wide);
			LONG end = (LONG)wide.size();
			Select(end, end);
		}
	} else if (!strcmp(name, "defaultValue")) {
		if (Text().empty()) Write(paragraphsAsCarriageReturns(widen(value, "TextInput defaultValue received")));
	} else if (!strcmp(name, "placeholder")) {
		placeholder = widen(value, "TextInput placeholder received");
		Dirty();
	} else if (!strcmp(name, "placeholderTextColor")) {
		placeholderColor = value[0] ? parseColor(value, "TextInput placeholderTextColor is not #rgb, #rrggbb or #rrggbbaa:") : Color{0.5f, 0.5f, 0.5f, 1};
		Dirty();
	} else if (!strcmp(name, "editable")) {
		readOnly = value[0] != '\0' && !flag(value, name);
		ChangeBits(TXTBIT_READONLY);
	} else if (!strcmp(name, "secureTextEntry")) {
		secure = flag(value, name);
		ChangeBits(TXTBIT_USEPASSWORD);
	} else if (!strcmp(name, "multiline")) {
		if (flag(value, name) != multiline) refuse("TextInput multiline changed after the input was created:", value);
	} else if (!strcmp(name, "autoFocus")) {
		autoFocus = flag(value, name);
	} else if (!strcmp(name, "blurOnSubmit")) {
		blurOnSubmit = value[0] == '\0' ? !multiline : flag(value, name);
	} else if (!strcmp(name, "autoCapitalize")) {
		if (strcmp(value, "characters") && strcmp(value, "none") && strcmp(value, "sentences") && strcmp(value, "words") && value[0]) {
			refuse("TextInput autoCapitalize is not none, sentences, words or characters:", value);
		}
		WPARAM upper = !strcmp(value, "characters") ? SES_UPPERCASE : 0;
		Send(EM_SETEDITSTYLE, upper, SES_UPPERCASE, "EM_SETEDITSTYLE");
	} else if (!strcmp(name, "maxLength")) {
		maxLength = value[0] ? (DWORD)atol(value) : 0x7FFFFFFE;
		Send(EM_LIMITTEXT, maxLength, 0, "EM_LIMITTEXT");
	} else if (noSoftKeyboardOrCorrectionProc(name)) {
	} else if (!strcmp(name, "selection")) {
		long start = 0, end = 0;
		if (sscanf(value, "%ld,%ld", &start, &end) != 2) refuse("TextInput selection is not start,end:", value);
		Select(start, end);
	} else if (!strcmp(name, "textInsets")) {
		if (sscanf(value, "%f,%f,%f,%f", &insetLeft, &insetTop, &insetRight, &insetBottom) != 4) refuse("TextInput textInsets is not l,t,r,b:", value);
		Dirty();
	} else if (!strcmp(name, "fontFamily")) {
		SetFamily(value);
	} else if (!strcmp(name, "textAlign")) {
		SetAlignment(value);
	} else {
		return false;
	}
	return true;
}

void TextInput::Write(const std::wstring &text) {
	writing += 1;
	must(services->TxSetText(text.c_str()), "TxSetText");
	writing -= 1;
	Dirty();
}

void TextInput::Select(LONG start, LONG end) {
	writing += 1;
	Send(EM_SETSEL, (WPARAM)start, (LPARAM)end, "EM_SETSEL");
	writing -= 1;
	Dirty();
}

std::string TextInput::Text() {
	BSTR text = nullptr;
	must(services->TxGetText(&text), "TxGetText");
	std::wstring wide = text ? std::wstring(text, SysStringLen(text)) : std::wstring();
	SysFreeString(text);
	while (!wide.empty() && (wide.back() == L'\0' || wide.back() == L'\r')) wide.pop_back();
	for (wchar_t &c : wide) if (c == L'\r') c = L'\n';
	return narrow(wide);
}

void TextInput::SetColor(Color c) {
	color = c;
	ChangeBits(TXTBIT_CHARFORMATCHANGE);
}

void TextInput::SetFont(float fontSize, bool fontBold) {
	if (fontSize == size && fontBold == bold) return;
	size = fontSize;
	bold = fontBold;
	SetFormat();
	ChangeBits(TXTBIT_CHARFORMATCHANGE);
}

void TextInput::SetFamily(const char *utf8) {
	std::wstring wide = utf8[0] ? widen(utf8, "TextInput fontFamily received") : std::wstring(L"Segoe UI");
	if (wide.size() >= LF_FACESIZE) refuse("TextInput fontFamily is longer than a face name:", utf8);
	if (wide == family) return;
	family = wide;
	SetFormat();
	ChangeBits(TXTBIT_CHARFORMATCHANGE);
}

void TextInput::SetAlignment(const char *value) {
	WORD next;
	if (!strcmp(value, "auto") || !strcmp(value, "left")) next = PFA_LEFT;
	else if (!strcmp(value, "right")) next = PFA_RIGHT;
	else if (!strcmp(value, "center")) next = PFA_CENTER;
	else if (!strcmp(value, "justify")) next = PFA_JUSTIFY;
	else refuse("TextInput textAlign is not auto, left, right, center or justify:", value);
	if (next == alignment) return;
	alignment = next;
	SetFormat();
	ChangeBits(TXTBIT_PARAFORMATCHANGE);
}

void TextInput::SetBackground(Color c) {
	background = c;
	Dirty();
}

void TextInput::SetScale(float next) {
	if (next == scale) return;
	scale = next;
	Send(kSetDpi, (WPARAM)lroundf(96 * scale), (LPARAM)lroundf(96 * scale), "EM_SETDPI");
	Dirty();
}

void TextInput::Measure(float maxWidth, float measureScale, float *width, float *height) {
	ComPtr<IDWriteTextFormat> format;
	must(writeFactory()->CreateTextFormat(family.c_str(), nullptr, bold ? DWRITE_FONT_WEIGHT_BOLD : DWRITE_FONT_WEIGHT_NORMAL,
		DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, size, L"", &format), "CreateTextFormat");
	std::wstring text = widen(Text().c_str(), "TextInput text");
	if (!multiline || text.empty()) text = L"Ag";
	float inner = maxWidth - insetLeft - insetRight;
	ComPtr<IDWriteTextLayout> layout;
	must(writeFactory()->CreateTextLayout(text.c_str(), (UINT32)text.size(), format.Get(), inner > 0 ? inner : 0, kUnboundedHeight, &layout), "CreateTextLayout");
	DWRITE_TEXT_METRICS metrics;
	must(layout->GetMetrics(&metrics), "GetMetrics");
	*width = ceilf((metrics.width + insetLeft + insetRight) * measureScale) / measureScale;
	*height = ceilf((metrics.height + insetTop + insetBottom) * measureScale) / measureScale;
}

bool TextInput::TakeAutoFocus() {
	bool due = autoFocus;
	autoFocus = false;
	return due;
}

void TextInput::Focus(bool next) {
	if (next == focused) return;
	focused = next;
	writing += 1;
	Send(next ? WM_SETFOCUS : WM_KILLFOCUS, 0, 0, next ? "WM_SETFOCUS" : "WM_KILLFOCUS");
	writing -= 1;
	if (!next) pointerHeld = false;
	Dirty();
}

void TextInput::WindowFocus(bool next) {
	if (next == windowFocused) return;
	windowFocused = next;
	Dirty();
}

void TextInput::Key(int action, int scancode, bool ctrl, const char *text) {
	if (!focused) return;
	UINT vk = MapVirtualKeyW((UINT)scancode, MAPVK_VSC_TO_VK_EX);
	if (vk == VK_TAB) return;
	LPARAM lParam = 1 | ((LPARAM)(scancode & 0xff) << 16);
	if (scancode & 0xe000) lParam |= 1 << 24;
	if (action == NIW_KEY_RELEASE) {
		Send(WM_KEYUP, vk, lParam | (LPARAM)0xC0000000, "WM_KEYUP");
		return;
	}
	if (action == NIW_KEY_REPEAT) lParam |= 1 << 30;
	if (vk == VK_RETURN) {
		if (multiline) {
			Send(EM_REPLACESEL, TRUE, (LPARAM)L"\r", "EM_REPLACESEL");
		} else {
			sink->InputReport(this, kInputSubmit, Text());
		}
		return;
	}
	Send(WM_KEYDOWN, vk, lParam, "WM_KEYDOWN");
	if (vk == VK_BACK) Send(WM_CHAR, ctrl ? 0x7f : VK_BACK, lParam, "WM_CHAR");
	std::wstring units = widen(text, "Ion key text");
	for (wchar_t unit : units) Send(WM_CHAR, unit, lParam, "WM_CHAR");
}

void TextInput::Insert(const char *utf8) {
	if (!focused) return;
	std::wstring units = widen(utf8, "Ion text");
	Send(EM_REPLACESEL, TRUE, (LPARAM)units.c_str(), "EM_REPLACESEL");
}

void TextInput::Preedit(const char *utf8, int cursor) {
	if (!focused) return;
	std::wstring units = widen(utf8, "Ion preedit");
	if (!composing && units.empty()) return;
	writing += 1;
	if (!composing) {
		CHARRANGE range;
		Send(EM_EXGETSEL, 0, (LPARAM)&range, "EM_EXGETSEL");
		compositionStart = range.cpMin;
		compositionLength = range.cpMax - range.cpMin;
		composing = true;
	}
	Send(EM_SETSEL, (WPARAM)compositionStart, (LPARAM)(compositionStart + compositionLength), "EM_SETSEL");
	Send(EM_REPLACESEL, FALSE, (LPARAM)units.c_str(), "EM_REPLACESEL");
	compositionLength = (LONG)units.size();
	if (units.empty()) {
		composing = false;
	} else {
		LONG at = compositionStart + (cursor < 0 || cursor > compositionLength ? compositionLength : cursor);
		Send(EM_SETSEL, (WPARAM)at, (LPARAM)at, "EM_SETSEL");
	}
	writing -= 1;
	Dirty();
}

void TextInput::Pointer(int kind, float pixelX, float pixelY) {
	LPARAM at = MAKELPARAM((int)lroundf(pixelX), (int)lroundf(pixelY));
	if (kind == NIW_POINTER_DOWN) {
		pointerHeld = true;
		Send(WM_LBUTTONDOWN, MK_LBUTTON, at, "WM_LBUTTONDOWN");
	} else if (kind == NIW_POINTER_MOVE && pointerHeld) {
		Send(WM_MOUSEMOVE, MK_LBUTTON, at, "WM_MOUSEMOVE");
	} else if (kind == NIW_POINTER_UP && pointerHeld) {
		pointerHeld = false;
		Send(WM_LBUTTONUP, 0, at, "WM_LBUTTONUP");
	} else if (kind == NIW_POINTER_CANCEL && pointerHeld) {
		pointerHeld = false;
		Send(WM_LBUTTONUP, 0, at, "WM_LBUTTONUP");
	}
}

bool TextInput::NeedsDraw(int32_t pixelWidth, int32_t pixelHeight) const {
	return paintDirty || pixelWidth != drawnWidth || pixelHeight != drawnHeight;
}

void TextInput::Draw(ICompositionContext *context, IVisual *visual, int32_t pixelWidth, int32_t pixelHeight, float drawScale) {
	bool resized = pixelWidth != drawnWidth || pixelHeight != drawnHeight;
	drawnWidth = pixelWidth;
	drawnHeight = pixelHeight;
	SetScale(drawScale);
	paintDirty = false;
	if (!caret) {
		parentVisual = visual;
		caret = context->CreateSpriteVisual();
		visual->InsertAt(caret, 0);
	}
	bool showCaret = focused && windowFocused && caretShown && caretX >= 0 && caretY >= 0;
	caret->Brush(color);
	caret->Size((float)(caretWidth > 0 ? caretWidth : 1), (float)caretHeight);
	caret->Offset((float)caretX, (float)caretY);
	caret->Opacity(showCaret ? 1.0f : 0.0f);
	if (pixelWidth <= 0 || pixelHeight <= 0) {
		surface.reset();
		visual->Content(nullptr);
		return;
	}
	if (!surface || resized) {
		surface.reset(context->CreateDrawingSurface(pixelWidth, pixelHeight));
		visual->Content(surface.get());
	}
	RECT client = Client();
	writing += 1;
	must(services->OnTxInPlaceActivate(&client), "OnTxInPlaceActivate");
	writing -= 1;
	ID2D1DeviceContext *dc = static_cast<ID2D1DeviceContext *>(surface->BeginDrawD2D(96.0f * scale));
	dc->Clear(D2D1::ColorF(background.r, background.g, background.b, background.a));
	RECTL bounds = {client.left, client.top, client.right, client.bottom};
	writing += 1;
	HRESULT drawn = services->TxDrawD2D(dc, &bounds, nullptr, TXTVIEW_ACTIVE);
	writing -= 1;
	if (FAILED(drawn)) must(drawn, "TxDrawD2D");
	if (!placeholder.empty() && !composing && Text().empty()) {
		ComPtr<IDWriteTextFormat> format;
		must(writeFactory()->CreateTextFormat(family.c_str(), nullptr, bold ? DWRITE_FONT_WEIGHT_BOLD : DWRITE_FONT_WEIGHT_NORMAL,
			DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, size, L"", &format), "CreateTextFormat");
		ComPtr<IDWriteTextLayout> layout;
		float width = (client.right - client.left) / scale;
		must(writeFactory()->CreateTextLayout(placeholder.c_str(), (UINT32)placeholder.size(), format.Get(), width, kUnboundedHeight, &layout), "CreateTextLayout");
		ComPtr<ID2D1SolidColorBrush> brush;
		must(dc->CreateSolidColorBrush(D2D1::ColorF(placeholderColor.r, placeholderColor.g, placeholderColor.b, placeholderColor.a), &brush), "CreateSolidColorBrush");
		dc->DrawTextLayout(D2D1::Point2F(client.left / scale, client.top / scale), layout.Get(), brush.Get(), D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT);
	}
	if (composing && compositionLength > 0) {
		POINTL from = {0, 0}, to = {0, 0};
		Send(EM_POSFROMCHAR, (WPARAM)&from, compositionStart, "EM_POSFROMCHAR");
		Send(EM_POSFROMCHAR, (WPARAM)&to, compositionStart + compositionLength, "EM_POSFROMCHAR");
		if (to.y == from.y && to.x > from.x) {
			ComPtr<ID2D1SolidColorBrush> brush;
			must(dc->CreateSolidColorBrush(D2D1::ColorF(color.r, color.g, color.b, color.a), &brush), "CreateSolidColorBrush");
			float y = (from.y + caretHeight - 1) / scale;
			dc->DrawLine(D2D1::Point2F(from.x / scale, y), D2D1::Point2F(to.x / scale, y), brush.Get(), 1.0f);
		}
	}
	surface->EndDraw();
}

bool TextInput::CaretRect(float *x, float *y, float *w, float *h) const {
	if (!focused || caretX < 0 || caretY < 0) return false;
	*x = (float)caretX;
	*y = (float)caretY;
	*w = (float)(caretWidth > 0 ? caretWidth : 1);
	*h = (float)caretHeight;
	return true;
}

HRESULT STDMETHODCALLTYPE TextInput::QueryInterface(REFIID riid, void **object) {
	if (riid == IID_IUnknown || riid == kTextHost) {
		*object = static_cast<ITextHost *>(this);
		AddRef();
		return S_OK;
	}
	*object = nullptr;
	return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE TextInput::AddRef() { return ++refs; }
ULONG STDMETHODCALLTYPE TextInput::Release() { return --refs; }

HDC TextInput::TxGetDC() { return nullptr; }
INT TextInput::TxReleaseDC(HDC) { return 0; }
WINBOOL TextInput::TxShowScrollBar(INT, WINBOOL) { return FALSE; }
WINBOOL TextInput::TxEnableScrollBar(INT, INT) { return FALSE; }
WINBOOL TextInput::TxSetScrollRange(INT, LONG, INT, WINBOOL) { return FALSE; }
WINBOOL TextInput::TxSetScrollPos(INT, INT, WINBOOL) { return FALSE; }
void TextInput::TxInvalidateRect(LPCRECT, WINBOOL) { Dirty(); }
void TextInput::TxViewChange(WINBOOL) { Dirty(); }

WINBOOL TextInput::TxCreateCaret(HBITMAP, INT xWidth, INT yHeight) {
	caretWidth = xWidth;
	caretHeight = yHeight;
	Dirty();
	return TRUE;
}

WINBOOL TextInput::TxShowCaret(WINBOOL fShow) {
	caretShown = fShow && focused;
	Dirty();
	return TRUE;
}

WINBOOL TextInput::TxSetCaretPos(INT x, INT y) {
	if (x < 0 && y < 0) return FALSE;
	caretX = x;
	caretY = y;
	Dirty();
	return TRUE;
}

WINBOOL TextInput::TxSetTimer(UINT, UINT) { return FALSE; }
void TextInput::TxKillTimer(UINT) {}
void TextInput::TxScrollWindowEx(INT, INT, LPCRECT, LPCRECT, HRGN, LPRECT, UINT) { Dirty(); }
void TextInput::TxSetCapture(WINBOOL) {}
void TextInput::TxSetFocus() {}
void TextInput::TxSetCursor(HCURSOR, WINBOOL) {}
WINBOOL TextInput::TxScreenToClient(LPPOINT) { return FALSE; }
WINBOOL TextInput::TxClientToScreen(LPPOINT) { return FALSE; }
HRESULT TextInput::TxActivate(LONG *plOldState) {
	if (plOldState) *plOldState = 0;
	return S_OK;
}
HRESULT TextInput::TxDeactivate(LONG) { return S_OK; }

HRESULT TextInput::TxGetClientRect(LPRECT prc) {
	*prc = Client();
	return S_OK;
}

HRESULT TextInput::TxGetViewInset(LPRECT prc) {
	*prc = RECT{0, 0, 0, 0};
	return S_OK;
}

HRESULT TextInput::TxGetCharFormat(const CHARFORMATW **ppCF) {
	*ppCF = reinterpret_cast<const CHARFORMATW *>(&charFormat);
	return S_OK;
}

HRESULT TextInput::TxGetParaFormat(const PARAFORMAT **ppPF) {
	*ppPF = reinterpret_cast<const PARAFORMAT *>(&paraFormat);
	return S_OK;
}

COLORREF TextInput::TxGetSysColor(int nIndex) {
	if (nIndex == COLOR_WINDOWTEXT) return colorRef(color);
	if (nIndex == COLOR_WINDOW && background.a > 0) return colorRef(background);
	return GetSysColor(nIndex);
}

HRESULT TextInput::TxGetBackStyle(TXTBACKSTYLE *pstyle) {
	*pstyle = TXTBACK_TRANSPARENT;
	return S_OK;
}

HRESULT TextInput::TxGetMaxLength(DWORD *plength) {
	*plength = maxLength;
	return S_OK;
}

HRESULT TextInput::TxGetScrollBars(DWORD *pdwScrollBar) {
	*pdwScrollBar = multiline ? WS_VSCROLL | ES_AUTOVSCROLL : WS_HSCROLL | ES_AUTOHSCROLL;
	return S_OK;
}

HRESULT TextInput::TxGetPasswordChar(TCHAR *pch) {
	*reinterpret_cast<wchar_t *>(pch) = L'\x2022';
	return S_OK;
}

HRESULT TextInput::TxGetAcceleratorPos(LONG *pcp) {
	*pcp = -1;
	return S_OK;
}

HRESULT TextInput::TxGetExtent(LPSIZEL) { return E_NOTIMPL; }
HRESULT TextInput::OnTxCharFormatChange(const CHARFORMATW *) { return S_OK; }
HRESULT TextInput::OnTxParaFormatChange(const PARAFORMAT *) { return S_OK; }

HRESULT TextInput::TxGetPropertyBits(DWORD dwMask, DWORD *pdwBits) {
	*pdwBits = PropertyBits() & dwMask;
	return S_OK;
}

HRESULT TextInput::TxNotify(DWORD iNotify, void *pv) {
	if (!sink) return S_OK;
	if (iNotify == EN_UPDATE) {
		Dirty();
	} else if (iNotify == EN_CHANGE && !writing && !composing) {
		sink->InputReport(this, kInputChange, Text());
	} else if (iNotify == EN_SELCHANGE && !writing && !composing) {
		const SELCHANGE *change = static_cast<const SELCHANGE *>(pv);
		char range[48];
		snprintf(range, sizeof range, "%ld,%ld", (long)change->chrg.cpMin, (long)change->chrg.cpMax);
		sink->InputReport(this, kInputSelection, range);
	}
	return S_OK;
}

HIMC TextInput::TxImmGetContext() { return nullptr; }
void TextInput::TxImmReleaseContext(HIMC) {}

HRESULT TextInput::TxGetSelectionBarWidth(LONG *lSelBarWidth) {
	*lSelBarWidth = 0;
	return S_OK;
}
