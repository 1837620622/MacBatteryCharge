#import <Cocoa/Cocoa.h>

FOUNDATION_EXPORT NSArray<NSString *> *MBCGuideStepTitles(void);
FOUNDATION_EXPORT NSArray<NSString *> *MBCGuideStepBodies(void);

// 第一次打开时的上下排列引导。动画画在本视图里，不播视频。
@interface MBCGuideView : NSView
@property (nonatomic, copy) void (^onFinished)(void);
- (void)reset;
- (void)startAnimation;
- (void)stopAnimation;
@end
