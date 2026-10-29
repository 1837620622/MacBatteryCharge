#import "ChargeClient.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

// 系统设置里的充电上限走 PowerUIAgent。这里按运行时方法调用，不把私有框架链进二进制。
// 本机已核对：isMCLSupported、getMCLLimitWithError:、availableChargeLimitsWithError:、setMCLLimit:error:。

static id MBCClient(void) {
    static id client;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/Versions/A/PowerUI", RTLD_NOW);
        if (!handle) return;
        Class cls = NSClassFromString(@"PowerUISmartChargeClient");
        if (!cls) return;
        id created = [cls alloc];
        SEL initSel = sel_registerName("initWithClientName:");
        client = ((id (*)(id, SEL, id))objc_msgSend)(created, initSel, @"MacBatteryCharge");
    });
    return client;
}

static NSString *errorText(NSError *error, NSString *fallback) {
    return error.localizedDescription.length ? error.localizedDescription : fallback;
}

BOOL MBCChargeSupported(NSString **error) {
    id client = MBCClient();
    if (!client) {
        if (error) *error = @"系统没有充电上限接口";
        return NO;
    }
    BOOL supported = ((BOOL (*)(id, SEL))objc_msgSend)(client, sel_registerName("isMCLSupported"));
    if (!supported && error) *error = @"这台 Mac 不支持系统充电上限";
    return supported;
}

BOOL MBCChargeGetLimit(NSInteger *limit, NSString **error) {
    id client = MBCClient();
    if (!client) {
        if (error) *error = @"系统没有充电上限接口";
        return NO;
    }
    NSError *failure = nil;
    unsigned char value = ((unsigned char (*)(id, SEL, NSError **))objc_msgSend)(client, sel_registerName("getMCLLimitWithError:"), &failure);
    if (failure) {
        if (error) *error = errorText(failure, @"读不到充电上限");
        return NO;
    }
    if (limit) *limit = value;
    return YES;
}

BOOL MBCChargeSetLimit(NSInteger limit, NSString **error) {
    id client = MBCClient();
    if (!client) {
        if (error) *error = @"系统没有充电上限接口";
        return NO;
    }
    NSError *failure = nil;
    NSArray *choices = ((id (*)(id, SEL, NSError **))objc_msgSend)(client, sel_registerName("availableChargeLimitsWithError:"), &failure);
    if (failure || ![choices isKindOfClass:[NSArray class]]) {
        if (error) *error = errorText(failure, @"读不到可选的充电上限");
        return NO;
    }
    BOOL allowed = NO;
    for (id choice in choices) {
        if ([choice integerValue] == limit) allowed = YES;
    }
    if (!allowed) {
        if (error) *error = @"系统不接受这个充电上限";
        return NO;
    }
    failure = nil;
    BOOL ok = ((BOOL (*)(id, SEL, unsigned char, NSError **))objc_msgSend)(client, sel_registerName("setMCLLimit:error:"), (unsigned char)limit, &failure);
    if (!ok || failure) {
        if (error) *error = errorText(failure, @"设置充电上限失败");
        return NO;
    }
    return YES;
}
