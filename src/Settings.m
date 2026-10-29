#import "Settings.h"

NSString *MBCSettingsPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/MacBatteryCharge/settings.json"];
}

NSDictionary *MBCLoadSettings(void) {
    NSData *data = [NSData dataWithContentsOfFile:MBCSettingsPath()];
    if (!data) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

BOOL MBCSaveSettings(NSDictionary *settings, NSString **error) {
    NSString *path = MBCSettingsPath();
    NSString *directory = [path stringByDeletingLastPathComponent];
    NSError *failure = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&failure]) {
        if (error) *error = failure.localizedDescription ?: @"建不了配置目录";
        return NO;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:settings options:NSJSONWritingPrettyPrinted error:&failure];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:&failure]) {
        if (error) *error = failure.localizedDescription ?: @"配置没有写上";
        return NO;
    }
    return YES;
}

NSString *MBCPreferredExecutable(void) {
    NSString *installed = @"/Applications/MacBatteryCharge.app/Contents/MacOS/MacBatteryCharge";
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:installed]) return installed;
    return [NSBundle mainBundle].executablePath ?: installed;
}
