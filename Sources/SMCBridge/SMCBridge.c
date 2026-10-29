#include "SMCBridge.h"

#include <IOKit/IOKitLib.h>
#include <string.h>

// AppleSMC 用户态客户端的数据结构。布局和系统内核扩展一致，不能改。
typedef struct {
    char major;
    char minor;
    char build;
    char reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimit;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyInfo;

typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimit pLimitData;
    SMCKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParam;

enum {
    kSMCUserClientOpen = 0,
    kSMCUserClientClose = 1,
    kSMCHandleYPCEvent = 2,
    kSMCReadKey = 5,
    kSMCWriteKey = 6,
    kSMCGetKeyInfo = 9,
};

static io_connect_t gConnection = 0;

static uint32_t keyCode(const char *key) {
    uint32_t value = 0;
    for (int i = 0; i < 4; i++) value = (value << 8) | (uint8_t)key[i];
    return value;
}

static bool call(SMCParam *input, SMCParam *output) {
    if (gConnection == 0) return false;
    size_t outSize = sizeof(SMCParam);
    kern_return_t result = IOConnectCallStructMethod(gConnection, kSMCHandleYPCEvent,
                                                     input, sizeof(SMCParam), output, &outSize);
    return result == kIOReturnSuccess && output->result == 0;
}

bool SMCOpen(void) {
    if (gConnection != 0) return true;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == 0) return false;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &gConnection);
    IOObjectRelease(service);
    if (result != kIOReturnSuccess) {
        gConnection = 0;
        return false;
    }
    return true;
}

void SMCClose(void) {
    if (gConnection != 0) {
        IOServiceClose(gConnection);
        gConnection = 0;
    }
}

static bool keyInfo(const char *key, SMCKeyInfo *info) {
    SMCParam input;
    SMCParam output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = keyCode(key);
    input.data8 = kSMCGetKeyInfo;
    if (!call(&input, &output)) return false;
    *info = output.keyInfo;
    return info->dataSize > 0 && info->dataSize <= sizeof(input.bytes);
}

bool SMCHasKey(const char *key) {
    SMCKeyInfo info;
    return keyInfo(key, &info);
}

int SMCReadBytes(const char *key, uint8_t *out, size_t capacity) {
    SMCKeyInfo info;
    if (!keyInfo(key, &info) || info.dataSize > capacity) return -1;
    SMCParam input;
    SMCParam output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = keyCode(key);
    input.keyInfo.dataSize = info.dataSize;
    input.data8 = kSMCReadKey;
    if (!call(&input, &output)) return -1;
    memcpy(out, output.bytes, info.dataSize);
    return (int)info.dataSize;
}

bool SMCWriteBytes(const char *key, const uint8_t *bytes, size_t length) {
    SMCKeyInfo info;
    if (!keyInfo(key, &info) || info.dataSize != length) return false;
    SMCParam input;
    SMCParam output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = keyCode(key);
    input.keyInfo.dataSize = info.dataSize;
    input.data8 = kSMCWriteKey;
    memcpy(input.bytes, bytes, length);
    return call(&input, &output);
}
