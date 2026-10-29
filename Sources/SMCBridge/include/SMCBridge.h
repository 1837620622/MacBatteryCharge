#ifndef SMCBridge_h
#define SMCBridge_h

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 打开 AppleSMC。成功返回 true。只有 root 的帮手用，主程序不链接这一块的调用。
bool SMCOpen(void);
void SMCClose(void);

/// 这个键在这台机器上有没有（并且有数据长度）。
bool SMCHasKey(const char *key);
/// 读键的原始字节。返回字节数，失败返回 -1。
int SMCReadBytes(const char *key, uint8_t *out, size_t capacity);
/// 写键的原始字节。长度必须和键的长度一致。
bool SMCWriteBytes(const char *key, const uint8_t *bytes, size_t length);

#ifdef __cplusplus
}
#endif

#endif
