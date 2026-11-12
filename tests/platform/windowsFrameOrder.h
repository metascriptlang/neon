#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
int32_t nfwSetup(void);
int32_t nfwOrder(int32_t requestFromLoop);
int32_t nfwRequests(void);
const char *nfwStage(void);
#ifdef __cplusplus
}
#endif
