#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *MBCLaunchAgentPlist(NSString *executable);
FOUNDATION_EXPORT BOOL MBCSetLaunchAtLogin(BOOL enabled, NSString *executable, NSString **error);
