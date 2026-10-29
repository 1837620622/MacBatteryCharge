#import <Foundation/Foundation.h>

// 从 ioreg 和 pmset 文本里取出电池数字。读不到的键不放进字典。
// 温度以 decidegrees 保存：3000 表示 30.00°C。健康度是标称容量相对设计容量的估算。
FOUNDATION_EXPORT NSDictionary *MBCParseBatteryReport(NSString *ioregText, NSString *thermText);
FOUNDATION_EXPORT NSArray<NSString *> *MBCBatteryDetailLines(NSDictionary *report);
FOUNDATION_EXPORT NSString *MBCBatteryAdvice(NSDictionary *report);
// 菜单栏下排的短字：充电、放电、接通、电池、无电池。
FOUNDATION_EXPORT NSString *MBCMenuBarBottom(NSDictionary *report);
FOUNDATION_EXPORT NSDictionary *MBCReadBatteryReport(void);
