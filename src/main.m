#import <Cocoa/Cocoa.h>
#import "AppController.h"

int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppController *controller = [AppController new];
        app.delegate = controller;
        [app run];
    }
    return 0;
}
