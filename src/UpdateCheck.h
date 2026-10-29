#import <Foundation/Foundation.h>

FOUNDATION_EXPORT BOOL MBCVersionIsNewer(NSString *latest, NSString *current);
FOUNDATION_EXPORT void MBCCheckForUpdate(NSString *current, void (^completion)(NSString *message, NSString *url, BOOL newer));
