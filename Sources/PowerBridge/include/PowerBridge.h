#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 系统设置里的充电上限（macOS 26.4 起）。都会同步等待 PowerUIAgent，请放在后台队列调用。
BOOL MBCChargeSupported(NSString * _Nullable * _Nullable error);
BOOL MBCChargeGetLimit(NSInteger *limit, NSString * _Nullable * _Nullable error);
NSArray<NSNumber *> * _Nullable MBCChargeAvailableLimits(NSString * _Nullable * _Nullable error);
BOOL MBCChargeSetLimit(NSInteger limit, NSString * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
