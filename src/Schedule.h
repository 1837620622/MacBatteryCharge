#import <Foundation/Foundation.h>

// 一天 1440 分钟。区间是 [开始, 结束)。结束早于开始表示跨过午夜。
// 覆盖数组里 -1 表示没有区间。同一分钟被两段写到就是重叠。

FOUNDATION_EXPORT int MBCCurrentMinute(void);
FOUNDATION_EXPORT NSArray<NSDictionary *> *MBCDefaultIntervals(void);
FOUNDATION_EXPORT BOOL MBCCompileIntervals(NSArray *items, int coverage[1440], NSString **error);
FOUNDATION_EXPORT int MBCLimitAtMinute(const int coverage[1440], int minute, BOOL *gap);
