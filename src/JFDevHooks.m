// JFDevHooks.m -- development commands sent over USB.
//
// The Apple TV cannot show HDMI while it is attached to a Mac, and rebooting it
// with USB attached leaves it in Recovery Mode.  So the Mac drives the app
// through a file in the media folder that plain AFC can write:
//
//   /var/mobile/Media/jf_cmd.txt  "shot"    -> /var/mobile/Media/jf_shot.png
//                                 "reload"  -> AppleTV.app exits; backboardd
//                                              relaunches it with the new build
//                                 "open"    -> opens Jellyfin as from the menu
//                                 "key up select ..." -> remote presses
//
// The file is deleted once handled.  Polled once a second on the main queue.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "JFRootView.h"

extern JFRootView *jf_current_root;   // JFAppliance.m: the open app view, if any

#define JF_CMD  @"/var/mobile/Media/jf_cmd.txt"
#define JF_SHOT @"/var/mobile/Media/jf_shot.png"

@interface NSObject (JFDevBackRow)
+ (CALayer *)rootLayer;
+ (CGRect)interfaceFrame;
@end

static UIImage *jf_screen_image(void) {
    Class win = objc_getClass("BRWindow");
    CALayer *root = [win rootLayer];
    if (!root) return nil;
    CGRect r = [win interfaceFrame];
    UIGraphicsBeginImageContextWithOptions(r.size, YES, 1);
    [root renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

// jf_auto_0.png ... jf_auto_9.png, oldest overwritten; jf_auto_last.txt holds
// the number of the newest.
void jf_autoshot(void) {
    static int n = 0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
        int i = n++ % 10;
        NSString *p = [NSString stringWithFormat:@"/var/mobile/Media/jf_auto_%d.png", i];
        [UIImagePNGRepresentation(jf_screen_image()) writeToFile:p atomically:YES];
        [[NSString stringWithFormat:@"%d\n", i] writeToFile:@"/var/mobile/Media/jf_auto_last.txt"
                                                    atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    });
}

static void jf_poll(void) {
    NSString *cmd = [NSString stringWithContentsOfFile:JF_CMD encoding:NSUTF8StringEncoding error:NULL];
    cmd = [cmd stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (cmd.length) {                       // empty: still being written over USB, next poll
        [[NSFileManager defaultManager] removeItemAtPath:JF_CMD error:NULL];
        NSLog(@"[Jellyfin] dev command: %@", cmd);
        if ([cmd isEqualToString:@"shot"]) {
            NSData *png = UIImagePNGRepresentation(jf_screen_image());
            [png writeToFile:JF_SHOT atomically:YES];
        } else if ([cmd isEqualToString:@"reload"]) {
            exit(0);
        } else if ([cmd isEqualToString:@"open"]) {
            // Open Jellyfin as if chosen from the main menu.
            id mgr = [objc_getClass("BRApplicationStackManager") performSelector:@selector(singleton)];
            id ctl = [[[objc_getClass("JFController") alloc] init] autorelease];
            if (mgr && ctl) [[mgr performSelector:@selector(stack)] performSelector:@selector(pushController:) withObject:ctl];
        } else if ([cmd hasPrefix:@"key "]) {
            // Remote presses for testing: key up|down|left|right|select|play|menu.
            NSDictionary *keys = @{@"up": @(JFKeyUp), @"down": @(JFKeyDown), @"left": @(JFKeyLeft), @"right": @(JFKeyRight),
                                   @"select": @(JFKeySelect), @"play": @(JFKeyPlayPause), @"menu": @(JFKeyMenu)};
            for (NSString *name in [[cmd substringFromIndex:4] componentsSeparatedByString:@" "]) {
                NSNumber *k = keys[name];
                if (!k || !jf_current_root) continue;
                JFKey key = (JFKey)k.intValue;
                if (key <= JFKeyRight) { [jf_current_root arrow:key pressed:YES]; [jf_current_root arrow:key pressed:NO]; }
                else [jf_current_root key:key];
            }
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ jf_poll(); });
}

static __attribute__((constructor)) void jf_dev_start(void) {
    if (!objc_getClass("BRBaseAppliance")) return;   // only inside AppleTV.app
    dispatch_async(dispatch_get_main_queue(), ^{ jf_poll(); });
}
