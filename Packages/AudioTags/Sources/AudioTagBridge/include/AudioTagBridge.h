#ifndef ND_AUDIO_TAG_BRIDGE_H
#define ND_AUDIO_TAG_BRIDGE_H
#ifdef __cplusplus
extern "C" {
#endif
// UTF-8 JSON result. Caller releases with NDTagFree. Errors use {"error": ...}.
char *NDTagRead(const char *path);
char *NDTagWrite(const char *path, const char *json);
void NDTagFree(char *value);
#ifdef __cplusplus
}
#endif
#endif
