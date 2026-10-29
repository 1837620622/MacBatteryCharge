#import "AppController.h"
#import "BatteryInfo.h"
#import "ChargeClient.h"
#import "Command.h"
#import "GuideView.h"
#import "LoginItem.h"
#import "MemoryInfo.h"
#import "Schedule.h"
#import "Settings.h"
#import "SystemPower.h"
#import "UpdateCheck.h"

static NSString *MBCVersionString(void) {
    NSString *version = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"];
    return version.length ? version : @"2.1.0";
}

static NSString *MBCInstalledExecutable(void) {
    return @"/Applications/MacBatteryCharge.app/Contents/MacOS/MacBatteryCharge";
}

static NSString *MBCLowPowerTitle(NSString *value) {
    value = MBCNormalizeLowPower(value);
    if ([value isEqualToString:@"on"]) return @"一直开";
    if ([value isEqualToString:@"battery"]) return @"仅电池";
    return @"不用";
}

static void MBCModesForLowPower(NSString *value, NSInteger *battery, NSInteger *ac) {
    value = MBCNormalizeLowPower(value);
    if ([value isEqualToString:@"on"]) {
        *battery = 1;
        *ac = 1;
    } else if ([value isEqualToString:@"battery"]) {
        *battery = 1;
        *ac = 0;
    } else {
        *battery = 0;
        *ac = 0;
    }
}

static void MBCSplitClock(NSString *text, NSInteger *hour, NSInteger *minute) {
    *hour = 0;
    *minute = 0;
    if (![text isKindOfClass:[NSString class]]) return;
    NSArray *parts = [text componentsSeparatedByString:@":"];
    if (parts.count != 2) return;
    NSInteger h = [parts[0] integerValue];
    NSInteger m = [parts[1] integerValue];
    if (h >= 0 && h <= 23) *hour = h;
    if (m >= 0 && m <= 59) *minute = m;
}

static BOOL MBCScreenHasNotch(void) {
    if (@available(macOS 12.0, *)) {
        for (NSScreen *screen in [NSScreen screens]) {
            if (screen.safeAreaInsets.top > 0) return YES;
            if (!NSIsEmptyRect(screen.auxiliaryTopLeftArea) || !NSIsEmptyRect(screen.auxiliaryTopRightArea)) return YES;
        }
    }
    return NO;
}

@interface AppController ()
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSScrollView *mainScroll;
@property (nonatomic, strong) MBCGuideView *guide;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *rows;
@property (nonatomic, strong) NSPopUpButton *startHour;
@property (nonatomic, strong) NSPopUpButton *startMinute;
@property (nonatomic, strong) NSPopUpButton *endHour;
@property (nonatomic, strong) NSPopUpButton *endMinute;
@property (nonatomic, strong) NSPopUpButton *limitPopup;
@property (nonatomic, strong) NSButton *lowOff;
@property (nonatomic, strong) NSButton *lowOn;
@property (nonatomic, strong) NSButton *lowBattery;
@property (nonatomic, strong) NSButton *loginCheck;
@property (nonatomic, strong) NSPopover *clockPopover;
@property (nonatomic, strong) NSDatePicker *clockPicker;
@property (nonatomic, assign) BOOL clockEditsStart;
@property (nonatomic, assign) BOOL suppressEditor;
@property (nonatomic, strong) NSTextField *chargeValue;
@property (nonatomic, strong) NSTextField *flowValue;
@property (nonatomic, strong) NSTextField *currentValue;
@property (nonatomic, strong) NSTextField *healthValue;
@property (nonatomic, strong) NSTextField *tempValue;
@property (nonatomic, strong) NSTextField *memoryValue;
@property (nonatomic, strong) NSTextField *adviceLabel;
@property (nonatomic, strong) NSTextField *powerValue;
@property (nonatomic, strong) NSTextField *limitValue;
@property (nonatomic, strong) NSTextField *lowValue;
@property (nonatomic, strong) NSTextField *lowHint;
@property (nonatomic, strong) NSTextField *targetValue;
@property (nonatomic, strong) NSTextField *resultLabel;
@property (nonatomic, strong) NSTextField *versionLabel;
@property (nonatomic, strong) NSStatusItem *status;
@property (nonatomic, assign) NSInteger lastApplied;
@property (nonatomic, assign) BOOL guideSeen;
@property (nonatomic, assign) BOOL backgroundLaunch;
@property (nonatomic, assign) BOOL updateOffered;
@property (nonatomic, copy) NSString *pendingUpdate;
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
    field.preferredMaxLayoutWidth = 360;
    return field;
}

- (NSPopUpButton *)clockPopup:(NSInteger)count {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSInteger i = 0; i < count; i++) {
        [popup addItemWithTitle:[NSString stringWithFormat:@"%02ld", (long)i]];
        popup.lastItem.tag = i;
    }
    popup.target = self;
    popup.action = @selector(editorChanged:);
    [popup.widthAnchor constraintEqualToConstant:68].active = YES;
    return popup;
}

- (NSBox *)hairline {
    NSBox *box = [[NSBox alloc] initWithFrame:NSZeroRect];
    box.boxType = NSBoxSeparator;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [box.heightAnchor constraintEqualToConstant:1].active = YES;
    return box;
}

- (NSTextField *)addMetric:(NSString *)name to:(NSStackView *)stack {
    NSTextField *nameLabel = [self label:name size:13 weight:NSFontWeightRegular color:[NSColor labelColor]];
    nameLabel.maximumNumberOfLines = 1;
    [nameLabel setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSTextField *value = [self label:@"读取中" size:13 weight:NSFontWeightMedium color:[NSColor labelColor]];
    value.alignment = NSTextAlignmentRight;
    value.maximumNumberOfLines = 2;
    [value setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *row = [NSStackView stackViewWithViews:@[nameLabel, value]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 12;
    [stack addArrangedSubview:row];
    [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    return value;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.backgroundLaunch = [[NSProcessInfo processInfo].arguments containsObject:@"--background"];
    [self buildStatusItem];
    [self buildWindow];
    [self loadRows];
    [self.table reloadData];
    if (self.rows.count > 0) [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self refreshStatus];
    [self refreshHardware];
    [self applyChargeLimitShowingResult:NO];
    if (!self.backgroundLaunch) [self registerLoginIfInstalled];
    [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(timerFired) userInfo:nil repeats:YES];
    MBCCheckForUpdate(MBCVersionString(), ^(NSString *message, NSString *url, BOOL newer) {
        if (url.length) self.updateURL = url;
        if (self.versionLabel) self.versionLabel.stringValue = [NSString stringWithFormat:@"版本 %@　%@", MBCVersionString(), message];
        if (newer) self.pendingUpdate = message;
        [self offerPendingUpdate];
    });
    if (!self.backgroundLaunch) [self presentFront];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

- (void)buildStatusItem {
    self.status = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.status.autosaveName = @"com.macbatterycharge.status";
    self.status.button.imagePosition = NSImageOnly;
    self.status.button.target = self;
    self.status.button.action = @selector(statusClicked:);
    self.status.button.toolTip = MBCScreenHasNotch()
        ? @"上下两行显示。这台屏幕有刘海，按住 Command 可以把图标拖到刘海两侧，位置会记住。"
        : @"上下两行显示。按住 Command 可以拖动图标，位置会记住。";
    [self setMenuBarTop:@"--" bottom:@"读取"];
}

// 菜单栏按钮不保证换行。把电池图标和两行字画进同一张模板图，上排才真的在上边。
- (void)setMenuBarTop:(NSString *)top bottom:(NSString *)bottom {
    NSString *line1 = top.length ? top : @"--";
    NSString *line2 = bottom.length ? bottom : @"";
    NSDictionary *topAttr = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:8 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor blackColor],
    };
    NSDictionary *bottomAttr = @{
        NSFontAttributeName: [NSFont systemFontOfSize:8 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor blackColor],
    };
    CGFloat textWidth = MAX([line1 sizeWithAttributes:topAttr].width, [line2 sizeWithAttributes:bottomAttr].width);
    CGFloat width = ceil(20 + textWidth);
    NSImage *image = [NSImage imageWithSize:NSMakeSize(width, 18) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [[NSColor blackColor] set];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1, 4, 12, 9) xRadius:1.4 yRadius:1.4] stroke];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(4.5, 13, 5, 1.8) xRadius:0.5 yRadius:0.5] fill];
        [[NSBezierPath bezierPathWithRect:NSMakeRect(3, 6, 6, 5)] fill];
        [line1 drawAtPoint:NSMakePoint(18, 8) withAttributes:topAttr];
        [line2 drawAtPoint:NSMakePoint(18, 0) withAttributes:bottomAttr];
        return YES;
    }];
    image.template = YES;
    self.status.button.image = image;
    self.status.button.title = @"";
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 420, 740);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                    styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    window.title = @"充电上限";
    window.minSize = NSMakeSize(400, 560);
    window.delegate = self;
    self.window = window;

    self.guide = [[MBCGuideView alloc] initWithFrame:NSZeroRect];
    self.guide.translatesAutoresizingMaskIntoConstraints = NO;
    self.guide.hidden = YES;
    __weak typeof(self) weakSelf = self;
    self.guide.onFinished = ^{
        [weakSelf finishGuide];
    };
    [window.contentView addSubview:self.guide];

    self.mainScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.mainScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.mainScroll.hasVerticalScroller = YES;
    self.mainScroll.drawsBackground = NO;
    self.mainScroll.borderType = NSNoBorder;
    self.mainScroll.hidden = YES;

    NSView *doc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420, 980)];
    doc.translatesAutoresizingMaskIntoConstraints = NO;
    NSStackView *root = [NSStackView stackViewWithViews:@[]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 6;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [doc addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:doc.topAnchor constant:16],
        [root.leadingAnchor constraintEqualToAnchor:doc.leadingAnchor constant:16],
        [root.trailingAnchor constraintEqualToAnchor:doc.trailingAnchor constant:-16],
        [root.bottomAnchor constraintEqualToAnchor:doc.bottomAnchor constant:-16],
    ]];
    self.mainScroll.documentView = doc;
    [window.contentView addSubview:self.mainScroll];
    NSView *content = window.contentView;
    [NSLayoutConstraint activateConstraints:@[
        [self.guide.topAnchor constraintEqualToAnchor:content.topAnchor],
        [self.guide.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.guide.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [self.guide.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [self.mainScroll.topAnchor constraintEqualToAnchor:content.topAnchor],
        [self.mainScroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.mainScroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [self.mainScroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [doc.widthAnchor constraintEqualToAnchor:self.mainScroll.contentView.widthAnchor],
    ]];

    [root addArrangedSubview:[self label:@"充电上限" size:18 weight:NSFontWeightSemibold color:[NSColor labelColor]]];
    NSTextField *intro = [self label:@"上排看现在的电池和内存。下排改时间。06:00 停在 80%，21:00 放开到 100%。已经高于上限的电不会被放掉。" size:12 weight:NSFontWeightRegular color:[NSColor secondaryLabelColor]];
    [root addArrangedSubview:intro];
    [intro.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;

    [root addArrangedSubview:[self label:@"上排" size:13 weight:NSFontWeightSemibold color:[NSColor labelColor]]];
    self.chargeValue = [self addMetric:@"电量" to:root];
    self.flowValue = [self addMetric:@"状态" to:root];
    self.currentValue = [self addMetric:@"电流" to:root];
    self.healthValue = [self addMetric:@"健康" to:root];
    self.tempValue = [self addMetric:@"温度" to:root];
    self.memoryValue = [self addMetric:@"内存" to:root];
    self.powerValue = [self addMetric:@"电源" to:root];
    self.limitValue = [self addMetric:@"系统上限" to:root];
    self.targetValue = [self addMetric:@"这一段" to:root];
    self.lowValue = [self addMetric:@"低电量" to:root];
    self.lowHint = [self label:@"" size:12 weight:NSFontWeightRegular color:[NSColor secondaryLabelColor]];
    self.adviceLabel = [self label:@"" size:12 weight:NSFontWeightRegular color:[NSColor secondaryLabelColor]];
    [root addArrangedSubview:self.lowHint];
    [root addArrangedSubview:self.adviceLabel];
    [self.lowHint.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;
    [self.adviceLabel.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;

    NSBox *line = [self hairline];
    [root addArrangedSubview:line];
    [line.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;

    [root addArrangedSubview:[self label:@"下排" size:13 weight:NSFontWeightSemibold color:[NSColor labelColor]]];
    [root addArrangedSubview:[self label:@"结束早于开始表示跨过午夜。空档按 100%。时间段不能重叠。上限只有 80、85、90、95、100。" size:12 weight:NSFontWeightRegular color:[NSColor secondaryLabelColor]]];

    self.table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.table.headerView = [[NSTableHeaderView alloc] init];
    self.table.usesAlternatingRowBackgroundColors = YES;
    self.table.rowHeight = 22;
    self.table.dataSource = self;
    self.table.delegate = self;
    for (NSArray *spec in @[@[@"开始", @"start", @78], @[@"结束", @"end", @78], @[@"上限", @"limit", @64], @[@"低电量", @"lowPower", @88]]) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[1]];
        column.title = spec[0];
        column.width = [spec[2] doubleValue];
        column.editable = NO;
        [self.table addTableColumn:column];
    }
    NSScrollView *tableScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    tableScroll.documentView = self.table;
    tableScroll.hasVerticalScroller = YES;
    tableScroll.borderType = NSBezelBorder;
    tableScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [tableScroll.heightAnchor constraintEqualToConstant:132].active = YES;
    [root addArrangedSubview:tableScroll];
    [tableScroll.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;

    NSButton *add = [NSButton buttonWithTitle:@"添加" target:self action:@selector(addRow:)];
    NSButton *remove = [NSButton buttonWithTitle:@"删除" target:self action:@selector(removeRow:)];
    NSStackView *rowButtons = [NSStackView stackViewWithViews:@[add, remove]];
    rowButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    rowButtons.spacing = 8;
    [root addArrangedSubview:rowButtons];

    self.startHour = [self clockPopup:24];
    self.startMinute = [self clockPopup:60];
    self.endHour = [self clockPopup:24];
    self.endMinute = [self clockPopup:60];
    NSButton *startClock = [NSButton buttonWithTitle:@"表盘" target:self action:@selector(showClock:)];
    startClock.tag = 1;
    NSButton *endClock = [NSButton buttonWithTitle:@"表盘" target:self action:@selector(showClock:)];
    endClock.tag = 2;
    [root addArrangedSubview:[self editorLine:@"开始" hour:self.startHour minute:self.startMinute clock:startClock]];
    [root addArrangedSubview:[self editorLine:@"结束" hour:self.endHour minute:self.endMinute clock:endClock]];

    self.limitPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSNumber *limit in @[@80, @85, @90, @95, @100]) {
        [self.limitPopup addItemWithTitle:[NSString stringWithFormat:@"%@%%", limit]];
        self.limitPopup.lastItem.tag = limit.integerValue;
    }
    self.limitPopup.target = self;
    self.limitPopup.action = @selector(editorChanged:);
    NSStackView *limitRow = [NSStackView stackViewWithViews:@[
        [self label:@"上限" size:13 weight:NSFontWeightRegular color:[NSColor labelColor]],
        self.limitPopup,
    ]];
    limitRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    limitRow.spacing = 8;
    [root addArrangedSubview:limitRow];

    [root addArrangedSubview:[self label:@"这一段的低电量" size:13 weight:NSFontWeightSemibold color:[NSColor labelColor]]];
    self.lowOff = [NSButton radioButtonWithTitle:@"这段不用" target:self action:@selector(editorChanged:)];
    self.lowOn = [NSButton radioButtonWithTitle:@"这段一直开" target:self action:@selector(editorChanged:)];
    self.lowBattery = [NSButton radioButtonWithTitle:@"仅用电池时开" target:self action:@selector(editorChanged:)];
    self.lowOff.state = NSControlStateValueOn;
    NSStackView *radios = [NSStackView stackViewWithViews:@[self.lowOff, self.lowOn, self.lowBattery]];
    radios.orientation = NSUserInterfaceLayoutOrientationVertical;
    radios.alignment = NSLayoutAttributeLeading;
    radios.spacing = 4;
    [root addArrangedSubview:radios];
    [root addArrangedSubview:[self label:@"低电量只在点「立即应用」时写入。和系统一致就不会要密码。" size:12 weight:NSFontWeightRegular color:[NSColor secondaryLabelColor]]];

    self.loginCheck = [NSButton checkboxWithTitle:@"登录后藏在菜单栏" target:self action:@selector(loginChanged:)];
    self.loginCheck.state = NSControlStateValueOn;
    [root addArrangedSubview:self.loginCheck];
    self.versionLabel = [self label:[NSString stringWithFormat:@"版本 %@", MBCVersionString()] size:12 weight:NSFontWeightRegular color:[NSColor secondaryLabelColor]];
    self.resultLabel = [self label:@"还没有应用到系统。" size:12 weight:NSFontWeightRegular color:[NSColor secondaryLabelColor]];
    [root addArrangedSubview:self.versionLabel];
    [root addArrangedSubview:self.resultLabel];
    [self.resultLabel.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;

    NSButton *update = [NSButton buttonWithTitle:@"检查更新" target:self action:@selector(checkUpdate:)];
    NSButton *replay = [NSButton buttonWithTitle:@"再看引导" target:self action:@selector(replayGuide:)];
    NSButton *uninstall = [NSButton buttonWithTitle:@"卸载" target:self action:@selector(uninstall:)];
    NSButton *quit = [NSButton buttonWithTitle:@"退出" target:self action:@selector(terminate:)];
    NSStackView *actions = [NSStackView stackViewWithViews:@[update, replay, uninstall, quit]];
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.spacing = 8;
    [root addArrangedSubview:actions];
    NSButton *apply = [NSButton buttonWithTitle:@"立即应用" target:self action:@selector(applyClicked:)];
    apply.keyEquivalent = @"\r";
    [root addArrangedSubview:apply];
    [apply.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;

    [window center];
}

- (NSStackView *)editorLine:(NSString *)title hour:(NSPopUpButton *)hour minute:(NSPopUpButton *)minute clock:(NSButton *)clock {
    NSStackView *line = [NSStackView stackViewWithViews:@[
        [self label:title size:13 weight:NSFontWeightRegular color:[NSColor labelColor]],
        hour,
        [self label:@":" size:13 weight:NSFontWeightRegular color:[NSColor labelColor]],
        minute,
        clock,
    ]];
    line.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    line.spacing = 6;
    return line;
}

- (void)loadRows {
    NSDictionary *saved = MBCLoadSettings();
    self.guideSeen = [saved[@"guideSeen"] boolValue];
    NSArray *items = [saved[@"intervals"] isKindOfClass:[NSArray class]] ? saved[@"intervals"] : MBCDefaultIntervals();
    BOOL legacyAuto = [saved[@"lowPowerAuto"] boolValue];
    [self.rows removeAllObjects];
    for (id item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSMutableDictionary *row = [item mutableCopy];
        NSString *low = row[@"lowPower"];
        if (low == nil && legacyAuto) low = @"battery";
        row[@"lowPower"] = MBCNormalizeLowPower(low);
        [self.rows addObject:row];
    }
    if (self.rows.count == 0) {
        for (NSDictionary *item in MBCDefaultIntervals()) [self.rows addObject:[item mutableCopy]];
    }
    if (saved[@"launchAtLogin"]) self.loginCheck.state = [saved[@"launchAtLogin"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.rows.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSDictionary *item = self.rows[(NSUInteger)row];
    if ([column.identifier isEqualToString:@"limit"]) return [NSString stringWithFormat:@"%@%%", item[@"limit"]];
    if ([column.identifier isEqualToString:@"lowPower"]) return MBCLowPowerTitle(item[@"lowPower"]);
    return item[column.identifier] ?: @"";
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (self.suppressEditor) return;
    NSInteger row = self.table.selectedRow;
    if (row < 0 || row >= (NSInteger)self.rows.count) return;
    NSDictionary *item = self.rows[(NSUInteger)row];
    NSInteger hour = 0;
    NSInteger minute = 0;
    self.suppressEditor = YES;
    MBCSplitClock(item[@"start"], &hour, &minute);
    [self.startHour selectItemWithTag:hour];
    [self.startMinute selectItemWithTag:minute];
    MBCSplitClock(item[@"end"], &hour, &minute);
    [self.endHour selectItemWithTag:hour];
    [self.endMinute selectItemWithTag:minute];
    [self.limitPopup selectItemWithTag:[item[@"limit"] integerValue]];
    NSString *low = MBCNormalizeLowPower(item[@"lowPower"]);
    self.lowOff.state = [low isEqualToString:@"off"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.lowOn.state = [low isEqualToString:@"on"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.lowBattery.state = [low isEqualToString:@"battery"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.suppressEditor = NO;
}

- (void)editorChanged:(id)sender {
    if (self.suppressEditor) return;
    NSInteger row = self.table.selectedRow;
    if (row < 0 || row >= (NSInteger)self.rows.count) return;
    NSMutableDictionary *item = self.rows[(NSUInteger)row];
    item[@"start"] = [NSString stringWithFormat:@"%02ld:%02ld", (long)self.startHour.selectedTag, (long)self.startMinute.selectedTag];
    item[@"end"] = [NSString stringWithFormat:@"%02ld:%02ld", (long)self.endHour.selectedTag, (long)self.endMinute.selectedTag];
    item[@"limit"] = @(self.limitPopup.selectedTag);
    NSString *low = @"off";
    if (self.lowOn.state == NSControlStateValueOn) low = @"on";
    else if (self.lowBattery.state == NSControlStateValueOn) low = @"battery";
    item[@"lowPower"] = low;
    self.suppressEditor = YES;
    [self.table reloadData];
    [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    self.suppressEditor = NO;
    [self refreshStatus];
}

- (void)addRow:(id)sender {
    int coverage[1440];
    NSString *error = nil;
    if (!MBCCompileIntervals(self.rows, coverage, &error)) {
        self.resultLabel.stringValue = error ?: @"先把现有时间段改正确，再添加";
        NSBeep();
        return;
    }
    int start = -1;
    for (int minute = 0; minute < 1440; minute++) {
        if (coverage[minute] < 0) {
            start = minute;
            break;
        }
    }
    if (start < 0) {
        self.resultLabel.stringValue = @"一天已经被排满。先把某一段改短，再添加。";
        NSBeep();
        return;
    }
    int end = start + 1;
    while (end < 1440 && coverage[end] < 0 && end - start < 60) end++;
    int endMinute = end >= 1440 ? 0 : end;
    [self.rows addObject:[@{
        @"start": [NSString stringWithFormat:@"%02d:%02d", start / 60, start % 60],
        @"end": [NSString stringWithFormat:@"%02d:%02d", endMinute / 60, endMinute % 60],
        @"limit": @90,
        @"lowPower": @"off",
    } mutableCopy]];
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
    if (self.rows.count == 0) return;
    NSInteger next = MIN(row, (NSInteger)self.rows.count - 1);
    [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)next] byExtendingSelection:NO];
}

- (void)showClock:(id)sender {
    self.clockEditsStart = [sender tag] == 1;
    if (!self.clockPopover) {
        self.clockPicker = [[NSDatePicker alloc] initWithFrame:NSMakeRect(0, 0, 220, 180)];
        self.clockPicker.datePickerStyle = NSDatePickerStyleClockAndCalendar;
        self.clockPicker.datePickerElements = NSDatePickerElementFlagHourMinute;
        self.clockPicker.datePickerMode = NSDatePickerModeSingle;
        self.clockPicker.target = self;
        self.clockPicker.action = @selector(clockChanged:);
        NSViewController *controller = [[NSViewController alloc] init];
        controller.view = self.clockPicker;
        self.clockPopover = [[NSPopover alloc] init];
        self.clockPopover.contentViewController = controller;
        self.clockPopover.behavior = NSPopoverBehaviorTransient;
    }
    NSInteger hour = self.clockEditsStart ? self.startHour.selectedTag : self.endHour.selectedTag;
    NSInteger minute = self.clockEditsStart ? self.startMinute.selectedTag : self.endMinute.selectedTag;
    NSDateComponents *parts = [[NSDateComponents alloc] init];
    parts.year = 2020;
    parts.month = 1;
    parts.day = 1;
    parts.hour = hour;
    parts.minute = minute;
    self.clockPicker.dateValue = [[NSCalendar currentCalendar] dateFromComponents:parts] ?: [NSDate date];
    [self.clockPopover showRelativeToRect:[sender bounds] ofView:sender preferredEdge:NSRectEdgeMaxY];
}

- (void)clockChanged:(id)sender {
    NSDateComponents *parts = [[NSCalendar currentCalendar] components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:self.clockPicker.dateValue];
    self.suppressEditor = YES;
    if (self.clockEditsStart) {
        [self.startHour selectItemWithTag:parts.hour];
        [self.startMinute selectItemWithTag:parts.minute];
    } else {
        [self.endHour selectItemWithTag:parts.hour];
        [self.endMinute selectItemWithTag:parts.minute];
    }
    self.suppressEditor = NO;
    [self editorChanged:sender];
}

- (BOOL)persist:(NSString **)error {
    NSDictionary *settings = @{
        @"intervals": self.rows,
        @"launchAtLogin": @(self.loginCheck.state == NSControlStateValueOn),
        @"guideSeen": @(self.guideSeen),
    };
    return MBCSaveSettings(settings, error);
}

- (void)timerFired {
    [self refreshStatus];
    [self refreshHardware];
    [self applyChargeLimitShowingResult:NO];
}

- (void)refreshHardware {
    NSDictionary *battery = MBCReadBatteryReport();
    NSArray *lines = MBCBatteryDetailLines(battery);
    self.chargeValue.stringValue = @"—";
    self.flowValue.stringValue = MBCMenuBarBottom(battery);
    self.currentValue.stringValue = @"—";
    self.healthValue.stringValue = @"—";
    self.tempValue.stringValue = @"—";
    for (NSString *line in lines) {
        if ([line hasPrefix:@"电量 "]) self.chargeValue.stringValue = [line substringFromIndex:3];
        if ([line hasPrefix:@"电流 "]) self.currentValue.stringValue = [line substringFromIndex:3];
        if ([line hasPrefix:@"健康度约 "]) self.healthValue.stringValue = [line substringFromIndex:5];
        if ([line hasPrefix:@"电池温度 "]) self.tempValue.stringValue = [line substringFromIndex:5];
        if ([line hasPrefix:@"没有读到内置电池"]) {
            self.chargeValue.stringValue = @"没有内置电池";
            self.flowValue.stringValue = @"无电池";
        }
    }
    NSDictionary *memory = MBCReadMemoryReport();
    uint64_t total = [memory[@"totalBytes"] unsignedLongLongValue];
    if (total == 0) {
        self.memoryValue.stringValue = @"没有读到";
    } else {
        self.memoryValue.stringValue = [NSString stringWithFormat:@"%@ · 已用 %@ · %@",
                                         MBCFormatBytes(total),
                                         MBCFormatBytes([memory[@"usedBytes"] unsignedLongLongValue]),
                                         MBCMemoryPressureName([memory[@"pressure"] integerValue])];
    }
    self.adviceLabel.stringValue = [@[MBCBatteryAdvice(battery), MBCMemoryAdvice(memory, battery)] componentsJoinedByString:@"\n"];
    [self setMenuBarTop:[self menuBarTopFromTarget] bottom:MBCMenuBarBottom(battery)];
}

- (NSString *)menuBarTopFromTarget {
    NSString *error = nil;
    int coverage[1440];
    if (!MBCCompileIntervals(self.rows, coverage, &error)) return @"--";
    BOOL gap = NO;
    int want = MBCLimitAtMinute(coverage, MBCCurrentMinute(), &gap);
    return [NSString stringWithFormat:@"%d%%", want];
}

- (void)refreshStatus {
    BOOL ac = NO;
    NSString *error = nil;
    if (MBCReadPowerSource(&ac, &error)) self.powerValue.stringValue = ac ? @"接通电源" : @"使用电池";
    else self.powerValue.stringValue = @"读不到";

    NSInteger current = -1;
    if (!MBCChargeSupported(&error)) self.limitValue.stringValue = @"这台 Mac 不支持";
    else if (MBCChargeGetLimit(&current, &error)) self.limitValue.stringValue = [NSString stringWithFormat:@"%ld%%", (long)current];
    else self.limitValue.stringValue = error ?: @"读不到";

    NSString *wantMode = MBCLowPowerAtMinute(self.rows, MBCCurrentMinute());
    NSInteger wantBattery = 0;
    NSInteger wantAC = 0;
    MBCModesForLowPower(wantMode, &wantBattery, &wantAC);
    NSInteger battery = 0;
    NSInteger plugged = 0;
    if (MBCReadLowPowerModes(&battery, &plugged, NULL)) {
        self.lowValue.stringValue = [NSString stringWithFormat:@"电池%@ · 电源%@", battery ? @"开" : @"关", plugged ? @"开" : @"关"];
        if (battery != wantBattery || plugged != wantAC) self.lowHint.stringValue = @"和这一段不一样。点「立即应用」才会改，到点不会弹密码。";
        else self.lowHint.stringValue = [NSString stringWithFormat:@"和这一段一致：%@", MBCLowPowerTitle(wantMode)];
    } else {
        self.lowValue.stringValue = @"读不到";
        self.lowHint.stringValue = @"";
    }

    int coverage[1440];
    if (MBCCompileIntervals(self.rows, coverage, &error)) {
        BOOL gap = NO;
        int want = MBCLimitAtMinute(coverage, MBCCurrentMinute(), &gap);
        self.targetValue.stringValue = gap
            ? [NSString stringWithFormat:@"%d%% · 这段没单独设置", want]
            : [NSString stringWithFormat:@"%d%% · %@", want, MBCLowPowerTitle(wantMode)];
        [self setMenuBarTop:[NSString stringWithFormat:@"%d%%", want] bottom:self.flowValue.stringValue.length ? self.flowValue.stringValue : @"上限"];
    } else {
        self.targetValue.stringValue = error ?: @"时间段还不能用";
        [self setMenuBarTop:@"--" bottom:@"检查"];
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
    NSString *chargeText = self.resultLabel.stringValue ?: @"";
    NSInteger batteryMode = 0;
    NSInteger acMode = 0;
    MBCModesForLowPower(MBCLowPowerAtMinute(self.rows, MBCCurrentMinute()), &batteryMode, &acMode);
    if (!MBCApplyLowPowerModes(batteryMode, acMode, &error)) {
        self.resultLabel.stringValue = error ?: @"低电量模式没有改成";
        [self refreshStatus];
        return;
    }
    if (![self applyLogin:&error]) {
        self.resultLabel.stringValue = error ?: @"登录启动没有改成";
        [self refreshStatus];
        return;
    }
    if (chargeOK) self.resultLabel.stringValue = [chargeText stringByAppendingString:@" 低电量和登录启动已按窗口保存。"];
    else if (chargeText.length) self.resultLabel.stringValue = [chargeText stringByAppendingString:@" 低电量和登录启动已保存。"];
    [self refreshStatus];
}

- (BOOL)applyLogin:(NSString **)error {
    BOOL enabled = self.loginCheck.state == NSControlStateValueOn;
    if (!enabled) return MBCSetLaunchAtLogin(NO, MBCInstalledExecutable(), error);
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:MBCInstalledExecutable()]) {
        if (error) *error = @"请先安装到“应用程序”。从磁盘映像打开时不能登记登录启动。";
        return NO;
    }
    return MBCSetLaunchAtLogin(YES, MBCInstalledExecutable(), error);
}

- (void)registerLoginIfInstalled {
    if (self.loginCheck.state != NSControlStateValueOn) return;
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:MBCInstalledExecutable()]) {
        self.resultLabel.stringValue = @"从磁盘映像打开不会登录自启。装进“应用程序”后再打开一次。";
        return;
    }
    NSString *error = nil;
    if (![self applyLogin:&error]) self.resultLabel.stringValue = error ?: @"登录启动没有登记";
}

- (void)loginChanged:(id)sender {
    NSString *error = nil;
    if (![self applyLogin:&error]) self.resultLabel.stringValue = error ?: @"登录启动没有改成";
    [self persist:&error];
}

- (void)activateApp {
    if (@available(macOS 14.0, *)) [NSApp activate];
    else [NSApp activateIgnoringOtherApps:YES];
}

- (void)showGuide {
    [self.guide stopAnimation];
    self.mainScroll.hidden = YES;
    self.guide.hidden = NO;
    [self.guide startAnimation];
}

- (void)showMain {
    [self.guide stopAnimation];
    self.guide.hidden = YES;
    self.mainScroll.hidden = NO;
}

- (void)presentFront {
    if (self.guideSeen) [self showMain];
    else [self showGuide];
    [self activateApp];
    [self.window makeKeyAndOrderFront:nil];
    [self offerPendingUpdate];
}

- (void)finishGuide {
    self.guideSeen = YES;
    NSString *error = nil;
    [self persist:&error];
    [self showMain];
    [self offerPendingUpdate];
}

- (void)replayGuide:(id)sender {
    [self.guide reset];
    [self showGuide];
}

- (void)statusClicked:(id)sender {
    if (self.window.isVisible && self.window.isKeyWindow) {
        [self.guide stopAnimation];
        [self.window orderOut:nil];
        return;
    }
    [self presentFront];
}

- (void)windowWillClose:(NSNotification *)notification {
    [self.guide stopAnimation];
}

- (void)offerPendingUpdate {
    if (!self.window.isVisible || !self.guideSeen || self.pendingUpdate.length == 0 || self.updateOffered) return;
    self.updateOffered = YES;
    [self offerUpdate:self.pendingUpdate];
}

- (void)checkUpdate:(id)sender {
    self.versionLabel.stringValue = @"正在检查更新";
    MBCCheckForUpdate(MBCVersionString(), ^(NSString *message, NSString *url, BOOL newer) {
        if (url.length) self.updateURL = url;
        self.versionLabel.stringValue = [NSString stringWithFormat:@"版本 %@　%@", MBCVersionString(), message];
        if (newer) {
            self.pendingUpdate = message;
            self.updateOffered = NO;
            [self offerPendingUpdate];
        }
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
    MBCSetLaunchAtLogin(NO, MBCInstalledExecutable(), &error);
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
