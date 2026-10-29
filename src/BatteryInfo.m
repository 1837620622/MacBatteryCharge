#import "BatteryInfo.h"
#import "Command.h"

static BOOL firstNumber(NSString *text, NSString *key, double *out) {
    if (text.length == 0 || key.length == 0) return NO;
    NSString *token = [NSString stringWithFormat:@"\"%@\" = ", key];
    NSRange found = [text rangeOfString:token];
    if (found.location == NSNotFound) return NO;
    NSUInteger index = NSMaxRange(found);
    if (index >= text.length) return NO;
    NSMutableString *digits = [NSMutableString string];
    if ([text characterAtIndex:index] == '-') {
        [digits appendString:@"-"];
        index++;
    }
    BOOL any = NO;
    while (index < text.length) {
        unichar ch = [text characterAtIndex:index];
        if (ch < '0' || ch > '9') break;
        [digits appendFormat:@"%C", ch];
        any = YES;
        index++;
    }
    if (!any) return NO;
    if (out) *out = digits.doubleValue;
    return YES;
}

static NSInteger roundedPercent(double part, double whole) {
    if (whole <= 0 || part <= 0) return 0;
    return (NSInteger)((part * 100.0 + whole / 2.0) / whole);
}

NSDictionary *MBCParseBatteryReport(NSString *ioregText, NSString *thermText) {
    NSMutableDictionary *report = [NSMutableDictionary dictionary];
    double value = 0;
    if (firstNumber(ioregText, @"CurrentCapacity", &value)) report[@"percent"] = @((NSInteger)value);
    if (firstNumber(ioregText, @"InstantAmperage", &value) || firstNumber(ioregText, @"Amperage", &value)) report[@"milliamps"] = @((NSInteger)value);
    if (firstNumber(ioregText, @"Voltage", &value)) report[@"millivolts"] = @((NSInteger)value);
    if (firstNumber(ioregText, @"CycleCount", &value)) report[@"cycles"] = @((NSInteger)value);
    if (firstNumber(ioregText, @"DesignCycleCount9C", &value)) report[@"designCycles"] = @((NSInteger)value);
    if (firstNumber(ioregText, @"DesignCapacity", &value)) report[@"designCapacity"] = @((NSInteger)value);
    if (firstNumber(ioregText, @"NominalChargeCapacity", &value)) report[@"nominalCapacity"] = @((NSInteger)value);
    if (firstNumber(ioregText, @"AppleRawMaxCapacity", &value) || firstNumber(ioregText, @"FullChargeCapacity", &value)) {
        report[@"rawMaxCapacity"] = @((NSInteger)value);
    }
    if (firstNumber(ioregText, @"Temperature", &value)) report[@"decidegrees"] = @((NSInteger)value);
    if (firstNumber(ioregText, @"TimeChargingThermallyLimited", &value)) report[@"thermalLimited"] = @((NSInteger)value);
    if ([ioregText containsString:@"\"IsCharging\" = Yes"]) report[@"charging"] = @YES;
    else if ([ioregText containsString:@"\"IsCharging\" = No"]) report[@"charging"] = @NO;
    if ([ioregText containsString:@"\"ExternalConnected\" = Yes"]) report[@"external"] = @YES;
    else if ([ioregText containsString:@"\"ExternalConnected\" = No"]) report[@"external"] = @NO;
    NSInteger health = roundedPercent([report[@"nominalCapacity"] doubleValue], [report[@"designCapacity"] doubleValue]);
    if (health > 0) report[@"health"] = @(health);
    if ([thermText containsString:@"No thermal warning"]) report[@"thermalQuiet"] = @YES;
    else if (thermText.length > 0) report[@"thermalQuiet"] = @NO;
    return report;
}

// 1000–6000 按百分度换算。小于 200 的正数按整摄氏度。关机温度一类的大数不用。
static BOOL celsiusFromReport(NSDictionary *report, double *celsius) {
    if (report[@"decidegrees"] == nil) return NO;
    double raw = [report[@"decidegrees"] doubleValue];
    if (raw >= 1000.0 && raw <= 6000.0) {
        if (celsius) *celsius = raw / 100.0;
        return YES;
    }
    if (raw > 0.0 && raw < 200.0) {
        if (celsius) *celsius = raw;
        return YES;
    }
    return NO;
}

NSString *MBCMenuBarBottom(NSDictionary *report) {
    if (report[@"percent"] == nil && report[@"designCapacity"] == nil) return @"无电池";
    NSInteger milliamps = [report[@"milliamps"] integerValue];
    BOOL external = [report[@"external"] boolValue];
    BOOL charging = [report[@"charging"] boolValue];
    if (charging || milliamps > 50) return @"充电";
    if (milliamps < -50) return @"放电";
    if (external) return @"接通";
    return @"电池";
}

static NSString *flowLine(NSDictionary *report) {
    NSInteger milliamps = [report[@"milliamps"] integerValue];
    BOOL external = [report[@"external"] boolValue];
    BOOL charging = [report[@"charging"] boolValue];
    if (charging || milliamps > 50) return @"正在往电池里充电。";
    if (milliamps < -50) return @"正在放电。";
    if (external) return @"电源已接通，当前没有明显电流。";
    return @"没有接通电源。";
}

NSArray<NSString *> *MBCBatteryDetailLines(NSDictionary *report) {
    if (report[@"percent"] == nil && report[@"designCapacity"] == nil) {
        return @[@"没有读到内置电池。台式机通常没有电池，充电上限也不会出现。"];
    }
    NSMutableArray *lines = [NSMutableArray array];
    if (report[@"percent"] != nil) {
        [lines addObject:[NSString stringWithFormat:@"电量 %ld%%", (long)[report[@"percent"] integerValue]]];
    }
    if (report[@"milliamps"] != nil || report[@"millivolts"] != nil) {
        NSMutableString *line = [NSMutableString stringWithString:@"电流 "];
        if (report[@"milliamps"] != nil) [line appendFormat:@"%ld mA", (long)[report[@"milliamps"] integerValue]];
        else [line appendString:@"没有读到"];
        if (report[@"millivolts"] != nil) [line appendFormat:@"，电压 %.2f V", [report[@"millivolts"] doubleValue] / 1000.0];
        [lines addObject:line];
    }
    [lines addObject:flowLine(report)];
    if (report[@"health"] != nil) {
        [lines addObject:[NSString stringWithFormat:@"健康度约 %ld%%，按标称容量相对出厂设计容量估算", (long)[report[@"health"] integerValue]]];
    }
    if (report[@"nominalCapacity"] != nil && report[@"designCapacity"] != nil) {
        [lines addObject:[NSString stringWithFormat:@"标称容量 %ld，设计容量 %ld",
                           (long)[report[@"nominalCapacity"] integerValue],
                           (long)[report[@"designCapacity"] integerValue]]];
    }
    if (report[@"rawMaxCapacity"] != nil) {
        [lines addObject:[NSString stringWithFormat:@"当前满充容量 %ld", (long)[report[@"rawMaxCapacity"] integerValue]]];
    }
    if (report[@"cycles"] != nil) {
        if (report[@"designCycles"] != nil) {
            [lines addObject:[NSString stringWithFormat:@"循环 %ld 次，设计循环约 %ld 次",
                               (long)[report[@"cycles"] integerValue],
                               (long)[report[@"designCycles"] integerValue]]];
        } else {
            [lines addObject:[NSString stringWithFormat:@"循环 %ld 次", (long)[report[@"cycles"] integerValue]]];
        }
    }
    double celsius = 0;
    if (celsiusFromReport(report, &celsius)) {
        [lines addObject:[NSString stringWithFormat:@"电池温度 %.1f°C", celsius]];
    }
    if ([report[@"thermalLimited"] integerValue] > 0) {
        [lines addObject:@"系统记录过因过热而放慢充电。"];
    } else if ([report[@"thermalQuiet"] boolValue]) {
        [lines addObject:@"系统没有过热警告。"];
    } else if (report[@"thermalQuiet"] != nil) {
        [lines addObject:@"散热状态请以系统提示为准。"];
    }
    return lines;
}

NSString *MBCBatteryAdvice(NSDictionary *report) {
    if (report[@"percent"] == nil && report[@"designCapacity"] == nil) return @"没有读到内置电池。台式机通常没有电池，充电上限也不会出现。";
    NSMutableArray *lines = [NSMutableArray array];
    NSInteger percent = [report[@"percent"] integerValue];
    BOOL external = [report[@"external"] boolValue];
    [lines addObject:flowLine(report)];
    NSInteger health = [report[@"health"] integerValue];
    if (health > 0 && health < 85) {
        [lines addObject:[NSString stringWithFormat:@"满充容量大约是设计容量的 %ld%%。白天长期停在 100%% 会加快损耗，默认时间表把 06:00 到 21:00 放在 80%%。", (long)health]];
    } else if (health >= 85) {
        [lines addObject:[NSString stringWithFormat:@"按设计容量估算，健康度大约 %ld%%。", (long)health]];
    }
    NSInteger cycles = [report[@"cycles"] integerValue];
    NSInteger designCycles = [report[@"designCycles"] integerValue];
    if (cycles > 0 && designCycles > 0 && cycles * 10 >= designCycles * 8) {
        [lines addObject:[NSString stringWithFormat:@"循环 %ld 次，设计循环大约 %ld 次，已经用掉大部分。", (long)cycles, (long)designCycles]];
    }
    double celsius = 0;
    if (celsiusFromReport(report, &celsius)) {
        if (celsius >= 40.0) [lines addObject:@"电池温度偏高。把机器放在硬平面上，不要盖住出风口。"];
        else if (celsius >= 10.0) [lines addObject:@"电池温度在常见范围内。"];
    }
    if ([report[@"thermalLimited"] integerValue] > 0) {
        [lines addObject:@"系统记录过因过热而放慢充电。"];
    } else if ([report[@"thermalQuiet"] boolValue]) {
        [lines addObject:@"系统没有过热警告。"];
    }
    if (external && percent >= 95) {
        [lines addObject:@"现在接近满电。若这台机器支持充电上限，白天可以停在 80%，21:00 再放开到 100%。"];
    }
    return [lines componentsJoinedByString:@""];
}

NSDictionary *MBCReadBatteryReport(void) {
    int status = 0;
    NSString *ioregText = MBCRunCommand(@"/usr/sbin/ioreg", @[@"-r", @"-n", @"AppleSmartBattery", @"-l"], &status);
    NSString *thermText = MBCRunCommand(@"/usr/bin/pmset", @[@"-g", @"therm"], &status);
    return MBCParseBatteryReport(ioregText, thermText);
}
