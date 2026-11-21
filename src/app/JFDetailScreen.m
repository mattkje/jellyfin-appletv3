#import "JFScreens.h"
#import "JFRow.h"
#import "JFServer.h"

// Item details over its backdrop.  Movies and episodes get Play / Resume /
// From Start buttons; a series gets a seasons row and that season's episodes.
@implementation JFDetailScreen {
    NSDictionary *_item;
    JFImageView *_backdrop;
    UILabel *_kicker, *_title, *_meta, *_genres, *_overview;
    NSMutableArray *_buttons;          // UILabel pills; tag 0 play/resume, 1 from start
    NSInteger _button;
    JFRow *_seasons, *_episodes;
    NSInteger _zone;                    // 0 buttons, 1 seasons, 2 episodes
}

- (instancetype)initWithFrame:(CGRect)frame item:(NSDictionary *)item {
    if ((self = [super initWithFrame:frame])) {
        _item = item;
        self.backgroundColor = JFColorBackground();
        self.clipsToBounds = YES;
        CGFloat W = frame.size.width;

        _backdrop = [[JFImageView alloc] initWithFrame:self.bounds];
        _backdrop.alpha = 0;
        [self addSubview:_backdrop];
        CAGradientLayer *shade = [CAGradientLayer layer];
        shade.frame = self.bounds;
        shade.colors = @[(id)[JFColorBackground() colorWithAlphaComponent:0.96].CGColor,
                         (id)[JFColorBackground() colorWithAlphaComponent:0.7].CGColor,
                         (id)[JFColorBackground() colorWithAlphaComponent:0.25].CGColor];
        shade.startPoint = CGPointMake(0, 0.5);
        shade.endPoint = CGPointMake(1, 0.5);
        [self.layer addSublayer:shade];
        CAGradientLayer *bottom = [CAGradientLayer layer];
        bottom.frame = self.bounds;
        bottom.colors = @[(id)[UIColor clearColor].CGColor, (id)JFColorBackground().CGColor];
        bottom.locations = @[@0.45, @0.95];
        [self.layer addSublayer:bottom];

        _kicker = JFLabel(18, YES, JFColorAccent());
        _kicker.frame = CGRectMake(JFS(64), JFS(70), JFS(800), JFS(24));
        [self addSubview:_kicker];
        _title = JFLabel(46, YES, JFColorText());
        _title.frame = CGRectMake(JFS(64), JFS(96), W - JFS(128), JFS(58));
        _title.adjustsFontSizeToFitWidth = YES;
        _title.minimumScaleFactor = 0.6;
        [self addSubview:_title];
        _meta = JFLabel(18, NO, JFColorDim());
        _meta.frame = CGRectMake(JFS(64), JFS(160), JFS(800), JFS(26));
        [self addSubview:_meta];
        _genres = JFLabel(16, NO, JFColorDim());
        _genres.frame = CGRectMake(JFS(64), JFS(188), JFS(800), JFS(22));
        [self addSubview:_genres];
        _overview = JFLabel(18, NO, [UIColor colorWithWhite:0.88 alpha:1]);
        _overview.numberOfLines = 5;
        _overview.frame = CGRectMake(JFS(64), JFS(222), JFS(660), JFS(120));
        [self addSubview:_overview];
        _buttons = [NSMutableArray array];

        [self showItem:item];
        [self loadFull];
    }
    return self;
}

- (BOOL)isSeries { return [_item[@"Type"] isEqualToString:@"Series"]; }

- (void)showItem:(NSDictionary *)item {
    _item = item;
    BOOL ep = [item[@"Type"] isEqualToString:@"Episode"];
    _kicker.text = ep ? [item[@"SeriesName"] uppercaseString] : nil;
    _title.text = ep ? JFDisplayTitle(item) : item[@"Name"];
    _meta.text = JFMetaLine(item);
    _genres.text = [item[@"Genres"] componentsJoinedByString:@", "];
    _overview.text = item[@"Overview"];
    [_overview sizeToFit];
    CGRect f = _overview.frame; f.size.width = JFS(660); f.size.height = MIN(f.size.height, JFS(120)); _overview.frame = f;

    JFServer *srv = [JFServer shared];
    NSArray *bd = item[@"BackdropImageTags"], *pbd = item[@"ParentBackdropImageTags"];
    NSURL *url = bd.count ? [srv imageURL:item[@"Id"] type:@"Backdrop" tag:bd[0] maxWidth:1280]
               : pbd.count ? [srv imageURL:item[@"ParentBackdropItemId"] type:@"Backdrop" tag:pbd[0] maxWidth:1280] : nil;
    [JFImages load:url done:^(UIImage *img) {
        if (!img) return;
        self->_backdrop.image = img;
        [UIView animateWithDuration:0.5 animations:^{ self->_backdrop.alpha = 1; }];
    }];
    if (![self isSeries]) [self buildButtons];
}

- (void)loadFull {
    JFServer *srv = [JFServer shared];
    [srv get:[NSString stringWithFormat:@"/Items/%@", _item[@"Id"]]
       query:@{@"userId": srv.userId, @"Fields": [JFItemFields stringByAppendingString:@",Genres"]}
        done:^(id json, NSError *e) {
        if ([json isKindOfClass:[NSDictionary class]]) [self showItem:json];
    }];
    if ([self isSeries]) {
        [srv get:[NSString stringWithFormat:@"/Shows/%@/Seasons", _item[@"Id"]] query:@{@"userId": srv.userId}
            done:^(id json, NSError *e) {
            NSArray *seasons = json[@"Items"];
            if (!seasons.count) return;
            self->_seasons = [[JFRow alloc] initWithTitle:@"Seasons" shape:JFShapePoster width:self.bounds.size.width];
            [self->_seasons setItems:seasons];
            __weak JFDetailScreen *w = self;
            self->_seasons.onFocus = ^(NSDictionary *season) { [w loadEpisodes:season]; };
            [self addSubview:self->_seasons];
            [self layoutZones:NO];
            [self loadEpisodes:seasons[0]];
        }];
    }
}

- (void)loadEpisodes:(NSDictionary *)season {
    JFServer *srv = [JFServer shared];
    [srv get:[NSString stringWithFormat:@"/Shows/%@/Episodes", _item[@"Id"]]
       query:@{@"userId": srv.userId, @"SeasonId": season[@"Id"], @"Fields": JFItemFields,
               @"EnableImageTypes": @"Primary,Backdrop,Thumb", @"ImageTypeLimit": @1}
        done:^(id json, NSError *e) {
        NSArray *eps = json[@"Items"];
        if (!self->_episodes) {
            self->_episodes = [[JFRow alloc] initWithTitle:@"Episodes" shape:JFShapeWide width:self.bounds.size.width];
            [self addSubview:self->_episodes];
        }
        [self->_episodes setItems:eps ?: @[]];
        // Start on the first unwatched episode.
        for (NSUInteger i = 0; i < eps.count; i++)
            if (![eps[i][@"UserData"][@"Played"] boolValue]) { [self->_episodes setIndex:i]; break; }
        [self layoutZones:NO];
    }];
}

- (void)buildButtons {
    for (UIView *b in _buttons) [b removeFromSuperview];
    [_buttons removeAllObjects];
    long long pos = [_item[@"UserData"][@"PlaybackPositionTicks"] longLongValue];
    NSMutableArray *titles = [NSMutableArray array];
    // U+FE0E asks for the text glyph; a bare U+25B6 becomes a blue emoji.
    if (pos > 0) {
        long s = (long)(pos / 10000000LL);
        NSString *at = s >= 3600 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", s / 3600, (s / 60) % 60, s % 60]
                                 : [NSString stringWithFormat:@"%ld:%02ld", s / 60, s % 60];
        [titles addObject:[NSString stringWithFormat:@"▶︎  Resume from %@", at]];
        [titles addObject:@"↺︎  From Start"];
    } else {
        [titles addObject:@"▶︎  Play"];
    }
    CGFloat x = JFS(64), y = JFS(370);
    for (NSString *t in titles) {
        UILabel *b = JFLabel(19, YES, JFColorText());
        b.text = t;
        b.textAlignment = NSTextAlignmentCenter;
        CGFloat w = [t sizeWithAttributes:@{NSFontAttributeName: b.font}].width + JFS(56);
        b.frame = CGRectMake(x, y, w, JFS(50));
        b.layer.cornerRadius = JFS(25);      // layer background: no offscreen masking
        [self addSubview:b];
        [_buttons addObject:b];
        x += w + JFS(18);
    }
    [self layoutZones:NO];
}

- (void)layoutZones:(BOOL)animated {
    if ([self isSeries]) {
        CGFloat y = JFS(350);
        if (_seasons) { _seasons.frame = CGRectMake(0, _zone == 2 ? JFS(-400) : y, _seasons.frame.size.width, _seasons.frame.size.height); }
        if (_episodes) {
            CGFloat ey = _zone == 2 ? JFS(350) : y + (_seasons ? _seasons.frame.size.height : 0);
            _episodes.frame = CGRectMake(0, ey, _episodes.frame.size.width, _episodes.frame.size.height);
        }
        if (_zone == 0) _zone = 1;          // a series has no buttons: start on Seasons
        _seasons.active = _zone == 1;
        _episodes.active = _zone == 2;
        return;
    }
    for (NSUInteger i = 0; i < _buttons.count; i++) {
        UILabel *b = _buttons[i];
        BOOL on = (NSInteger)i == _button;
        b.layer.backgroundColor = (on ? [UIColor whiteColor] : [UIColor colorWithWhite:1 alpha:0.12]).CGColor;
        b.textColor = on ? [UIColor blackColor] : JFColorText();
        b.transform = on ? CGAffineTransformMakeScale(1.06, 1.06) : CGAffineTransformIdentity;
    }
}

- (void)arrow:(JFKey)k {
    if ([self isSeries]) {
        JFRow *r = _zone == 2 ? _episodes : _seasons;
        if (k == JFKeyLeft) [r move:-1];
        else if (k == JFKeyRight) [r move:1];
        else if (k == JFKeyDown && _zone == 1 && _episodes.items.count) _zone = 2;
        else if (k == JFKeyUp && _zone == 2) _zone = 1;
        [UIView animateWithDuration:0.25 animations:^{ [self layoutZones:YES]; }];
        return;
    }
    NSInteger n = _button + (k == JFKeyRight ? 1 : k == JFKeyLeft ? -1 : 0);
    if (n >= 0 && n < (NSInteger)_buttons.count) {
        _button = n;
        [UIView animateWithDuration:0.2 animations:^{ [self layoutZones:YES]; }];
    }
}

- (void)key:(JFKey)k {
    if (k != JFKeySelect && k != JFKeyPlayPause) return;
    if ([self isSeries]) {
        if (_zone == 2 && _episodes.focusedItem) {
            NSDictionary *ep = _episodes.focusedItem;
            if (k == JFKeyPlayPause) [self.nav pushScreen:[[JFPlayerScreen alloc] initWithFrame:self.bounds item:ep fromStart:NO]];
            else [self.nav pushScreen:[[JFDetailScreen alloc] initWithFrame:self.bounds item:ep]];
        } else if (_zone == 1) {
            _zone = 2;
            [UIView animateWithDuration:0.25 animations:^{ [self layoutZones:YES]; }];
        }
        return;
    }
    BOOL fromStart = _buttons.count > 1 && _button == 1;
    [self.nav pushScreen:[[JFPlayerScreen alloc] initWithFrame:self.bounds item:_item fromStart:fromStart]];
}

- (void)screenDidAppear {
    // Back from the player: refresh the resume point.
    if (![self isSeries] && _item[@"Id"]) [self loadFull];
}
@end
