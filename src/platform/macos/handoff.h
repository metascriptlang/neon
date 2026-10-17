#ifndef NEON_MACOS_HANDOFF_H
#define NEON_MACOS_HANDOFF_H

#ifndef MS_CLOSURE_DEFINED
#define MS_CLOSURE_DEFINED
typedef struct {
	void *fn;
	void *env;
} msClosure;
#endif

#ifdef __cplusplus
extern "C" {
#endif

// root is the NSView an owner hands over (Ion's windowRoot); sizes are in points.
void nimAttach(void *root, float scale, float logicalWidth, float logicalHeight);
void nimFrame(void);
void nimResize(float scale, float logicalWidth, float logicalHeight);
void nimSetFrameRequester(msClosure requester);
int nimStoredAccessibility(const char *name, const char *value);
// Text layouts built since the process began, so a check can see that a colour change built none.
int nimLayoutsBuilt(void);
void nimShutdown(void);

#ifdef __cplusplus
}
#endif

#endif
