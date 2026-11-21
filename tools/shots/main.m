// Screenshot tool: runs the app's real UI code in the iOS Simulator against a
// Jellyfin server (the public demo by default), follows a list of steps and
// writes 1280x720 PNGs.  See `make screenshots`.
//
// JF_STEPS (environment), separated by ';':
//   server URL          use this server
//   login USER [PASS]   sign in with a password
//   open                show the app (Connect screen, then Home when signed in)
//   wait SECONDS        let requests and images arrive
//   key up|down|left|right|select|play|menu ...
//   shot NAME           write NAME.png to JF_OUT
//   quit
#import <UIKit/UIKit.h>
#import "JFRootView.h"
#import "JFServer.h"

// iOS 13+ simulators require the scene lifecycle: ShotsApp only starts it,
// ShotsScene owns the window and runs the steps.
@interface ShotsApp : UIResponder <UIApplicationDelegate>
@end
@implementation ShotsApp
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts { return YES; }
@end

@interface ShotsScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) JFRootView *root;
@property (nonatomic, strong) NSMutableArray *steps;
@end

@implementation ShotsScene

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)opts {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [[UIViewController alloc] init];
    self.window.backgroundColor = [UIColor blackColor];
    [self.window makeKeyAndVisible];
    NSString *env = [NSProcessInfo processInfo].environment[@"JF_STEPS"] ?: @"";
    self.steps = [[env componentsSeparatedByString:@";"] mutableCopy];
    [self next];
}

- (void)next {
    while (self.steps.count) {
        NSString *step = [self.steps.firstObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [self.steps removeObjectAtIndex:0];
        if (!step.length) continue;
        NSArray *w = [step componentsSeparatedByString:@" "];
        NSString *cmd = w[0];
        NSLog(@"[shots] %@", step);
        if ([cmd isEqualToString:@"server"]) {
            [[JFServer shared] useAddress:w[1]];
        } else if ([cmd isEqualToString:@"login"]) {
            [[JFServer shared] signInWithUser:w[1] password:w.count > 2 ? w[2] : @"" done:^(NSError *e) {
                if (e) NSLog(@"[shots] login failed: %@", e);
                [self next];
            }];
            return;
        } else if ([cmd isEqualToString:@"open"]) {
            [self.root removeFromSuperview];
            // Off to the side of the device screen: the capture renders the
            // view itself, at the Apple TV's 1280x720.
            self.root = [[JFRootView alloc] initWithFrame:CGRectMake(0, 0, 1280, 720)];
            [self.window.rootViewController.view addSubview:self.root];
            [self.root didAppear];
        } else if ([cmd isEqualToString:@"wait"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([w[1] doubleValue] * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [self next]; });
            return;
        } else if ([cmd isEqualToString:@"key"]) {
            NSDictionary *keys = @{@"up": @(JFKeyUp), @"down": @(JFKeyDown), @"left": @(JFKeyLeft), @"right": @(JFKeyRight),
                                   @"select": @(JFKeySelect), @"play": @(JFKeyPlayPause), @"menu": @(JFKeyMenu)};
            for (NSString *name in [w subarrayWithRange:NSMakeRange(1, w.count - 1)]) {
                JFKey k = (JFKey)[keys[name] intValue];
                if (k <= JFKeyRight) { [self.root arrow:k pressed:YES]; [self.root arrow:k pressed:NO]; }
                else [self.root key:k];
            }
        } else if ([cmd isEqualToString:@"shot"]) {
            UIGraphicsBeginImageContextWithOptions(self.root.bounds.size, YES, 1);
            [self.root.layer renderInContext:UIGraphicsGetCurrentContext()];
            UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            NSString *dir = [NSProcessInfo processInfo].environment[@"JF_OUT"] ?: NSTemporaryDirectory();
            NSString *path = [[dir stringByAppendingPathComponent:w[1]] stringByAppendingPathExtension:@"png"];
            [UIImagePNGRepresentation(img) writeToFile:path atomically:YES];
            NSLog(@"[shots] wrote %@", path);
        } else if ([cmd isEqualToString:@"quit"]) {
            exit(0);
        }
    }
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass([ShotsApp class])); }
}

// JFLog for the simulator build (the device one writes to /var/mobile/Media).
void jf_log(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSLog(@"[Jellyfin] %@", [[NSString alloc] initWithFormat:fmt arguments:ap]);
    va_end(ap);
}
