#import "JFScreens.h"
#import "JFRow.h"
#import "JFServer.h"
#import "JFLog.h"

NSString *const JFItemFields = @"Overview,PrimaryImageAspectRatio,ProductionYear,OfficialRating,CommunityRating,RunTimeTicks,ParentId";

// Full-screen backdrop that cross-fades, under left and bottom shades.
@interface JFBackdrop : UIView
- (void)showItem:(NSDictionary *)item;
@end

@implementation JFBackdrop {
    JFImageView *_a, *_b;
    NSURL *_current;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = YES;
        _a = [[JFImageView alloc] initWithFrame:self.bounds];
        _b = [[JFImageView alloc] initWithFrame:self.bounds];
        for (JFImageView *v in @[_a, _b]) { v.alpha = 0; [self addSubview:v]; }
        CAGradientLayer *left = [CAGradientLayer layer];
        left.frame = self.bounds;
        left.colors = @[(id)[JFColorBackground() colorWithAlphaComponent:0.95].CGColor,
                        (id)[JFColorBackground() colorWithAlphaComponent:0.55].CGColor,
                        (id)[JFColorBackground() colorWithAlphaComponent:0.15].CGColor];
        left.startPoint = CGPointMake(0, 0.5);
        left.endPoint = CGPointMake(1, 0.5);
        [self.layer addSublayer:left];
        CAGradientLayer *bottom = [CAGradientLayer layer];
        bottom.frame = self.bounds;
        bottom.colors = @[(id)[UIColor clearColor].CGColor, (id)JFColorBackground().CGColor];
        bottom.locations = @[@0.25, @0.62];
        [self.layer addSublayer:bottom];
    }
    return self;
}
- (void)showItem:(NSDictionary *)item {
    JFServer *srv = [JFServer shared];
    NSURL *url = nil;
    NSArray *bd = item[@"BackdropImageTags"], *pbd = item[@"ParentBackdropImageTags"];
    if (bd.count) url = [srv imageURL:item[@"Id"] type:@"Backdrop" tag:bd[0] maxWidth:1280];
    else if (pbd.count) url = [srv imageURL:item[@"ParentBackdropItemId"] type:@"Backdrop" tag:pbd[0] maxWidth:1280];
    if ([url isEqual:_current]) return;
    _current = url;
    if (!url) { [UIView animateWithDuration:0.4 animations:^{ self->_a.alpha = 0; self->_b.alpha = 0; }]; return; }
    [JFImages load:url done:^(UIImage *img) {
        if (![url isEqual:self->_current] || !img) return;
        JFImageView *front = self->_a.alpha > 0 ? self->_a : self->_b, *back = front == self->_a ? self->_b : self->_a;
        back.image = img;
        [self bringSubviewToFront:back];
        for (CALayer *l in [self.layer.sublayers copy]) if ([l isKindOfClass:[CAGradientLayer class]]) [self.layer addSublayer:l];
        [UIView animateWithDuration:0.5 animations:^{ back.alpha = 1; front.alpha = 0; }];
    }];
}
@end

// ---- home -----------------------------------------------------------------------------

@implementation JFHomeScreen {
    JFBackdrop *_backdrop;
    UILabel *_title, *_meta, *_overview, *_user;
    NSArray *_headerButtons;      // UILabel pills: Change Server, Sign Out
    BOOL _inHeader;
    NSInteger _headerIndex;
    UIView *_rowsView;
    NSMutableArray *_rows;        // JFRow, in display order
    NSInteger _focusRow;
    BOOL _loaded;
}

#define ROWS_TOP JFS(318)

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = JFColorBackground();
        self.clipsToBounds = YES;
        CGFloat W = frame.size.width;
        _backdrop = [[JFBackdrop alloc] initWithFrame:self.bounds];
        [self addSubview:_backdrop];

        UILabel *logo = JFLabel(22, YES, JFColorText());
        logo.text = @"Jellyfin";
        logo.frame = CGRectMake(JFS(64), JFS(30), JFS(200), JFS(30));
        [self addSubview:logo];
        // Header actions, reached with Up from the top row.
        NSMutableArray *buttons = [NSMutableArray array];
        CGFloat x = W - JFS(64);
        for (NSString *t in @[@"Sign Out", @"Change Server"]) {
            UILabel *b = JFLabel(15, YES, JFColorDim());
            b.text = t;
            b.textAlignment = NSTextAlignmentCenter;
            CGFloat w = [t sizeWithAttributes:@{NSFontAttributeName: b.font}].width + JFS(36);
            x -= w;
            b.frame = CGRectMake(x, JFS(28), w, JFS(34));
            b.layer.cornerRadius = JFS(17);
            b.layer.borderWidth = JFS(1.5);
            b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
            [self addSubview:b];
            [buttons insertObject:b atIndex:0];
            x -= JFS(12);
        }
        _headerButtons = buttons;
        _user = JFLabel(17, NO, JFColorDim());
        _user.textAlignment = NSTextAlignmentRight;
        _user.frame = CGRectMake(x - JFS(300), JFS(33), JFS(288), JFS(24));
        _user.text = [JFServer shared].userName;
        [self addSubview:_user];

        _title = JFLabel(40, YES, JFColorText());
        _title.frame = CGRectMake(JFS(64), JFS(96), JFS(760), JFS(50));
        [self addSubview:_title];
        _meta = JFLabel(17, NO, JFColorDim());
        _meta.frame = CGRectMake(JFS(64), JFS(150), JFS(760), JFS(24));
        [self addSubview:_meta];
        _overview = JFLabel(17, NO, [UIColor colorWithWhite:0.85 alpha:1]);
        _overview.numberOfLines = 3;
        _overview.frame = CGRectMake(JFS(64), JFS(182), JFS(640), JFS(72));
        [self addSubview:_overview];

        _rowsView = [[UIView alloc] initWithFrame:CGRectMake(0, ROWS_TOP, W, frame.size.height)];
        [self addSubview:_rowsView];
        _rows = [NSMutableArray array];
    }
    return self;
}

- (void)screenDidAppear {
    if (!_loaded) { _loaded = YES; [self load]; }
    else [self refreshResume];
}

// Row keys fix the order rows appear in, whatever order the requests finish.
static NSArray *jf_row_order(void) { return @[@"resume", @"nextup", @"views"]; }

- (void)addRow:(NSString *)key title:(NSString *)title shape:(JFShape)shape items:(NSArray *)items {
    if (!items.count) return;
    JFRow *existing = nil;
    for (JFRow *r in _rows) if ([r.accessibilityIdentifier isEqualToString:key]) existing = r;
    if (existing) { [existing setItems:items]; [self focusChanged]; return; }

    JFRow *row = [[JFRow alloc] initWithTitle:title shape:shape width:self.bounds.size.width];
    row.accessibilityIdentifier = key;
    [row setItems:items];
    __weak JFHomeScreen *w = self;
    row.onFocus = ^(NSDictionary *item) { [w showHero:item]; };
    row.onSelect = ^(NSDictionary *item) { JFOpenItem(w.nav, w.bounds, item); };

    // Insert by the fixed order: known keys first, then "latest-*" in arrival order.
    NSArray *order = jf_row_order();
    NSUInteger rank = [order indexOfObject:key];
    if (rank == NSNotFound) rank = order.count;
    NSUInteger at = _rows.count;
    for (NSUInteger i = 0; i < _rows.count; i++) {
        NSUInteger r = [order indexOfObject:[_rows[i] accessibilityIdentifier]];
        if (r == NSNotFound) r = order.count;
        if (rank < r) { at = i; break; }
    }
    JFRow *focusedBefore = _focusRow < (NSInteger)_rows.count ? _rows[_focusRow] : nil;
    [_rows insertObject:row atIndex:at];
    [_rowsView addSubview:row];
    if (focusedBefore) _focusRow = [_rows indexOfObject:focusedBefore];
    [self layoutRows:NO];
    [self focusChanged];
}

- (void)load {
    JFServer *srv = [JFServer shared];
    NSString *uid = srv.userId;
    NSDictionary *common = @{@"userId": uid, @"Fields": JFItemFields, @"EnableImageTypes": @"Primary,Backdrop,Thumb", @"ImageTypeLimit": @1};

    [self refreshResume];

    NSMutableDictionary *q = [common mutableCopy]; q[@"Limit"] = @24;
    [srv get:@"/Shows/NextUp" query:q done:^(id json, NSError *e) {
        [self addRow:@"nextup" title:@"Next Up" shape:JFShapeWide items:json[@"Items"]];
    }];

    [srv get:@"/UserViews" query:@{@"userId": uid} done:^(id json, NSError *e) {
        NSArray *views = json[@"Items"];
        [self addRow:@"views" title:@"My Media" shape:JFShapeWide items:views];
        for (NSDictionary *v in views) {
            NSString *type = v[@"CollectionType"];
            if (![@[@"movies", @"tvshows", @"music", @"homevideos"] containsObject:type ?: @""]) continue;
            NSMutableDictionary *lq = [common mutableCopy];
            lq[@"ParentId"] = v[@"Id"];
            lq[@"Limit"] = @24;
            [srv get:@"/Items/Latest" query:lq done:^(id latest, NSError *e2) {
                NSArray *items = [latest isKindOfClass:[NSArray class]] ? latest : nil;
                [self addRow:[@"latest-" stringByAppendingString:v[@"Id"]]
                       title:[NSString stringWithFormat:@"Recently Added in %@", v[@"Name"]]
                       shape:[type isEqualToString:@"music"] ? JFShapeSquare : JFShapePoster
                       items:items];
            }];
        }
    }];
}

- (void)refreshResume {
    JFServer *srv = [JFServer shared];
    if (!srv.userId) return;
    NSDictionary *q = @{@"userId": srv.userId, @"Fields": JFItemFields, @"MediaTypes": @"Video",
                        @"EnableImageTypes": @"Primary,Backdrop,Thumb", @"ImageTypeLimit": @1, @"Limit": @24};
    [srv get:@"/UserItems/Resume" query:q done:^(id json, NSError *e) {
        [self addRow:@"resume" title:@"Continue Watching" shape:JFShapeWide items:json[@"Items"]];
    }];
}

- (void)showHero:(NSDictionary *)item {
    BOOL episode = [item[@"Type"] isEqualToString:@"Episode"];
    _title.text = episode ? item[@"SeriesName"] : item[@"Name"];
    _meta.text = episode ? [NSString stringWithFormat:@"%@  ·  %@", JFDisplayTitle(item), JFMetaLine(item)] : JFMetaLine(item);
    _overview.text = item[@"Overview"];
    [_backdrop showItem:item];
}

- (void)focusChanged {
    if (_focusRow >= (NSInteger)_rows.count) return;
    JFRow *r = _rows[_focusRow];
    if (r.focusedItem) [self showHero:r.focusedItem];
}

- (void)layoutRows:(BOOL)animated {
    void (^apply)(void) = ^{
        CGFloat y = 0, offset = 0;
        for (NSInteger i = 0; i < (NSInteger)self->_rows.count; i++) {
            JFRow *r = self->_rows[i];
            if (i == self->_focusRow) offset = y;
            CGRect f = r.frame; f.origin.y = y; r.frame = f;
            y += f.size.height;
        }
        for (NSInteger i = 0; i < (NSInteger)self->_rows.count; i++) {
            JFRow *r = self->_rows[i];
            r.alpha = i < self->_focusRow ? 0 : 1;
            r.active = i == self->_focusRow;
        }
        CGRect f = self->_rowsView.frame;
        f.origin.y = ROWS_TOP - offset;
        self->_rowsView.frame = f;
    };
    if (animated)
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:apply completion:nil];
    else apply();
}

- (void)arrow:(JFKey)k {
    if (_inHeader) {
        if (k == JFKeyDown && _rows.count) { _inHeader = NO; [self layoutHeader]; [self layoutRows:YES]; }
        else if (k == JFKeyLeft && _headerIndex > 0) { _headerIndex--; [self layoutHeader]; }
        else if (k == JFKeyRight && _headerIndex < (NSInteger)_headerButtons.count - 1) { _headerIndex++; [self layoutHeader]; }
        return;
    }
    if (!_rows.count) { if (k == JFKeyUp) { _inHeader = YES; [self layoutHeader]; } return; }
    JFRow *r = _rows[_focusRow];
    if (k == JFKeyUp && _focusRow == 0) {
        _inHeader = YES;
        r.active = NO;
        [self layoutHeader];
        return;
    }
    if (k == JFKeyLeft) [r move:-1];
    else if (k == JFKeyRight) [r move:1];
    else {
        NSInteger n = _focusRow + (k == JFKeyDown ? 1 : -1);
        if (n < 0 || n >= (NSInteger)_rows.count) return;
        _focusRow = n;
        [self layoutRows:YES];
        [self focusChanged];
    }
}

- (void)layoutHeader {
    [UIView animateWithDuration:0.2 animations:^{
        for (NSInteger i = 0; i < (NSInteger)self->_headerButtons.count; i++) {
            UILabel *b = self->_headerButtons[i];
            BOOL on = self->_inHeader && i == self->_headerIndex;
            b.layer.backgroundColor = (on ? [UIColor whiteColor] : [UIColor clearColor]).CGColor;
            b.textColor = on ? [UIColor blackColor] : JFColorDim();
            b.transform = on ? CGAffineTransformMakeScale(1.06, 1.06) : CGAffineTransformIdentity;
        }
    }];
}

- (void)key:(JFKey)k {
    if (_inHeader) {
        if (k != JFKeySelect) return;
        JFServer *srv = [JFServer shared];
        if (_headerIndex == 1) [srv signOut]; else [srv forgetServer];
        [self.nav replaceWithScreen:[[JFConnectScreen alloc] initWithFrame:self.bounds]];
        return;
    }
    if ((k == JFKeySelect || k == JFKeyPlayPause) && _focusRow < (NSInteger)_rows.count) {
        JFRow *r = _rows[_focusRow];
        NSDictionary *item = r.focusedItem;
        if (!item) return;
        if (k == JFKeyPlayPause && ![item[@"IsFolder"] boolValue]) {
            [self.nav pushScreen:[[JFPlayerScreen alloc] initWithFrame:self.bounds item:item fromStart:NO]];
            return;
        }
        if (r.onSelect) r.onSelect(item);
    }
}
@end

void JFOpenItem(id<JFNavigator> nav, CGRect frame, NSDictionary *item) {
    NSString *type = item[@"Type"];
    if ([type isEqualToString:@"CollectionFolder"] || [type isEqualToString:@"UserView"] ||
        [type isEqualToString:@"Folder"] || [type isEqualToString:@"BoxSet"] || [type isEqualToString:@"Season"])
        [nav pushScreen:[[JFLibraryScreen alloc] initWithFrame:frame library:item]];
    else
        [nav pushScreen:[[JFDetailScreen alloc] initWithFrame:frame item:item]];
}
