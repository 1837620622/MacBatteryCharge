#import "Command.h"

NSString *MBCRunCommand(NSString *executable, NSArray<NSString *> *arguments, int *status) {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = arguments ?: @[];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        if (status) *status = 127;
        return error.localizedDescription ?: @"无法运行命令";
    }
    [task waitUntilExit];
    if (status) *status = task.terminationStatus;
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}
