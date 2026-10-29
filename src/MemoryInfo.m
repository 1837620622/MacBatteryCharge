#import "MemoryInfo.h"
#import <mach/mach.h>
#import <sys/sysctl.h>

NSDictionary *MBCMemoryReport(uint64_t totalBytes,
                              uint64_t pageSize,
                              uint64_t freeCount,
                              uint64_t activeCount,
                              uint64_t inactiveCount,
                              uint64_t wiredCount,
                              uint64_t compressorCount,
                              uint64_t speculativeCount,
                              NSInteger pressureLevel) {
    if (pageSize == 0) pageSize = 4096;
    uint64_t used = (activeCount + wiredCount + compressorCount) * pageSize;
    if (totalBytes > 0 && used > totalBytes) used = totalBytes;
    uint64_t available = (freeCount + inactiveCount + speculativeCount) * pageSize;
    if (totalBytes > 0 && available > totalBytes) available = totalBytes;
    return @{
        @"totalBytes": @(totalBytes),
        @"usedBytes": @(used),
        @"availableBytes": @(available),
        @"pressure": @(pressureLevel),
    };
}

NSString *MBCMemoryPressureName(NSInteger level) {
    switch (level) {
        case 1: return @"正常";
        case 2: return @"偏紧";
        case 4: return @"紧张";
        case 8: return @"严重";
        default: return @"未知";
    }
}

NSString *MBCFormatBytes(uint64_t bytes) {
    double gb = (double)bytes / (1024.0 * 1024.0 * 1024.0);
    if (gb >= 1.0) return [NSString stringWithFormat:@"%.1f GB", gb];
    double mb = (double)bytes / (1024.0 * 1024.0);
    return [NSString stringWithFormat:@"%.0f MB", mb];
}

NSString *MBCMemoryAdvice(NSDictionary *memory, NSDictionary *battery) {
    uint64_t total = [memory[@"totalBytes"] unsignedLongLongValue];
    if (total == 0) return @"没有读到内存容量。";
    NSInteger pressure = [memory[@"pressure"] integerValue];
    NSInteger milliamps = [battery[@"milliamps"] integerValue];
    BOOL discharging = milliamps < -50;
    if (pressure >= 4 && discharging) return @"正在放电，内存压力也高。关掉暂时不用的软件，耗电会少一些。";
    if (pressure >= 4) return @"内存压力高。这只说明内存，不说明电池坏了。";
    if (pressure == 2 && discharging) return @"正在放电，内存有些紧。";
    if (pressure == 2) return @"内存压力偏紧。";
    if (pressure == 0) return discharging ? @"正在放电。内存压力没有读到。" : @"内存容量已读到。压力等级没有读到。";
    if (discharging) return @"内存压力正常。电量变化只看电池读数。";
    return @"内存压力正常。";
}

NSDictionary *MBCReadMemoryReport(void) {
    uint64_t total = 0;
    size_t length = sizeof(total);
    sysctlbyname("hw.memsize", &total, &length, NULL, 0);
    vm_size_t page = 0;
    host_page_size(mach_host_self(), &page);
    vm_statistics64_data_t stats;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    kern_return_t result = host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&stats, &count);
    uint64_t freeCount = 0;
    uint64_t activeCount = 0;
    uint64_t inactiveCount = 0;
    uint64_t wiredCount = 0;
    uint64_t compressorCount = 0;
    uint64_t speculativeCount = 0;
    if (result == KERN_SUCCESS) {
        freeCount = stats.free_count;
        activeCount = stats.active_count;
        inactiveCount = stats.inactive_count;
        wiredCount = stats.wire_count;
        compressorCount = stats.compressor_page_count;
        speculativeCount = stats.speculative_count;
    }
    int pressure = 0;
    length = sizeof(pressure);
    sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &length, NULL, 0);
    return MBCMemoryReport(total, page, freeCount, activeCount, inactiveCount, wiredCount, compressorCount, speculativeCount, pressure);
}
