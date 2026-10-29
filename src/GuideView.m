#import "GuideView.h"

NSArray<NSString *> *MBCGuideStepTitles(void) {
    return @[
        @"放进“应用程序”",
        @"菜单栏上下两行",
        @"拖到刘海两侧",
        @"低电量的管理员密码",
        @"充电上限看机器",
        @"不会把电放掉",
    ];
}

NSArray<NSString *> *MBCGuideStepBodies(void) {
    return @[
        @"用 PKG 安装，或从磁盘映像拖进“应用程序”。放对位置后，下次登录才会自己出现在菜单栏。这一步不要密码。",
        @"没有程序坞图标。菜单栏上是电池图标，右边两行小字：上面是这一段的上限，下面是充电、放电或接通。点一下打开或关上窗口。",
        @"带刘海的 Mac 上，按住 Command 拖动图标，可以放到刘海左边或右边。松手后位置会记住。软件不能自己跳进刘海。",
        @"只有点「立即应用」，并且这一段的低电量和系统现在不一样，才会弹出系统的管理员密码框。密码不经过本软件。读电池、温度和内存不用密码。到了 06:00 或 21:00 也不会突然弹窗。",
        @"Apple 芯片并且系统支持时，上限会写成 80、85、90、95 或 100。Intel、台式机或较旧系统会写明不支持，窗口和内存读数仍然可用。",
        @"早上如果已经高于 80%，电量停在那里，不会为了降到 80% 去放电。23:30 断电不是软件的动作。上限保持 100% 时，充电宝还能继续充。",
    ];
}

static CGFloat easeInOut(CGFloat value) {
    if (value < 0) value = 0;
    if (value > 1) value = 1;
    return value * value * (3.0 - 2.0 * value);
}

@interface MBCGuideStage : NSView
@property (nonatomic, assign) NSInteger step;
@property (nonatomic, assign) CGFloat phase;
@end

@implementation MBCGuideStage

- (BOOL)isFlipped {
    return YES;
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self setNeedsDisplay:YES];
}

- (NSDictionary *)captionAttributes {
    return @{
        NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
    };
}

- (void)drawCaption:(NSString *)text at:(NSPoint)origin {
    [text drawAtPoint:origin withAttributes:[self captionAttributes]];
}

- (void)drawGlyphAt:(NSPoint)origin size:(CGFloat)side {
    NSRect rect = NSMakeRect(origin.x, origin.y, side, side);
    [[NSColor textBackgroundColor] setFill];
    NSBezierPath *box = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:side * 0.22 yRadius:side * 0.22];
    [box fill];
    [[NSColor labelColor] setStroke];
    box.lineWidth = 1.2;
    [box stroke];
    NSRect cell = NSMakeRect(origin.x + side * 0.26, origin.y + side * 0.34, side * 0.42, side * 0.30);
    NSBezierPath *battery = [NSBezierPath bezierPathWithRoundedRect:cell xRadius:1.5 yRadius:1.5];
    battery.lineWidth = 1.1;
    [battery stroke];
    [[NSColor labelColor] setFill];
    [[NSBezierPath bezierPathWithRect:NSMakeRect(cell.origin.x + 2, cell.origin.y + 2, cell.size.width * 0.55, cell.size.height - 4)] fill];
    NSRect nub = NSMakeRect(NSMidX(cell) - 2, cell.origin.y - 2.5, 4, 2.5);
    [[NSBezierPath bezierPathWithRoundedRect:nub xRadius:0.6 yRadius:0.6] fill];
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;
    [[NSColor controlBackgroundColor] setFill];
    NSBezierPath *card = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 1, 1) xRadius:8 yRadius:8];
    [card fill];
    [[NSColor separatorColor] setStroke];
    card = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 1.5, 1.5) xRadius:8 yRadius:8];
    card.lineWidth = 1;
    [card stroke];
    switch (self.step) {
        case 0: [self drawInstall:bounds]; break;
        case 1: [self drawMenu:bounds]; break;
        case 2: [self drawNotch:bounds]; break;
        case 3: [self drawPassword:bounds]; break;
        case 4: [self drawLimit:bounds]; break;
        default: [self drawStay:bounds]; break;
    }
}

- (void)drawInstall:(NSRect)bounds {
    CGFloat width = bounds.size.width;
    NSRect folder = NSMakeRect(width - 150, 46, 112, 72);
    [[NSColor tertiaryLabelColor] setFill];
    NSRect tab = NSMakeRect(folder.origin.x + 10, 36, 40, 12);
    [[NSBezierPath bezierPathWithRoundedRect:tab xRadius:3 yRadius:3] fill];
    [[NSBezierPath bezierPathWithRoundedRect:folder xRadius:6 yRadius:6] fill];
    [self drawCaption:@"应用程序" at:NSMakePoint(folder.origin.x + 22, folder.origin.y + 28)];
    CGFloat travel = easeInOut(self.phase);
    CGFloat x = 28 + (folder.origin.x + 36 - 28) * travel;
    [self drawGlyphAt:NSMakePoint(x, 64) size:34];
}

- (void)drawMenu:(NSRect)bounds {
    CGFloat width = bounds.size.width;
    NSRect bar = NSMakeRect(16, 16, width - 32, 36);
    [[NSColor quaternaryLabelColor] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:bar xRadius:5 yRadius:5] fill];
    NSRect dock = NSMakeRect((width - 150) / 2.0, bounds.size.height - 42, 150, 24);
    [[NSBezierPath bezierPathWithRoundedRect:dock xRadius:8 yRadius:8] fill];
    CGFloat travel = easeInOut(self.phase);
    [self drawGlyphAt:NSMakePoint(NSMidX(dock) - 9, dock.origin.y + 3) size:18];
    CGFloat y = dock.origin.y + (22 - dock.origin.y) * travel;
    [self drawGlyphAt:NSMakePoint(bar.origin.x + 10, y) size:18];
    [self drawCaption:@"80%" at:NSMakePoint(bar.origin.x + 34, 18)];
    [self drawCaption:@"接通" at:NSMakePoint(bar.origin.x + 34, 32)];
}

- (void)drawNotch:(NSRect)bounds {
    CGFloat width = bounds.size.width;
    [[NSColor quaternaryLabelColor] setFill];
    NSRectFill(NSMakeRect(0, 18, width, 30));
    NSRect notch = NSMakeRect(width / 2.0 - 42, 10, 84, 26);
    [[NSColor controlBackgroundColor] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:notch xRadius:10 yRadius:10] fill];
    CGFloat x = (width / 2.0 - 16) + easeInOut(self.phase) * 86;
    [self drawGlyphAt:NSMakePoint(x, 22) size:18];
    [self drawCaption:@"按住 ⌘ 拖" at:NSMakePoint(20, bounds.size.height - 36)];
}

- (void)drawPassword:(NSRect)bounds {
    CGFloat appear = easeInOut(self.phase < 0.3 ? self.phase / 0.3 : 1);
    NSRect card = NSMakeRect(NSMidX(bounds) - 100, 40, 200, 86);
    NSColor *paper = [[NSColor windowBackgroundColor] colorWithAlphaComponent:appear];
    [paper setFill];
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:card xRadius:8 yRadius:8];
    [path fill];
    [[NSColor separatorColor] setStroke];
    path.lineWidth = 1;
    [path stroke];
    NSDictionary *title = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [[NSColor labelColor] colorWithAlphaComponent:appear],
    };
    [@"系统密码" drawAtPoint:NSMakePoint(card.origin.x + 16, card.origin.y + 16) withAttributes:title];
    NSRect button = NSMakeRect(card.origin.x + 16, card.origin.y + 48, 72, 22);
    [[[NSColor controlAccentColor] colorWithAlphaComponent:appear] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:button xRadius:5 yRadius:5] fill];
    NSDictionary *buttonText = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [[NSColor whiteColor] colorWithAlphaComponent:appear],
    };
    [@"允许" drawAtPoint:NSMakePoint(button.origin.x + 22, button.origin.y + 3) withAttributes:buttonText];
}

- (void)drawLimit:(NSRect)bounds {
    NSString *limit = self.phase < 0.5 ? @"80%" : @"100%";
    NSDictionary *big = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:40 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor labelColor],
    };
    NSSize size = [limit sizeWithAttributes:big];
    [limit drawAtPoint:NSMakePoint(NSMidX(bounds) - size.width / 2.0, 48) withAttributes:big];
    [self drawCaption:@"只有支持的 Mac 会写上" at:NSMakePoint(NSMidX(bounds) - 70, 100)];
}

- (void)drawStay:(NSRect)bounds {
    NSRect body = NSMakeRect(NSMidX(bounds) - 34, 28, 68, 96);
    NSRect cap = NSMakeRect(NSMidX(body) - 12, 20, 24, 8);
    [[NSColor labelColor] setStroke];
    NSBezierPath *capPath = [NSBezierPath bezierPathWithRoundedRect:cap xRadius:2 yRadius:2];
    capPath.lineWidth = 1.4;
    [capPath stroke];
    NSBezierPath *shell = [NSBezierPath bezierPathWithRoundedRect:body xRadius:6 yRadius:6];
    shell.lineWidth = 1.8;
    [shell stroke];
    NSRect inner = NSInsetRect(body, 6, 6);
    CGFloat fillHeight = inner.size.height * 0.90;
    NSRect fill = NSMakeRect(inner.origin.x, NSMaxY(inner) - fillHeight, inner.size.width, fillHeight);
    [[[NSColor labelColor] colorWithAlphaComponent:0.82] setFill];
    [[NSBezierPath bezierPathWithRect:fill] fill];
    CGFloat ceiling = NSMaxY(inner) - inner.size.height * 0.80;
    [[NSColor controlAccentColor] setStroke];
    [NSBezierPath strokeLineFromPoint:NSMakePoint(inner.origin.x - 10, ceiling) toPoint:NSMakePoint(NSMaxX(inner) + 8, ceiling)];
    [self drawCaption:@"80% 停住，不往下放" at:NSMakePoint(NSMidX(bounds) - 62, bounds.size.height - 28)];
}

@end

@interface MBCGuideView ()
@property (nonatomic, strong) MBCGuideStage *stage;
@property (nonatomic, strong) NSTextField *stepTitle;
@property (nonatomic, strong) NSTextField *stepBody;
@property (nonatomic, strong) NSTextField *progressLabel;
@property (nonatomic, strong) NSButton *backButton;
@property (nonatomic, strong) NSButton *nextButton;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) NSInteger step;
@property (nonatomic, assign) CGFloat phase;
@end

@implementation MBCGuideView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) [self build];
    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

- (NSTextField *)wrappingLabel:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight {
    NSTextField *field = [NSTextField labelWithString:text];
    field.font = [NSFont systemFontOfSize:size weight:weight];
    field.textColor = weight == NSFontWeightRegular ? [NSColor secondaryLabelColor] : [NSColor labelColor];
    field.maximumNumberOfLines = 0;
    field.lineBreakMode = NSLineBreakByWordWrapping;
    field.preferredMaxLayoutWidth = 360;
    return field;
}

- (void)build {
    NSStackView *root = [NSStackView stackViewWithViews:@[]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 10;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:self.topAnchor constant:18],
        [root.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18],
        [root.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-18],
    ]];

    [root addArrangedSubview:[self wrappingLabel:@"开始使用" size:20 weight:NSFontWeightSemibold]];
    NSTextField *intro = [self wrappingLabel:@"先看完这几步。读电池和内存不用授权。唯一的密码框，是改低电量时系统自己弹出来的。" size:12 weight:NSFontWeightRegular];
    [root addArrangedSubview:intro];
    [intro.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;

    self.stage = [[MBCGuideStage alloc] initWithFrame:NSZeroRect];
    self.stage.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stage.heightAnchor constraintEqualToConstant:168].active = YES;
    [root addArrangedSubview:self.stage];
    [self.stage.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;

    self.stepTitle = [self wrappingLabel:MBCGuideStepTitles().firstObject size:15 weight:NSFontWeightSemibold];
    self.stepBody = [self wrappingLabel:MBCGuideStepBodies().firstObject size:13 weight:NSFontWeightRegular];
    self.progressLabel = [self wrappingLabel:@"1 / 6" size:12 weight:NSFontWeightRegular];
    [root addArrangedSubview:self.stepTitle];
    [root addArrangedSubview:self.stepBody];
    [self.stepBody.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;
    [root addArrangedSubview:self.progressLabel];

    self.backButton = [NSButton buttonWithTitle:@"上一步" target:self action:@selector(goBack:)];
    self.nextButton = [NSButton buttonWithTitle:@"下一步" target:self action:@selector(goForward:)];
    NSButton *skip = [NSButton buttonWithTitle:@"跳过" target:self action:@selector(skip:)];
    NSStackView *buttons = [NSStackView stackViewWithViews:@[self.backButton, skip, self.nextButton]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.spacing = 8;
    [root addArrangedSubview:buttons];
    [self refreshCopy];
}

- (void)refreshCopy {
    NSArray *titles = MBCGuideStepTitles();
    NSArray *bodies = MBCGuideStepBodies();
    if (self.step < 0) self.step = 0;
    if (self.step >= (NSInteger)titles.count) self.step = (NSInteger)titles.count - 1;
    self.stepTitle.stringValue = titles[(NSUInteger)self.step];
    self.stepBody.stringValue = bodies[(NSUInteger)self.step];
    self.progressLabel.stringValue = [NSString stringWithFormat:@"%ld / %ld", (long)self.step + 1, (long)titles.count];
    self.backButton.enabled = self.step > 0;
    self.nextButton.title = self.step + 1 >= (NSInteger)titles.count ? @"开始使用" : @"下一步";
    self.stage.step = self.step;
    self.stage.phase = self.phase;
    [self.stage setNeedsDisplay:YES];
}

- (void)reset {
    self.step = 0;
    self.phase = 0;
    [self refreshCopy];
}

- (void)startAnimation {
    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
}

- (void)stopAnimation {
    [self.timer invalidate];
    self.timer = nil;
}

- (void)tick:(NSTimer *)timer {
    self.phase += 1.0 / 30.0 / 2.8;
    if (self.phase >= 1) self.phase -= 1;
    self.stage.phase = self.phase;
    [self.stage setNeedsDisplay:YES];
}

- (void)goBack:(id)sender {
    if (self.step == 0) return;
    self.step -= 1;
    self.phase = 0;
    [self refreshCopy];
}

- (void)goForward:(id)sender {
    if (self.step + 1 >= (NSInteger)MBCGuideStepTitles().count) {
        if (self.onFinished) self.onFinished();
        return;
    }
    self.step += 1;
    self.phase = 0;
    [self refreshCopy];
}

- (void)skip:(id)sender {
    if (self.onFinished) self.onFinished();
}

@end
