#import "UpdateCheck.h"

static BOOL parseVersion(NSString *text, int out[3]) {
    if (![text isKindOfClass:[NSString class]]) return NO;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return NO;
    unichar first = [trimmed characterAtIndex:0];
    if (first == 'v' || first == 'V') trimmed = [trimmed substringFromIndex:1];
    NSArray *parts = [trimmed componentsSeparatedByString:@"."];
    if (parts.count == 0 || parts.count > 3) return NO;
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    for (NSInteger i = 0; i < 3; i++) {
        if (i >= (NSInteger)parts.count) {
            out[i] = 0;
            continue;
        }
        NSString *part = parts[(NSUInteger)i];
        if (part.length == 0 || [part rangeOfCharacterFromSet:[digits invertedSet]].location != NSNotFound) return NO;
        out[i] = part.intValue;
    }
    return YES;
}

BOOL MBCVersionIsNewer(NSString *latest, NSString *current) {
    int left[3] = {0, 0, 0};
    int right[3] = {0, 0, 0};
    if (!parseVersion(latest, left) || !parseVersion(current, right)) return NO;
    for (int i = 0; i < 3; i++) {
        if (left[i] > right[i]) return YES;
        if (left[i] < right[i]) return NO;
    }
    return NO;
}

void MBCCheckForUpdate(NSString *current, void (^completion)(NSString *message, NSString *url, BOOL newer)) {
    NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/1837620622/MacBatteryCharge/releases/latest"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 15;
    [request setValue:@"MacBatteryCharge" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *message = @"暂时连不上 GitHub，更新没检查成";
        NSString *page = @"https://github.com/1837620622/MacBatteryCharge/releases/latest";
        BOOL newer = NO;
        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        if (data && http.statusCode == 200) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *tag = [json isKindOfClass:[NSDictionary class]] ? json[@"tag_name"] : nil;
            NSString *html = [json isKindOfClass:[NSDictionary class]] ? json[@"html_url"] : nil;
            if (html.length) page = html;
            if (MBCVersionIsNewer(tag, current)) {
                newer = YES;
                message = [NSString stringWithFormat:@"有新版本 %@", tag];
            } else if (tag.length) {
                message = [NSString stringWithFormat:@"已是最新 %@", tag];
            }
        } else if (http.statusCode == 404) {
            message = @"还没有可更新的发布";
        }
        if (error && !data) message = @"暂时连不上 GitHub，更新没检查成";
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(message, page, newer);
        });
    }] resume];
}
