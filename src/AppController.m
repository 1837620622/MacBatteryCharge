#import "AppController.h"
#import "ChargeClient.h"
#import "Command.h"
#import "LoginItem.h"
#import "Schedule.h"
#import "Settings.h"
#import "SystemPower.h"
#import "UpdateCheck.h"

static NSString *MBCVersionString(void) {
    NSString *version = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"];
    return version.length ? version : @"2.0.0";
}

@interface AppController ()
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *rows;
@property (nonatomic, strong) NSTextField *startField;
@property (nonatomic, strong) NSTextField *endField;
@property (nonatomic, strong) NSPopUpButton *limitPopup;
@property (nonatomic, strong) NSButton *lowCheck;
@property (nonatomic, strong) NSButton *loginCheck;
@property (nonatomic, strong) NSTextField *powerLabel;
@property (nonatomic, strong) NSTextField *limitLabel;
@property (nonatomic, strong) NSTextField *lowLabel;
@property (nonatomic, strong) NSTextField *targetLabel;
@property (nonatomic, strong) NSTextField *resultLabel;
@property (nonatomic, strong) NSTextField *versionLabel;
@property (nonatomic, strong) NSStatusItem *status;
@property (nonatomic, assign) NSInteger lastApplied;
@property (nonatomic, copy) NSString *updateURL;
@end

@implementation AppController

- (instancetype)init {
    self = [super init];
    if (self) {
        _rows = [NSMutableArray array];
        _lastApplied = -1;
        _updateURL = @"https://github.com/1837620622/MacBatteryCharge/releases/latest";
    }
    return self;
}

- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color {
    NSTextField *field = [NSTextField labelWithString:text];
    field.font = [NSFont systemFontOfSize:size weight:weight];
    field.textColor = color;
    field.maximumNumberOfLines = 0;
    field.lineBreakMode = NSLineBreakByWordWrapping;
    field.preferredMaxLayoutWidth = 640;
    return field;
}

- (NSTextField *)editField:(NSString *)value {
    NSTextField *field = [NSTextField textFieldWithString:value];
    field.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular];
    field.target = self;
    field.action = @selector(editorChanged:);
    [field.widthAnchor constraintEqualToConstant:72].active = YES;
    return field;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildStatusItem];
    [self buildWindow];
    [self loadRows];
    [self.table reloadData];
    if (self.rows.count > 0) [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self refreshStatus];
    [self applyChargeLimitShowingResult:NO];
    [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(timerFired) userInfo:nil repeats:YES];
    MBCCheckForUpdate(MBCVersionString(), ^(NSString *message, NSString *url, BOOL newer) {
        if (url.length) self.updateURL = url;
        self.versionLabel.stringValue = [NSString stringWithFormat:@"版本 %@　%@", MBCVersionString(), message];
        if (newer) [self offerUpdate:message];
    });
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

- (void)buildStatusItem {
    self.status = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    NSImage *image = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [[NSColor blackColor] set];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1.5, 3, 13, 11) xRadius:1.5 yRadius:1.5] stroke];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(5.5, 14.5, 5, 2) xRadius:0.6 yRadius:0.6] fill];
        [[NSBezierPath bezierPathWithRect:NSMakeRect(3.5, 5, 7, 7)] fill];
        return YES;
    }];
    image.template = YES;
    self.status.button.image = image;
    self.status.button.imagePosition = NSImageLeft;
    self.status.button.title = @" --";
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"打开窗口" action:@selector(showWindow) keyEquivalent:@""];
    [menu addItemWithTitle:@"立即应用" action:@selector(applyClicked:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"退出" action:@selector(terminate:) keyEquivalent:@"q"];
    self.status.menu = menu;
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 700, 640);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                    styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    window.title = @"充电上限";
    window.minSize = NSMakeSize(680, 600);
    window.backgroundColor = [NSColor windowBackgroundColor];
    self.window = window;

    NSView *content = window.contentView;
    NSStackView *root = [NSStackView stackViewWithViews:@[]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 8;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:content.topAnchor constant:18],
        [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [root.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor constant:-16],
    ]];

    [root addArrangedSubview:[self label:@"充电上限" size:20 weight:NSFontWeightSemibold color:NSColor.labelColor]];
    NSTextField *intro = [self label:@"06:00 来电后停在 80%。21:00 起允许充到 100%，给 23:30 断电前留出时间。时间可以自己改。电量已经高于上限时，不会自动往下放。" size:13 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    [root addArrangedSubview:intro];
    [intro.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;

    [root addArrangedSubview:[self label:@"当前状态" size:13 weight:NSFontWeightSemibold color:NSColor.labelColor]];
    self.powerLabel = [self label:@"电源：读取中" size:13 weight:NSFontWeightRegular color:NSColor.labelColor];
    self.limitLabel = [self label:@"上限：读取中" size:13 weight:NSFontWeightRegular color:NSColor.labelColor];
    self.lowLabel = [self label:@"低电量：读取中" size:13 weight:NSFontWeightRegular color:NSColor.labelColor];
    self.targetLabel = [self label:@"本时段目标：读取中" size:13 weight:NSFontWeightRegular color:NSColor.labelColor];
    NSStackView *status = [NSStackView stackViewWithViews:@[self.powerLabel, self.limitLabel, self.lowLabel, self.targetLabel]];
    status.orientation = NSUserInterfaceLayoutOrientationVertical;
    status.alignment = NSLayoutAttributeLeading;
    status.spacing = 4;
    [root addArrangedSubview:status];

    [root addArrangedSubview:[self label:@"时间段" size:13 weight:NSFontWeightSemibold color:NSColor.labelColor]];
    [root addArrangedSubview:[self label:@"结束时间早于开始时间，表示跨过午夜。没被覆盖的时间按 100%。时间段不能重叠。" size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor]];

    self.table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.table.headerView = [[NSTableHeaderView alloc] init];
    self.table.usesAlternatingRowBackgroundColors = YES;
    self.table.rowHeight = 22;
    self.table.dataSource = self;
    self.table.delegate = self;
    for (NSArray *spec in @[@[@"开始", @"start", @120], @[@"结束", @"end", @120], @[@"上限", @"limit", @120]]) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[1]];
        column.title = spec[0];
        column.width = [spec[2] doubleValue];
        column.editable = NO;
        [self.table addTableColumn:column];
    }
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.documentView = self.table;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll.heightAnchor constraintEqualToConstant:148].active = YES;
    [scroll.widthAnchor constraintEqualToConstant:660].active = YES;
    [root addArrangedSubview:scroll];

    NSButton *add = [NSButton buttonWithTitle:@"添加" target:self action:@selector(addRow:)];
    NSButton *remove = [NSButton buttonWithTitle:@"删除" target:self action:@selector(removeRow:)];
    NSStackView *rowButtons = [NSStackView stackViewWithViews:@[add, remove]];
    rowButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    rowButtons.spacing = 8;
    [root addArrangedSubview:rowButtons];

    self.startField = [self editField:@"06:00"];
    self.endField = [self editField:@"21:00"];
    self.limitPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSNumber *limit in @[@80, @85, @90, @95, @100]) {
        [self.limitPopup addItemWithTitle:[NSString stringWithFormat:@"%@%%", limit]];
        self.limitPopup.lastItem.tag = limit.integerValue;
    }
    self.limitPopup.target = self;
    self.limitPopup.action = @selector(editorChanged:);
    NSStackView *editor = [NSStackView stackViewWithViews:@[
        [self label:@"开始" size:13 weight:NSFontWeightRegular color:NSColor.labelColor], self.startField,
        [self label:@"结束" size:13 weight:NSFontWeightRegular color:NSColor.labelColor], self.endField,
        [self label:@"上限" size:13 weight:NSFontWeightRegular color:NSColor.labelColor], self.limitPopup,
    ]];
    editor.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    editor.spacing = 8;
    [root addArrangedSubview:editor];

    [root addArrangedSubview:[self label:@"低电量模式" size:13 weight:NSFontWeightSemibold color:NSColor.labelColor]];
    self.lowCheck = [NSButton checkboxWithTitle:@"使用电池时打开，接通电源后关闭" target:self action:@selector(optionChanged:)];
    self.lowCheck.state = NSControlStateValueOn;
    [root addArrangedSubview:self.lowCheck];
    [root addArrangedSubview:[self label:@"系统会分别记住电池和电源下的低电量开关。只有当前设置和这里不一致时，才要输入一次管理员密码。" size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor]];

    [root addArrangedSubview:[self label:@"通用" size:13 weight:NSFontWeightSemibold color:NSColor.labelColor]];
    self.loginCheck = [NSButton checkboxWithTitle:@"登录时打开" target:self action:@selector(optionChanged:)];
    self.loginCheck.state = NSControlStateValueOn;
    [root addArrangedSubview:self.loginCheck];
    self.versionLabel = [self label:[NSString stringWithFormat:@"版本 %@", MBCVersionString()] size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    [root addArrangedSubview:self.versionLabel];
    self.resultLabel = [self label:@"还没有应用到系统。" size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    [root addArrangedSubview:self.resultLabel];

    NSButton *update = [NSButton buttonWithTitle:@"检查更新" target:self action:@selector(checkUpdate:)];
    NSButton *uninstall = [NSButton buttonWithTitle:@"卸载" target:self action:@selector(uninstall:)];
    NSButton *apply = [NSButton buttonWithTitle:@"立即应用" target:self action:@selector(applyClicked:)];
    apply.keyEquivalent = @"\r";
    NSStackView *actions = [NSStackView stackViewWithViews:@[update, uninstall, apply]];
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.spacing = 8;
    [root addArrangedSubview:actions];

    [window center];
    [NSApp activate];
    [window makeKeyAndOrderFront:nil];
}

- (void)loadRows {
    NSDictionary *saved = MBCLoadSettings();
    NSArray *items = [saved[@"intervals"] isKindOfClass:[NSArray class]] ? saved[@"intervals"] : MBCDefaultIntervals();
    [self.rows removeAllObjects];
    for (id item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        [self.rows addObject:[item mutableCopy]];
    }
    if (self.rows.count == 0) {
        for (NSDictionary *item in MBCDefaultIntervals()) [self.rows addObject:[item mutableCopy]];
    }
    if (saved) {
        if (saved[@"lowPowerAuto"]) self.lowCheck.state = [saved[@"lowPowerAuto"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
        if (saved[@"launchAtLogin"]) self.loginCheck.state = [saved[@"launchAtLogin"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.rows.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSDictionary *item = self.rows[(NSUInteger)row];
    if ([column.identifier isEqualToString:@"limit"]) return [NSString stringWithFormat:@"%@%%", item[@"limit"]];
    return item[column.identifier] ?: @"";
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.table.selectedRow;
    if (row < 0 || row >= (NSInteger)self.rows.count) return;
    NSDictionary *item = self.rows[(NSUInteger)row];
    self.startField.stringValue = item[@"start"] ?: @"";
    self.endField.stringValue = item[@"end"] ?: @"";
    [self.limitPopup selectItemWithTag:[item[@"limit"] integerValue]];
}

- (void)editorChanged:(id)sender {
    NSInteger row = self.table.selectedRow;
    if (row < 0 || row >= (NSInteger)self.rows.count) return;
    NSMutableDictionary *item = self.rows[(NSUInteger)row];
    item[@"start"] = self.startField.stringValue;
    item[@"end"] = self.endField.stringValue;
    item[@"limit"] = @(self.limitPopup.selectedTag);
    [self.table reloadData];
    [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
}

- (void)addRow:(id)sender {
    [self.rows addObject:[@{@"start": @"12:00", @"end": @"13:00", @"limit": @90} mutableCopy]];
    [self.table reloadData];
    [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:self.rows.count - 1] byExtendingSelection:NO];
}

- (void)removeRow:(id)sender {
    NSInteger row = self.table.selectedRow;
    if (row < 0 || row >= (NSInteger)self.rows.count) {
        NSBeep();
        return;
    }
    [self.rows removeObjectAtIndex:(NSUInteger)row];
    [self.table reloadData];
}

- (void)optionChanged:(id)sender {
    [self persist:NULL];
}

- (BOOL)persist:(NSString **)error {
    NSDictionary *settings = @{
        @"intervals": self.rows,
        @"lowPowerAuto": @(self.lowCheck.state == NSControlStateValueOn),
        @"launchAtLogin": @(self.loginCheck.state == NSControlStateValueOn),
    };
    return MBCSaveSettings(settings, error);
}

- (void)timerFired {
    [self refreshStatus];
    [self applyChargeLimitShowingResult:NO];
}

- (void)refreshStatus {
    BOOL ac = NO;
    NSString *error = nil;
    if (MBCReadPowerSource(&ac, &error)) self.powerLabel.stringValue = ac ? @"电源：接通电源" : @"电源：使用电池";
    else self.powerLabel.stringValue = @"电源：读不到";

    NSInteger current = -1;
    if (!MBCChargeSupported(&error)) self.limitLabel.stringValue = @"上限：这台 Mac 不支持";
    else if (MBCChargeGetLimit(&current, &error)) self.limitLabel.stringValue = [NSString stringWithFormat:@"上限：%ld%%", (long)current];
    else self.limitLabel.stringValue = [NSString stringWithFormat:@"上限：%@", error ?: @"读不到"];

    NSInteger battery = -1;
    NSInteger plugged = -1;
    if (MBCReadLowPowerModes(&battery, &plugged, NULL)) {
        self.lowLabel.stringValue = [NSString stringWithFormat:@"低电量：电池 %@，电源 %@", battery ? @"开" : @"关", plugged ? @"开" : @"关"];
    } else {
        self.lowLabel.stringValue = @"低电量：读不到";
    }

    int coverage[1440];
    if (MBCCompileIntervals(self.rows, coverage, &error)) {
        BOOL gap = NO;
        int want = MBCLimitAtMinute(coverage, MBCCurrentMinute(), &gap);
        self.targetLabel.stringValue = gap
            ? [NSString stringWithFormat:@"本时段目标：%d%%，这段没单独设置", want]
            : [NSString stringWithFormat:@"本时段目标：%d%%", want];
        self.status.button.title = [NSString stringWithFormat:@" %d%%", want];
    } else {
        self.targetLabel.stringValue = error ?: @"时间段还不能用";
    }
}

- (BOOL)applyChargeLimitShowingResult:(BOOL)showResult {
    NSString *error = nil;
    int coverage[1440];
    if (!MBCCompileIntervals(self.rows, coverage, &error)) {
        if (showResult) self.resultLabel.stringValue = error;
        return NO;
    }
    if (!MBCChargeSupported(&error)) {
        if (showResult) self.resultLabel.stringValue = error;
        return NO;
    }
    BOOL gap = NO;
    int want = MBCLimitAtMinute(coverage, MBCCurrentMinute(), &gap);
    if (want == self.lastApplied) return YES;
    if (!MBCChargeSetLimit(want, &error)) {
        self.resultLabel.stringValue = error ?: @"充电上限没有改成";
        self.lastApplied = -1;
        return NO;
    }
    self.lastApplied = want;
    if (showResult) self.resultLabel.stringValue = [NSString stringWithFormat:@"充电上限已设为 %d%%。", want];
    return YES;
}

- (void)applyClicked:(id)sender {
    NSString *error = nil;
    int coverage[1440];
    if (!MBCCompileIntervals(self.rows, coverage, &error)) {
        self.resultLabel.stringValue = error ?: @"时间段还不能用";
        return;
    }
    if (![self persist:&error]) {
        self.resultLabel.stringValue = error ?: @"配置没有保存";
        return;
    }
    BOOL chargeOK = [self applyChargeLimitShowingResult:YES];
    [self refreshStatus];
    if (self.lowCheck.state == NSControlStateValueOn) {
        if (!MBCApplyLowPowerPolicy(&error)) {
            self.resultLabel.stringValue = error ?: @"低电量模式没有改成";
            [self refreshStatus];
            return;
        }
        if (chargeOK) self.resultLabel.stringValue = [self.resultLabel.stringValue stringByAppendingString:@"低电量已按电源切换。"];
    }
    if (![self applyLogin:&error]) {
        self.resultLabel.stringValue = error ?: @"登录启动没有改成";
        return;
    }
    [self refreshStatus];
}

- (BOOL)applyLogin:(NSString **)error {
    BOOL enabled = self.loginCheck.state == NSControlStateValueOn;
    return MBCSetLaunchAtLogin(enabled, MBCPreferredExecutable(), error);
}

- (void)showWindow {
    [NSApp activate];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)checkUpdate:(id)sender {
    self.versionLabel.stringValue = @"正在检查更新";
    MBCCheckForUpdate(MBCVersionString(), ^(NSString *message, NSString *url, BOOL newer) {
        if (url.length) self.updateURL = url;
        self.versionLabel.stringValue = [NSString stringWithFormat:@"版本 %@　%@", MBCVersionString(), message];
        if (newer) [self offerUpdate:message];
    });
}

- (void)offerUpdate:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message;
    alert.informativeText = @"打开发布页可以下载新的 PKG 或 DMG。";
    [alert addButtonWithTitle:@"打开发布页"];
    [alert addButtonWithTitle:@"稍后"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:self.updateURL]];
    }
}

- (void)uninstall:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"卸载充电上限？";
    alert.informativeText = @"会关掉登录启动，删掉这台 Mac 上的配置，并移除“应用程序”里的 MacBatteryCharge。充电上限和低电量模式保持现在的值。";
    [alert addButtonWithTitle:@"卸载"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSString *error = nil;
    MBCSetLaunchAtLogin(NO, MBCPreferredExecutable(), &error);
    [[NSFileManager defaultManager] removeItemAtPath:[MBCSettingsPath() stringByDeletingLastPathComponent] error:nil];
    NSString *app = @"/Applications/MacBatteryCharge.app";
    if ([[NSFileManager defaultManager] fileExistsAtPath:app]) {
        int status = 0;
        NSString *output = MBCRunCommand(@"/usr/bin/osascript", @[@"-e", @"do shell script \"rm -rf /Applications/MacBatteryCharge.app\" with administrator privileges"], &status);
        if (status != 0) {
            self.resultLabel.stringValue = output.length ? output : @"应用程序没有删掉";
            return;
        }
    }
    [NSApp terminate:nil];
}

@end
