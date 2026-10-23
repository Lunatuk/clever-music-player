#ifndef CMP_MEDIA_H
#define CMP_MEDIA_H
#include <stdint.h>
#ifdef _WIN32
#define CMP_MEDIA_API __declspec(dllexport)
#else
#define CMP_MEDIA_API __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif
/* One job across engines. Cancellation never frees a running job's memory.
 * Response is bounded UTF-8 JSON, valid until end. No caller owns its buffer. */
CMP_MEDIA_API int cmp_media_begin(void);
CMP_MEDIA_API void cmp_media_cancel(void);
CMP_MEDIA_API void cmp_media_end(void);
/* op: 0 capabilities, 1 inspect, 2 decode audio, 3 decode cover,
 * 4 digest (mode 0 packets, 1 S32LE PCM, 2 cover), 5 remux metadata.
 * cover format: 0 none, 1 PNG, 2 JPEG. tags follow the fixed key table. */
CMP_MEDIA_API const char *cmp_media_run(int op, const char *source,
    const char *output, const char *cover, int cover_format, int mode,
    int64_t max_output, const char *const tags[8]);
#ifdef __cplusplus
}
#endif
#endif
