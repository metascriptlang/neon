#pragma once
#include <windows.h>
#include <richedit.h>
#include <textserv.h>
#include <cstdint>
#include <memory>
#include <string>
#include "composition.h"

class ITextServices2;
class TextInput;

// The control phases a text input reports, as src/platform/native/bridge.h numbers them.
enum InputPhase { kInputChange = 0, kInputFocus = 1, kInputBlur = 2, kInputSubmit = 3, kInputSelection = 9 };

class TextInputSink {
public:
	virtual ~TextInputSink() {}
	virtual void InputReport(TextInput *input, int phase, const std::string &value) = 0;
	virtual void InputDirty(TextInput *input) = 0;
};

// RNW's WindowsTextInputComponentView on a windowless RichEdit: Msftedit's text services draw into the view's
// composition surface through Direct2D, and the caret is a child visual. Keys, text and IME composition arrive
// as Ion's input records, so RichEdit's own IME stays off.
class TextInput : public ITextHost {
public:
	TextInput(TextInputSink *sink, void *owner, bool multiline);
	~TextInput();

	void *Owner() const { return owner; }
	bool SetProp(const char *name, const char *value);
	void SetColor(Color color);
	void SetFont(float size, bool bold);
	void SetFamily(const char *utf8);
	void SetAlignment(const char *value);
	void SetWritingDirection(const char *value);
	void SetBackground(Color color);
	void SetScale(float scale);
	void Measure(float maxWidth, float scale, float *width, float *height);
	bool BlursOnSubmit() const { return blurOnSubmit; }
	bool TakeAutoFocus();
	std::string Text();

	void Focus(bool focused);
	void WindowFocus(bool focused);
	void Key(int action, int scancode, bool ctrl, const char *text);
	void Insert(const char *utf8);
	void Preedit(const char *utf8, int cursor);
	void Pointer(int kind, float pixelX, float pixelY);

	bool NeedsDraw(int32_t pixelWidth, int32_t pixelHeight) const;
	void Draw(ICompositionContext *context, IVisual *visual, int32_t pixelWidth, int32_t pixelHeight, float scale);
	// The caret in the surface's pixels, false while it is hidden.
	bool CaretRect(float *x, float *y, float *w, float *h) const;

	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **object) override;
	ULONG STDMETHODCALLTYPE AddRef() override;
	ULONG STDMETHODCALLTYPE Release() override;

	HDC TxGetDC() override;
	INT TxReleaseDC(HDC hdc) override;
	WINBOOL TxShowScrollBar(INT fnBar, WINBOOL fShow) override;
	WINBOOL TxEnableScrollBar(INT fuSBFlags, INT fuArrowflags) override;
	WINBOOL TxSetScrollRange(INT fnBar, LONG nMinPos, INT nMaxPos, WINBOOL fRedraw) override;
	WINBOOL TxSetScrollPos(INT fnBar, INT nPos, WINBOOL fRedraw) override;
	void TxInvalidateRect(LPCRECT prc, WINBOOL fMode) override;
	void TxViewChange(WINBOOL fUpdate) override;
	WINBOOL TxCreateCaret(HBITMAP hbmp, INT xWidth, INT yHeight) override;
	WINBOOL TxShowCaret(WINBOOL fShow) override;
	WINBOOL TxSetCaretPos(INT x, INT y) override;
	WINBOOL TxSetTimer(UINT idTimer, UINT uTimeout) override;
	void TxKillTimer(UINT idTimer) override;
	void TxScrollWindowEx(INT dx, INT dy, LPCRECT lprcScroll, LPCRECT lprcClip, HRGN hrgnUpdate, LPRECT lprcUpdate, UINT fuScroll) override;
	void TxSetCapture(WINBOOL fCapture) override;
	void TxSetFocus() override;
	void TxSetCursor(HCURSOR hcur, WINBOOL fText) override;
	WINBOOL TxScreenToClient(LPPOINT lppt) override;
	WINBOOL TxClientToScreen(LPPOINT lppt) override;
	HRESULT TxActivate(LONG *plOldState) override;
	HRESULT TxDeactivate(LONG lNewState) override;
	HRESULT TxGetClientRect(LPRECT prc) override;
	HRESULT TxGetViewInset(LPRECT prc) override;
	HRESULT TxGetCharFormat(const CHARFORMATW **ppCF) override;
	HRESULT TxGetParaFormat(const PARAFORMAT **ppPF) override;
	COLORREF TxGetSysColor(int nIndex) override;
	HRESULT TxGetBackStyle(TXTBACKSTYLE *pstyle) override;
	HRESULT TxGetMaxLength(DWORD *plength) override;
	HRESULT TxGetScrollBars(DWORD *pdwScrollBar) override;
	HRESULT TxGetPasswordChar(TCHAR *pch) override;
	HRESULT TxGetAcceleratorPos(LONG *pcp) override;
	HRESULT TxGetExtent(LPSIZEL lpExtent) override;
	HRESULT OnTxCharFormatChange(const CHARFORMATW *pcf) override;
	HRESULT OnTxParaFormatChange(const PARAFORMAT *ppf) override;
	HRESULT TxGetPropertyBits(DWORD dwMask, DWORD *pdwBits) override;
	HRESULT TxNotify(DWORD iNotify, void *pv) override;
	HIMC TxImmGetContext() override;
	void TxImmReleaseContext(HIMC himc) override;
	HRESULT TxGetSelectionBarWidth(LONG *lSelBarWidth) override;

private:
	LRESULT Send(UINT message, WPARAM wParam, LPARAM lParam, const char *what);
	DWORD PropertyBits() const;
	void ChangeBits(DWORD mask);
	void SetFormat();
	void Write(const std::wstring &text);
	void Select(LONG start, LONG end);
	void Dirty();
	RECT Client() const;

	TextInputSink *sink;
	void *owner;
	ULONG refs = 1;
	ITextServices2 *services = nullptr;
	bool multiline;
	bool focused = false;
	bool windowFocused = true;
	bool readOnly = false;
	bool secure = false;
	bool blurOnSubmit;
	bool autoFocus = false;
	int writing = 0;
	DWORD maxLength = 0x7FFFFFFE;
	std::wstring placeholder;
	Color placeholderColor = {0.5f, 0.5f, 0.5f, 1};
	Color color = {0, 0, 0, 1};
	Color background = {0, 0, 0, 0};
	float size = 17;
	bool bold = false;
	std::wstring family = L"Segoe UI";
	WORD alignment = PFA_LEFT;
	bool rightToLeft = false;
	float insetLeft = 0, insetTop = 0, insetRight = 0, insetBottom = 0;
	CHARFORMAT2W charFormat;
	PARAFORMAT2 paraFormat;
	bool composing = false;
	LONG compositionStart = 0;
	LONG compositionLength = 0;
	bool pointerHeld = false;
	float scale = 1;
	bool paintDirty = true;
	int32_t drawnWidth = 0, drawnHeight = 0;
	std::unique_ptr<IDrawingSurface> surface;
	IVisual *parentVisual = nullptr;
	IVisual *caret = nullptr;
	int caretWidth = 1, caretHeight = 0;
	int caretX = -1, caretY = -1;
	bool caretShown = false;
};
