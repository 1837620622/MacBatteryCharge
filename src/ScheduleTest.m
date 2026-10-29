#import "BatteryInfo.h"
#import "GuideView.h"
#import "LoginItem.h"
#import "MemoryInfo.h"
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
        expect([MBCLowPowerAtMinute(defaults, 10 * 60) isEqualToString:@"off"], @"白天默认不用低电量");
        expect([MBCLowPowerAtMinute(defaults, 22 * 60) isEqualToString:@"battery"], @"晚间默认仅电池开低电量");
        expect([MBCLowPowerAtMinute(defaults, 5 * 60) isEqualToString:@"battery"], @"清晨仍在晚间这一段");
        expect([MBCNormalizeLowPower(@"nope") isEqualToString:@"off"], @"不认识的低电量选项按不用");

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
        expect([plist containsString:@"--background"], @"开机启动时不要弹出窗口");

        NSString *ioreg = @"\"CurrentCapacity\" = 100\n\"InstantAmperage\" = 0\n\"Voltage\" = 12578\n"
                          @"\"CycleCount\" = 618\n\"DesignCycleCount9C\" = 1000\n\"DesignCapacity\" = 5103\n"
                          @"\"NominalChargeCapacity\" = 4229\n\"AppleRawMaxCapacity\" = 4096\n"
                          @"\"Temperature\" = 3000\n\"TimeChargingThermallyLimited\" = 0\n"
                          @"\"IsCharging\" = No\n\"ExternalConnected\" = Yes\n";
        NSDictionary *report = MBCParseBatteryReport(ioreg, @"No thermal warning");
        expect([report[@"health"] integerValue] == 83, @"健康度按标称容量四舍五入");
        expect([report[@"decidegrees"] integerValue] == 3000, @"温度按百分度保存");
        expect([report[@"rawMaxCapacity"] integerValue] == 4096, @"满充容量");
        NSString *advice = MBCBatteryAdvice(report);
        expect([advice containsString:@"没有过热"], @"没有过热警告");
        expect([advice containsString:@"没有明显电流"], @"接通但没有电流");
        expect([advice containsString:@"常见范围"], @"30°C 算常见温度");
        NSString *details = [MBCBatteryDetailLines(report) componentsJoinedByString:@"\n"];
        expect([details containsString:@"30.0"], @"温度显示成摄氏度");
        expect([MBCMenuBarBottom(report) isEqualToString:@"接通"], @"菜单栏下排是接通");

        NSString *compact = @"\"CurrentCapacity\" = 100\n\"InstantAmperage\" = 0\n\"ExternalConnected\" = Yes\n"
                            @"\"IsCharging\"=0 \"DesignCapacity\"=5103,\"NominalChargeCapacity\"=4229,"
                            @"\"AppleRawMaxCapacity\"=4096,\"Temperature\"=3000,\"ShutDownTemperature\"=2982";
        NSDictionary *packed = MBCParseBatteryReport(compact, @"No thermal warning");
        expect([packed[@"decidegrees"] integerValue] == 3000, @"无空格的温度也要读到");
        expect([packed[@"health"] integerValue] == 83, @"无空格的容量也能算健康度");
        expect([packed[@"charging"] boolValue] == NO, @"IsCharging=0 不是在充电");
        expect([MBCMenuBarBottom(packed) isEqualToString:@"接通"], @"充满且接通时下排是接通");
        expect([[MBCBatteryDetailLines(packed) componentsJoinedByString:@"\n"] containsString:@"30.0"], @"紧凑文本也显示 30.0°C");
        expect([MBCMenuBarBottom(@{}) isEqualToString:@"无电池"], @"没有电池时下排写无电池");
        expect([MBCBatteryAdvice(@{}) containsString:@"没有读到内置电池"], @"台式机不要装成有电池");

        NSDictionary *memory = MBCMemoryReport(16ULL << 30, 16384, 1000, 2000, 500, 800, 100, 50, 1);
        expect([memory[@"totalBytes"] unsignedLongLongValue] == (16ULL << 30), @"总内存照传入值");
        expect([memory[@"usedBytes"] unsignedLongLongValue] == 2900ULL * 16384ULL, @"已用按活跃、联动和压缩估算");
        expect([memory[@"pressure"] integerValue] == 1, @"压力等级保留");
        expect([MBCMemoryAdvice(memory, @{@"milliamps": @0}) containsString:@"正常"], @"压力正常");
        NSDictionary *tight = MBCMemoryReport(8ULL << 30, 4096, 10, 100000, 10, 100000, 50000, 0, 4);
        expect([MBCMemoryAdvice(tight, @{@"milliamps": @(-400)}) containsString:@"放电"], @"放电且内存紧要一起说");

        NSArray *titles = MBCGuideStepTitles();
        NSString *bodies = [MBCGuideStepBodies() componentsJoinedByString:@"\n"];
        expect(titles.count == 6 && MBCGuideStepBodies().count == 6, @"引导是六步");
        expect([[titles componentsJoinedByString:@" "] containsString:@"刘海"], @"引导讲刘海");
        expect([bodies containsString:@"管理员"], @"引导讲管理员密码");
        expect([bodies containsString:@"不会为了降到 80%"], @"引导讲不会放电");
        expect(![bodies containsString:@"完全磁盘"], @"引导不索要磁盘权限");
        expect(![bodies containsString:@"辅助功能"], @"引导不索要辅助功能");

        if (failures) {
            fprintf(stderr, "%d failed\n", failures);
            return 1;
        }
        printf("schedule tests passed\n");
    }
    return 0;
}
