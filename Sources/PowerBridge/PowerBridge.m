#import "PowerBridge.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

// 系统设置里的充电上限走 PowerUIAgent。这里按运行时方法调用，不把私有框架链进二进制。
// 每个方法先问 respondsToSelector:，较旧的系统没有这些方法时不会崩。

static id MBCClient(void) {
    static id client;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/Versions/A/PowerUI", RTLD_NOW);
        if (!handle) return;
        Class cls = NSClassFromString(@"PowerUISmartChargeClient");
        SEL initSel = sel_registerName("initWithClientName:");
        if (!cls || ![cls instancesRespondToSelector:initSel]) return;
        id created = [cls alloc];
        client = ((id (*)(id, SEL, id))objc_msgSend)(created, initSel, @"MacBatteryCharge");
    });
    return client;
}

static void setError(NSString * _Nullable * _Nullable error, NSString *text) {
    if (error) *error = text;
}

static NSString *errorText(NSError *error, NSString *fallback) {
    return error.localizedDescription.length ? error.localizedDescription : fallback;
}

static id MBCReadyClient(SEL selector, NSString * _Nullable * _Nullable error) {
    id client = MBCClient();
    if (!client) {
        setError(error, @"系统没有充电上限接口");
        return nil;
    }
    if (![client respondsToSelector:selector]) {
        setError(error, @"这个系统版本还没有充电上限，要 macOS 26.4 或更新");
        return nil;
    }
    return client;
}

BOOL MBCChargeSupported(NSString * _Nullable * _Nullable error) {
    SEL sel = sel_registerName("isMCLSupported");
    id client = MBCReadyClient(sel, error);
    if (!client) return NO;
    BOOL supported = ((BOOL (*)(id, SEL))objc_msgSend)(client, sel);
    if (!supported) setError(error, @"这台 Mac 不支持系统充电上限");
    return supported;
}

BOOL MBCChargeGetLimit(NSInteger *limit, NSString * _Nullable * _Nullable error) {
    SEL sel = sel_registerName("getMCLLimitWithError:");
    id client = MBCReadyClient(sel, error);
    if (!client) return NO;
    NSError *failure = nil;
    unsigned char value = ((unsigned char (*)(id, SEL, NSError **))objc_msgSend)(client, sel, &failure);
    if (failure) {
        setError(error, errorText(failure, @"读不到充电上限"));
        return NO;
    }
    *limit = value;
    return YES;
}

NSArray<NSNumber *> *MBCChargeAvailableLimits(NSString * _Nullable * _Nullable error) {
    SEL sel = sel_registerName("availableChargeLimitsWithError:");
    id client = MBCReadyClient(sel, error);
    if (!client) return nil;
    NSError *failure = nil;
    id choices = ((id (*)(id, SEL, NSError **))objc_msgSend)(client, sel, &failure);
    if (failure || ![choices isKindOfClass:[NSArray class]]) {
        setError(error, errorText(failure, @"读不到可选的充电上限"));
        return nil;
    }
    NSMutableArray<NSNumber *> *numbers = [NSMutableArray array];
    for (id choice in (NSArray *)choices) {
        if ([choice respondsToSelector:@selector(integerValue)]) [numbers addObject:@([choice integerValue])];
    }
    return numbers;
}

BOOL MBCChargeSetLimit(NSInteger limit, NSString * _Nullable * _Nullable error) {
    NSArray<NSNumber *> *choices = MBCChargeAvailableLimits(error);
    if (!choices) return NO;
    if (![choices containsObject:@(limit)]) {
        setError(error, @"系统不接受这个充电上限");
        return NO;
    }
    SEL sel = sel_registerName("setMCLLimit:error:");
    id client = MBCReadyClient(sel, error);
    if (!client) return NO;
    NSError *failure = nil;
    BOOL ok = ((BOOL (*)(id, SEL, unsigned char, NSError **))objc_msgSend)(client, sel, (unsigned char)limit, &failure);
    if (!ok || failure) {
        setError(error, errorText(failure, @"设置充电上限失败"));
        return NO;
    }
    return YES;
}
