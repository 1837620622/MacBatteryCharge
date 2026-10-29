#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *MBCSettingsPath(void);
FOUNDATION_EXPORT NSDictionary *MBCLoadSettings(void);
FOUNDATION_EXPORT BOOL MBCSaveSettings(NSDictionary *settings, NSString **error);
FOUNDATION_EXPORT NSString *MBCPreferredExecutable(void);
