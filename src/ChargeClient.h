#import <Foundation/Foundation.h>

FOUNDATION_EXPORT BOOL MBCChargeSupported(NSString **error);
FOUNDATION_EXPORT BOOL MBCChargeGetLimit(NSInteger *limit, NSString **error);
FOUNDATION_EXPORT BOOL MBCChargeSetLimit(NSInteger limit, NSString **error);
