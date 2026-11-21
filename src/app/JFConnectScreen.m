#import "JFScreens.h"
#import "JFServer.h"
#import "JFLog.h"

@implementation JFConnectScreen {
    UILabel *_status, *_code, *_help;
    UIView *_card;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = JFColorBackground();
        CGFloat W = frame.size.width;

        CAGradientLayer *glow = [CAGradientLayer layer];
        glow.frame = self.bounds;
        glow.colors = @[(id)[UIColor colorWithRed:0.67 green:0.36 blue:0.76 alpha:0.25].CGColor,
                        (id)[UIColor colorWithRed:0 green:0.64 blue:0.86 alpha:0.12].CGColor,
                        (id)[UIColor clearColor].CGColor];
        glow.startPoint = CGPointMake(0, 0);
        glow.endPoint = CGPointMake(0.8, 1);
        [self.layer addSublayer:glow];

        UILabel *logo = JFLabel(54, YES, JFColorText());
        logo.text = @"Jellyfin";
        logo.textAlignment = NSTextAlignmentCenter;
        logo.frame = CGRectMake(0, JFS(110), W, JFS(70));
        [self addSubview:logo];

        _status = JFLabel(22, NO, JFColorDim());
        _status.textAlignment = NSTextAlignmentCenter;
        _status.frame = CGRectMake(0, JFS(190), W, JFS(30));
        _status.text = @"Looking for your server…";
        [self addSubview:_status];

        _card = [[UIView alloc] initWithFrame:CGRectMake((W - JFS(560)) / 2, JFS(270), JFS(560), JFS(250))];
        _card.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        _card.layer.cornerRadius = JFS(14);
        _card.alpha = 0;
        [self addSubview:_card];

        UILabel *t = JFLabel(20, YES, JFColorDim());
        t.text = @"QUICK CONNECT CODE";
        t.textAlignment = NSTextAlignmentCenter;
        t.frame = CGRectMake(0, JFS(28), _card.bounds.size.width, JFS(26));
        [_card addSubview:t];

        _code = JFLabel(72, YES, JFColorText());
        _code.textAlignment = NSTextAlignmentCenter;
        _code.font = [UIFont fontWithName:@"AvenirNext-Bold" size:JFS(72)] ?: JFFont(72, YES);
        _code.frame = CGRectMake(0, JFS(64), _card.bounds.size.width, JFS(90));
        [_card addSubview:_code];

        _help = JFLabel(17, NO, JFColorDim());
        _help.numberOfLines = 2;
        _help.textAlignment = NSTextAlignmentCenter;
        _help.frame = CGRectMake(JFS(30), JFS(170), _card.bounds.size.width - JFS(60), JFS(56));
        _help.text = @"In Jellyfin on your phone or computer, open your profile → Quick Connect and enter this code.";
        [_card addSubview:_help];
    }
    return self;
}

- (void)screenDidAppear {
    [self start];
}

- (void)start {
    JFServer *srv = [JFServer shared];
    _status.text = @"Looking for your server…";
    [srv findServer:^(NSString *name) {
        if (!name) {
            self->_status.text = @"No Jellyfin server found on this network. Press Select to try again.";
            return;
        }
        if (srv.signedIn) { [self.nav replaceWithScreen:[[JFHomeScreen alloc] initWithFrame:self.bounds]]; return; }
        self->_status.text = [NSString stringWithFormat:@"Sign in to %@", name];
        [srv startQuickConnect:^(NSString *code, NSError *error) {
            if (error) { self->_status.text = @"Quick Connect is not available on this server."; return; }
            self->_code.text = code;
            [UIView animateWithDuration:0.4 animations:^{ self->_card.alpha = 1; }];
        } done:^(NSError *error) {
            if (error) { self->_status.text = @"Sign-in failed. Press Select to try again."; return; }
            [self.nav replaceWithScreen:[[JFHomeScreen alloc] initWithFrame:self.bounds]];
        }];
    }];
}

- (void)screenWillDisappear { [[JFServer shared] cancelQuickConnect]; }

- (void)key:(JFKey)k {
    if (k == JFKeySelect) { [[JFServer shared] cancelQuickConnect]; _card.alpha = 0; [self start]; }
}
@end
