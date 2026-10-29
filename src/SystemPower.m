#import "SystemPower.h"
#import "Command.h"

BOOL MBCParseDrawingAC(NSString *text, BOOL *ac) {
    if ([text containsString:@"Now drawing from 'AC Power'"]) {
        if (ac) *ac = YES;
        return YES;
    }
    if ([text containsString:@"Now drawing from 'Battery Power'"]) {
        if (ac) *ac = NO;
        return YES;
    }
    return NO;
}

static NSInteger lastInteger(NSString *line) {
    NSArray *parts = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    for (NSInteger i = (NSInteger)parts.count - 1; i >= 0; i--) {
        NSString *part = parts[(NSUInteger)i];
        if (part.length > 0) return part.integerValue;
    }
    return -1;
}

BOOL MBCParseCustomLowPower(NSString *text, NSInteger *batteryMode, NSInteger *acMode) {
    BOOL seenBattery = NO;
    BOOL seenAC = NO;
    NSInteger battery = -1;
    NSInteger ac = -1;
    NSString *section = @"";
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([line hasPrefix:@"Battery Power"]) {
            section = @"battery";
            continue;
        }
        if ([line hasPrefix:@"AC Power"]) {
            section = @"ac";
            continue;
        }
        if ([line hasPrefix:@"UPS Power"] || [line hasSuffix:@":"]) {
            section = @"";
            continue;
        }
        if (![line hasPrefix:@"lowpowermode"]) continue;
        NSInteger value = lastInteger(line);
        if ([section isEqualToString:@"battery"]) {
            battery = value;
            seenBattery = YES;
        } else if ([section isEqualToString:@"ac"]) {
            ac = value;
            seenAC = YES;
        }
    }
    if (!seenBattery || !seenAC) return NO;
    if (batteryMode) *batteryMode = battery;
    if (acMode) *acMode = ac;
    return YES;
}

BOOL MBCReadPowerSource(BOOL *ac, NSString **error) {
    int status = 0;
    NSString *text = MBCRunCommand(@"/usr/bin/pmset", @[@"-g", @"batt"], &status);
    if (MBCParseDrawingAC(text, ac)) return YES;
    if (error) *error = text.length ? text : @"读不到电源状态";
    return NO;
}

BOOL MBCReadLowPowerModes(NSInteger *batteryMode, NSInteger *acMode, NSString **error) {
    int status = 0;
    NSString *text = MBCRunCommand(@"/usr/bin/pmset", @[@"-g", @"custom"], &status);
    if (MBCParseCustomLowPower(text, batteryMode, acMode)) return YES;
    if (error) *error = @"读不到低电量模式";
    return NO;
}

BOOL MBCApplyLowPowerPolicy(NSString **error) {
    // pmset 写入需要管理员。系统会记住电池和电源两套配置，所以只在不一致时问一次密码。
    NSInteger battery = -1;
    NSInteger ac = -1;
    if (MBCReadLowPowerModes(&battery, &ac, NULL) && battery == 1 && ac == 0) return YES;
    int status = 0;
    NSString *script = @"do shell script \"pmset -b lowpowermode 1; pmset -c lowpowermode 0\" with administrator privileges";
    NSString *output = MBCRunCommand(@"/usr/bin/osascript", @[@"-e", script], &status);
    if (status != 0) {
        if (error) *error = output.length ? output : @"没有获得管理员权限，低电量模式未改";
        return NO;
    }
    return YES;
}
