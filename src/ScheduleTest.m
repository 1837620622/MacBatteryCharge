#import "LoginItem.h"
#import "Schedule.h"
#import "SystemPower.h"
#import "UpdateCheck.h"

static int failures = 0;

static void expect(BOOL condition, NSString *message) {
    if (condition) return;
    failures++;
    fprintf(stderr, "FAIL %s\n", message.UTF8String);
}

static int limitAt(NSArray *items, int minute, BOOL *gap, NSString **error) {
    int coverage[1440];
    if (!MBCCompileIntervals(items, coverage, error)) return -1;
    return MBCLimitAtMinute(coverage, minute, gap);
}

int main(void) {
    @autoreleasepool {
        NSArray *defaults = MBCDefaultIntervals();
        NSString *error = nil;
        BOOL gap = NO;
        expect(limitAt(defaults, 5 * 60 + 59, &gap, &error) == 100 && !gap, @"05:59 应为 100");
        expect(limitAt(defaults, 6 * 60, &gap, &error) == 80 && !gap, @"06:00 应为 80");
        expect(limitAt(defaults, 20 * 60 + 59, &gap, &error) == 80 && !gap, @"20:59 应为 80");
        expect(limitAt(defaults, 21 * 60, &gap, &error) == 100 && !gap, @"21:00 应为 100");
        expect(limitAt(defaults, 23 * 60 + 30, &gap, &error) == 100 && !gap, @"23:30 应为 100");

        int coverage[1440];
        expect(MBCCompileIntervals(defaults, coverage, &error), @"默认时间段应能通过");
        BOOL anyGap = NO;
        for (int minute = 0; minute < 1440; minute++) {
            BOOL one = NO;
            MBCLimitAtMinute(coverage, minute, &one);
            if (one) anyGap = YES;
        }
        expect(!anyGap, @"默认时间段应盖住一整天");

        expect(!MBCCompileIntervals(@[@{@"start": @"06:00", @"end": @"12:00", @"limit": @80},
                                      @{@"start": @"11:00", @"end": @"13:00", @"limit": @90}], coverage, &error), @"重叠应拒绝");
        expect(!MBCCompileIntervals(@[@{@"start": @"25:00", @"end": @"26:00", @"limit": @80}], coverage, &error), @"非法时间应拒绝");
        expect(!MBCCompileIntervals(@[@{@"start": @"06:00", @"end": @"07:00", @"limit": @70}], coverage, &error), @"70 应拒绝");
        expect(!MBCCompileIntervals(@[@{@"start": @"06:00", @"end": @"06:00", @"limit": @80}], coverage, &error), @"零长度应拒绝");

        gap = NO;
        int lone = limitAt(@[@{@"start": @"06:00", @"end": @"21:00", @"limit": @80}], 22 * 60, &gap, &error);
        expect(lone == 100 && gap, @"空档应按 100");

        expect(MBCVersionIsNewer(@"v2.0.1", @"2.0.0"), @"新版本应判断为更新");
        expect(!MBCVersionIsNewer(@"v2.0.0", @"2.0.0"), @"相同版本不是更新");
        expect(!MBCVersionIsNewer(@"v1.9.9", @"2.0.0"), @"旧版本不是更新");
        expect(MBCVersionIsNewer(@"2.1", @"2.0.9"), @"少一段的版本号也能比");
        expect(!MBCVersionIsNewer(@"beta", @"2.0.0"), @"无法解析的版本不是更新");

        BOOL ac = NO;
        expect(MBCParseDrawingAC(@"Now drawing from 'AC Power'\n", &ac) && ac, @"市电文本");
        expect(MBCParseDrawingAC(@"Now drawing from 'Battery Power'\n", &ac) && !ac, @"电池文本");
        expect(!MBCParseDrawingAC(@"nothing", &ac), @"认不出的电源文本");

        NSString *custom = @"Battery Power:\n lowpowermode         1\nAC Power:\n lowpowermode         0\n";
        NSInteger battery = -1;
        NSInteger plugged = -1;
        expect(MBCParseCustomLowPower(custom, &battery, &plugged) && battery == 1 && plugged == 0, @"低电量配置文本");
        expect(!MBCParseCustomLowPower(@"Battery Power:\n lowpowermode 1\n", &battery, &plugged), @"缺电源段应失败");

        NSString *plist = MBCLaunchAgentPlist(@"/Applications/MacBatteryCharge.app/Contents/MacOS/MacBatteryCharge");
        expect([plist containsString:@"com.macbatterycharge.agent"], @"启动项要有标签");
        expect([plist containsString:@"/Applications/MacBatteryCharge.app/Contents/MacOS/MacBatteryCharge"], @"启动项要指向程序");
        expect([plist containsString:@"<key>RunAtLoad</key><true/>"], @"启动项要在登录时运行");

        if (failures) {
            fprintf(stderr, "%d failed\n", failures);
            return 1;
        }
        printf("schedule tests passed\n");
    }
    return 0;
}
