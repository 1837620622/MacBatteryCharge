#import <Foundation/Foundation.h>

// 内存数字来自调用方传入的 sysctl / host_statistics 计数，方便用固定样本测试。
// usedBytes、availableBytes 是估算，不是活动监视器的同名栏目。
FOUNDATION_EXPORT NSDictionary *MBCMemoryReport(uint64_t totalBytes,
                                                 uint64_t pageSize,
                                                 uint64_t freeCount,
                                                 uint64_t activeCount,
                                                 uint64_t inactiveCount,
                                                 uint64_t wiredCount,
                                                 uint64_t compressorCount,
                                                 uint64_t speculativeCount,
                                                 NSInteger pressureLevel);
FOUNDATION_EXPORT NSString *MBCMemoryPressureName(NSInteger level);
FOUNDATION_EXPORT NSString *MBCFormatBytes(uint64_t bytes);
FOUNDATION_EXPORT NSString *MBCMemoryAdvice(NSDictionary *memory, NSDictionary *battery);
FOUNDATION_EXPORT NSDictionary *MBCReadMemoryReport(void);
