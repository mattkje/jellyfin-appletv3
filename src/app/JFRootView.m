// JFRootView -- hosts the screen stack and routes the remote.
//
//   Menu        back one screen; on the first screen it leaves the app
//   hold Menu   leaves the app from anywhere
//   arrows      repeat while held
#import "JFRootView.h"
#import "JFScreens.h"
#import "JFLog.h"

@interface JFRootView () <JFNavigator>
@end

@implementation JFRootView {
    NSMutableArray *_stack;
    NSTimer *_repeat;
    JFKey _held;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        jf_scale = frame.size.height / 720.0;
        // BackRow's root layer has Mac-style geometry (y up), so UIKit layout
        // hung under it shows upside down on the TV.  Flipping here once puts
        // the whole app back.  (renderInContext screenshots ignore BackRow's
        // flip, so `make shot` flips the capture back.)
        self.layer.geometryFlipped = YES;
        self.backgroundColor = [UIColor colorWithRed:0.063 green:0.063 blue:0.063 alpha:1];
        self.clipsToBounds = YES;
        _stack = [NSMutableArray array];
        [self pushScreen:[[JFConnectScreen alloc] initWithFrame:self.bounds]];
    }
    return self;
}

- (JFScreen *)top { return _stack.lastObject; }

- (void)pushScreen:(JFScreen *)screen {
    JFScreen *prev = self.top;
    [prev screenWillDisappear];
    screen.nav = self;
    [_stack addObject:screen];
    screen.alpha = 0;
    [self addSubview:screen];
    [UIView animateWithDuration:0.25 animations:^{ screen.alpha = 1; } completion:^(BOOL f) { prev.hidden = YES; }];
    [screen screenDidAppear];
    jf_log(@"screen: %@", NSStringFromClass([screen class]));
}

- (void)popScreen {
    if (_stack.count < 2) { [self exitApp]; return; }
    JFScreen *gone = self.top;
    [gone screenWillDisappear];
    [_stack removeLastObject];
    JFScreen *back = self.top;
    back.hidden = NO;
    [UIView animateWithDuration:0.2 animations:^{ gone.alpha = 0; } completion:^(BOOL f) { [gone removeFromSuperview]; }];
    [back screenDidAppear];
}

- (void)replaceWithScreen:(JFScreen *)screen {
    NSArray *old = [_stack copy];
    for (JFScreen *s in old) [s screenWillDisappear];
    [_stack removeAllObjects];
    screen.nav = self;
    [_stack addObject:screen];
    screen.alpha = 0;
    [self addSubview:screen];
    [UIView animateWithDuration:0.35 animations:^{ screen.alpha = 1; }
                     completion:^(BOOL f) { for (UIView *v in old) [v removeFromSuperview]; }];
    [screen screenDidAppear];
    jf_log(@"screen: %@", NSStringFromClass([screen class]));
}

- (void)exitApp {
    for (JFScreen *s in [_stack reverseObjectEnumerator]) [s screenWillDisappear];
    if (self.onExit) self.onExit();
}

// ---- from the appliance -------------------------------------------------------------------

- (void)didAppear {}

- (void)willDisappear {
    [_repeat invalidate];
    _repeat = nil;
}

- (void)repeatTick:(NSTimer *)t { [self.top arrow:_held]; }

- (void)arrow:(JFKey)k pressed:(BOOL)pressed {
    [_repeat invalidate];
    _repeat = nil;
    if (!pressed) return;
    _held = k;
    [self.top arrow:k];
    _repeat = [NSTimer scheduledTimerWithTimeInterval:0.11 target:self selector:@selector(repeatTick:) userInfo:nil repeats:YES];
    _repeat.fireDate = [NSDate dateWithTimeIntervalSinceNow:0.42];
}

- (void)key:(JFKey)k {
    if (k == JFKeyMenuHold) { [self exitApp]; return; }
    if (k == JFKeyMenu && ![self.top handlesMenu]) { [self popScreen]; return; }
    [self.top key:k];
}
@end
