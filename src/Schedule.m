#import "Schedule.h"

int MBCCurrentMinute(void) {
    NSDateComponents *parts = [[NSCalendar currentCalendar] components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:[NSDate date]];
    return (int)parts.hour * 60 + (int)parts.minute;
}

NSArray<NSDictionary *> *MBCDefaultIntervals(void) {
    // 06:00 来电后停在 80%。21:00 放开到 100%，给 23:30 断电前留出约 2.5 小时。
    return @[
        @{@"start": @"06:00", @"end": @"21:00", @"limit": @80},
        @{@"start": @"21:00", @"end": @"06:00", @"limit": @100},
    ];
}

static BOOL parseClock(NSString *text, int *minute) {
    if (![text isKindOfClass:[NSString class]]) return NO;
    NSArray *parts = [text componentsSeparatedByString:@":"];
    if (parts.count != 2) return NO;
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    for (NSString *part in parts) {
        if (part.length == 0 || part.length > 2) return NO;
        if ([part rangeOfCharacterFromSet:[digits invertedSet]].location != NSNotFound) return NO;
    }
    int hour = [parts[0] intValue];
    int min = [parts[1] intValue];
    if (hour > 23 || min > 59) return NO;
    *minute = hour * 60 + min;
    return YES;
}

static BOOL allowedLimit(int limit) {
    switch (limit) {
        case 80:
        case 85:
        case 90:
        case 95:
        case 100:
            return YES;
        default:
            return NO;
    }
}

BOOL MBCCompileIntervals(NSArray *items, int coverage[1440], NSString **error) {
    for (int i = 0; i < 1440; i++) coverage[i] = -1;
    if (![items isKindOfClass:[NSArray class]]) {
        if (error) *error = @"时间段格式不正确";
        return NO;
    }
    if (items.count > 12) {
        if (error) *error = @"最多 12 个时间段";
        return NO;
    }
    NSInteger index = 0;
    for (id item in items) {
        index++;
        if (![item isKindOfClass:[NSDictionary class]]) {
            if (error) *error = @"时间段格式不正确";
            return NO;
        }
        NSDictionary *row = item;
        int start = 0;
        int end = 0;
        if (!parseClock(row[@"start"], &start) || !parseClock(row[@"end"], &end)) {
            if (error) *error = [NSString stringWithFormat:@"第 %ld 段的时间要用 24 小时制，例如 21:00", (long)index];
            return NO;
        }
        if (start == end) {
            if (error) *error = [NSString stringWithFormat:@"第 %ld 段的开始和结束不能相同", (long)index];
            return NO;
        }
        int limit = [row[@"limit"] intValue];
        if (!allowedLimit(limit)) {
            if (error) *error = [NSString stringWithFormat:@"第 %ld 段的上限只能是 80、85、90、95 或 100", (long)index];
            return NO;
        }
        // 从开始走到结束前一分钟。跨过午夜时走到 23:59 后从 0 继续。
        int cursor = start;
        while (cursor != end) {
            if (coverage[cursor] != -1) {
                if (error) *error = @"时间段有重叠";
                return NO;
            }
            coverage[cursor] = limit;
            cursor = (cursor + 1) % 1440;
        }
    }
    return YES;
}

int MBCLimitAtMinute(const int coverage[1440], int minute, BOOL *gap) {
    if (minute < 0 || minute > 1439) minute = 0;
    if (coverage[minute] < 0) {
        if (gap) *gap = YES;
        return 100;
    }
    if (gap) *gap = NO;
    return coverage[minute];
}
