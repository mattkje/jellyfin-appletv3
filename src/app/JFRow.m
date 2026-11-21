#import "JFRow.h"
#import "JFServer.h"

static CGSize jf_card_size(JFShape s) {
    switch (s) {
        case JFShapePoster: return CGSizeMake(JFS(150), JFS(225));
        case JFShapeWide:   return CGSizeMake(JFS(272), JFS(153));
        case JFShapeSquare: return CGSizeMake(JFS(180), JFS(180));
    }
    return CGSizeZero;
}
#define JF_GAP   JFS(22)
#define JF_TITLE JFS(34)

NSURL *JFCardImageURL(NSDictionary *item, JFShape shape) {
    JFServer *srv = [JFServer shared];
    NSDictionary *tags = item[@"ImageTags"];
    int w = shape == JFShapeWide ? 544 : 300;
    if (shape == JFShapeWide) {
        // Episodes: their own still; else the item's Thumb, then a backdrop.
        if ([item[@"Type"] isEqualToString:@"Episode"] && tags[@"Primary"])
            return [srv imageURL:item[@"Id"] type:@"Primary" tag:tags[@"Primary"] maxWidth:w];
        if (tags[@"Thumb"]) return [srv imageURL:item[@"Id"] type:@"Thumb" tag:tags[@"Thumb"] maxWidth:w];
        if (item[@"ParentThumbItemId"])
            return [srv imageURL:item[@"ParentThumbItemId"] type:@"Thumb" tag:item[@"ParentThumbImageTag"] maxWidth:w];
        NSArray *bd = item[@"BackdropImageTags"];
        if (bd.count) return [srv imageURL:item[@"Id"] type:@"Backdrop" tag:bd[0] maxWidth:w];
        NSArray *pbd = item[@"ParentBackdropImageTags"];
        if (pbd.count) return [srv imageURL:item[@"ParentBackdropItemId"] type:@"Backdrop" tag:pbd[0] maxWidth:w];
    }
    if (tags[@"Primary"]) return [srv imageURL:item[@"Id"] type:@"Primary" tag:tags[@"Primary"] maxWidth:w];
    if (item[@"SeriesId"] && item[@"SeriesPrimaryImageTag"])
        return [srv imageURL:item[@"SeriesId"] type:@"Primary" tag:item[@"SeriesPrimaryImageTag"] maxWidth:w];
    return nil;
}

// ---- card ---------------------------------------------------------------------------

@interface JFCard : UIView
@property (nonatomic, strong) UIView *frameView;
@property (nonatomic, strong) JFImageView *image;
@property (nonatomic, strong) UILabel *placeholder;
@property (nonatomic, strong) UILabel *caption;
@property (nonatomic, strong) UIView *progress;
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, assign) BOOL loaded;
@end

@implementation JFCard
- (instancetype)initWithItem:(NSDictionary *)item shape:(JFShape)shape {
    CGSize sz = jf_card_size(shape);
    if ((self = [super initWithFrame:CGRectMake(0, 0, sz.width, sz.height + JFS(30))])) {
        _frameView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, sz.width, sz.height)];
        _frameView.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1];
        _frameView.layer.cornerRadius = JFS(6);
        _frameView.layer.shadowColor = [UIColor blackColor].CGColor;
        _frameView.layer.shadowOpacity = 0.5;
        _frameView.layer.shadowRadius = JFS(10);
        _frameView.layer.shadowOffset = CGSizeMake(0, JFS(6));
        // An explicit path keeps the shadow cheap (no per-frame alpha scan).
        _frameView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:_frameView.bounds cornerRadius:JFS(6)].CGPath;
        [self addSubview:_frameView];

        _placeholder = JFLabel(15, YES, JFColorDim());
        _placeholder.frame = CGRectInset(_frameView.bounds, JFS(10), JFS(10));
        _placeholder.numberOfLines = 3;
        _placeholder.textAlignment = NSTextAlignmentCenter;
        _placeholder.text = item[@"Name"];
        [_frameView addSubview:_placeholder];

        _image = [[JFImageView alloc] initWithFrame:_frameView.bounds];
        _image.cornerRadius = JFS(6);
        [_frameView addSubview:_image];

        double played = JFPlayedFraction(item);
        if (played > 0.01 && played < 0.99) {
            UIView *track = [[UIView alloc] initWithFrame:CGRectMake(JFS(8), sz.height - JFS(10), sz.width - JFS(16), JFS(4))];
            track.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
            track.layer.cornerRadius = JFS(2);
            [_frameView addSubview:track];
            _progress = [[UIView alloc] initWithFrame:CGRectMake(0, 0, track.bounds.size.width * played, JFS(4))];
            _progress.backgroundColor = JFColorAccent();
            _progress.layer.cornerRadius = JFS(2);
            [track addSubview:_progress];
        }

        _caption = JFLabel(14, NO, JFColorDim());
        _caption.frame = CGRectMake(0, sz.height + JFS(8), sz.width, JFS(20));
        _caption.text = JFDisplayTitle(item);   // "S1:E2 · Title" for episodes
        _caption.alpha = 0;
        [self addSubview:_caption];

        _url = JFCardImageURL(item, shape);
    }
    return self;
}

- (void)loadImage {
    if (self.loaded || !self.url) return;
    self.loaded = YES;
    __weak JFCard *w = self;
    [JFImages load:self.url done:^(UIImage *img) {
        if (!img) return;
        w.image.image = img;
        w.image.alpha = 0;
        [UIView animateWithDuration:0.25 animations:^{ w.image.alpha = 1; }];
    }];
}

- (void)setHighlighted:(BOOL)on {
    self.frameView.transform = on ? CGAffineTransformMakeScale(1.08, 1.08) : CGAffineTransformIdentity;
    self.frameView.layer.borderWidth = on ? JFS(3) : 0;
    self.frameView.layer.borderColor = [UIColor whiteColor].CGColor;
    self.frameView.layer.shadowOpacity = on ? 0.8 : 0.5;
    self.caption.alpha = on ? 1 : 0;
    self.caption.textColor = on ? JFColorText() : JFColorDim();
}
@end

// ---- row ----------------------------------------------------------------------------

@implementation JFRow {
    JFShape _shape;
    UILabel *_title;
    UIView *_strip;
    NSMutableArray *_cards;
    CGFloat _width;
}

+ (CGFloat)heightForShape:(JFShape)shape { return JF_TITLE + jf_card_size(shape).height + JFS(44); }

- (instancetype)initWithTitle:(NSString *)title shape:(JFShape)shape width:(CGFloat)width {
    if ((self = [super initWithFrame:CGRectMake(0, 0, width, [JFRow heightForShape:shape])])) {
        _shape = shape;
        _width = width;
        _title = JFLabel(21, YES, JFColorText());
        _title.frame = CGRectMake(JFS(64), 0, width - JFS(128), JFS(26));
        _title.text = title;
        [self addSubview:_title];
        _strip = [[UIView alloc] initWithFrame:CGRectMake(JFS(64), JF_TITLE, width, jf_card_size(shape).height + JFS(40))];
        [self addSubview:_strip];
        _cards = [NSMutableArray array];
    }
    return self;
}

- (void)setItems:(NSArray *)items {
    _items = [items copy];
    for (UIView *c in _cards) [c removeFromSuperview];
    [_cards removeAllObjects];
    CGSize sz = jf_card_size(_shape);
    for (NSUInteger i = 0; i < items.count; i++) {
        JFCard *c = [[JFCard alloc] initWithItem:items[i] shape:_shape];
        c.frame = CGRectMake(i * (sz.width + JF_GAP), 0, c.frame.size.width, c.frame.size.height);
        [_strip addSubview:c];
        [_cards addObject:c];
    }
    _index = MIN(_index, (NSInteger)items.count - 1);
    if (_index < 0) _index = 0;
    [self layoutFocus:NO];
}

- (NSDictionary *)focusedItem { return _index < (NSInteger)_items.count ? _items[_index] : nil; }

- (void)setActive:(BOOL)active {
    _active = active;
    [self layoutFocus:YES];
}

- (void)setIndex:(NSInteger)index {
    _index = MAX(0, MIN(index, (NSInteger)_items.count - 1));
    [self layoutFocus:NO];
}

- (BOOL)move:(int)delta {
    NSInteger n = _index + delta;
    if (n < 0 || n >= (NSInteger)_items.count) return NO;
    _index = n;
    [self layoutFocus:YES];
    if (self.onFocus) self.onFocus(self.focusedItem);
    return YES;
}

- (void)layoutFocus:(BOOL)animated {
    CGFloat step = jf_card_size(_shape).width + JF_GAP;
    // Keep the focused card in the left third once the row has scrolled.
    CGFloat visible = _width - JFS(128);
    CGFloat maxShift = MAX(0, _cards.count * step - JF_GAP - visible);
    CGFloat shift = MIN(maxShift, MAX(0, _index * step - JFS(2) * step / 2));
    void (^apply)(void) = ^{
        CGRect f = self->_strip.frame;
        f.origin.x = JFS(64) - shift;
        self->_strip.frame = f;
        for (NSUInteger i = 0; i < self->_cards.count; i++)
            [self->_cards[i] setHighlighted:self->_active && (NSInteger)i == self->_index];
    };
    if (animated)
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:apply completion:nil];
    else apply();
    // Load what is on screen plus a few either side.
    NSInteger first = (NSInteger)(shift / step) - 2, last = (NSInteger)((shift + visible) / step) + 3;
    for (NSInteger i = MAX(0, first); i < MIN((NSInteger)_cards.count, last); i++) [_cards[i] loadImage];
}

@end
