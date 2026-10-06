#include <stdint.h>
int32_t nmViewsCreated(void);
int32_t nmReleaseCalls(void);
void nmTouch(int32_t tag, int32_t phase);
void nmTeardown(void);
int32_t nmLoop(void);
void nmMount(void);
void nmResize(float width, float height);
void nmScroll(int32_t tag, float x, float y, float width, float height, float contentWidth, float contentHeight);
int32_t nmLastScrollTag(void);
float nmContentWidth(void);
float nmContentHeight(void);
float nmScrolledX(void);
float nmScrolledY(void);
int32_t nmScrolledAnimated(void);
int32_t nmContentSizeWrites(void);
int32_t nmScrollFrameWrites(void);
int32_t nmScreenHeightReads(void);
