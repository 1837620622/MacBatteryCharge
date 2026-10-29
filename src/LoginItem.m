#import "LoginItem.h"
#import "Command.h"
#include <unistd.h>

static NSString *agentPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/com.macbatterycharge.agent.plist"];
}

NSString *MBCLaunchAgentPlist(NSString *executable) {
    return [NSString stringWithFormat:
            @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
            @"<plist version=\"1.0\"><dict>\n"
            @"<key>Label</key><string>com.macbatterycharge.agent</string>\n"
            @"<key>ProgramArguments</key><array><string>%@</string><string>--background</string></array>\n"
            @"<key>RunAtLoad</key><true/>\n"
            @"<key>LimitLoadToSessionType</key><string>Aqua</string>\n"
            @"</dict></plist>\n",
            executable];
}

BOOL MBCSetLaunchAtLogin(BOOL enabled, NSString *executable, NSString **error) {
    NSString *path = agentPath();
    NSString *directory = [path stringByDeletingLastPathComponent];
    NSFileManager *files = [NSFileManager defaultManager];
    [files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *domain = [NSString stringWithFormat:@"gui/%d", getuid()];
    int status = 0;
    // 登录项拉起的进程如果 bootout 自己，这次运行会立刻退出。也不 bootstrap，避免菜单栏两个图标。
    BOOL background = [[NSProcessInfo processInfo].arguments containsObject:@"--background"];
    if (!enabled) {
        [files removeItemAtPath:path error:nil];
        if (!background) MBCRunCommand(@"/bin/launchctl", @[@"bootout", domain, path], &status);
        return YES;
    }
    NSString *plist = MBCLaunchAgentPlist(executable);
    if (![plist writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
        if (error) *error = @"写不开机启动项";
        return NO;
    }
    if (!background) MBCRunCommand(@"/bin/launchctl", @[@"bootout", domain, path], &status);
    return YES;
}
