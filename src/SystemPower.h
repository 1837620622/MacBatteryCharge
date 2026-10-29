#import <Foundation/Foundation.h>

FOUNDATION_EXPORT BOOL MBCParseDrawingAC(NSString *text, BOOL *ac);
FOUNDATION_EXPORT BOOL MBCParseCustomLowPower(NSString *text, NSInteger *batteryMode, NSInteger *acMode);
FOUNDATION_EXPORT BOOL MBCReadPowerSource(BOOL *ac, NSString **error);
FOUNDATION_EXPORT BOOL MBCReadLowPowerModes(NSInteger *batteryMode, NSInteger *acMode, NSString **error);
FOUNDATION_EXPORT BOOL MBCApplyLowPowerModes(NSInteger batteryMode, NSInteger acMode, NSString **error);
