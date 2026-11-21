#import "JFScreens.h"
#import "JFRow.h"
#import "JFServer.h"

// A library as a grid: one JFRow per line of the grid, so cards, focus and
// image loading behave exactly as on Home.  Pages of 120 load as you go down.
@implementation JFLibraryScreen {
    NSDictionary *_library;
    JFShape _shape;
    NSInteger _perLine;
    NSMutableArray *_items, *_lines;
    UIView *_linesView;
    UILabel *_title, *_count;
    NSInteger _line, _total;
    BOOL _loading;
}

#define GRID_TOP JFS(100)

- (instancetype)initWithFrame:(CGRect)frame library:(NSDictionary *)library {
    if ((self = [super initWithFrame:frame])) {
        _library = library;
        self.backgroundColor = JFColorBackground();
        self.clipsToBounds = YES;
        NSString *type = library[@"CollectionType"] ?: @"";
        _shape = [type isEqualToString:@"music"] ? JFShapeSquare
               : [library[@"Type"] isEqualToString:@"Season"] ? JFShapeWide : JFShapePoster;
        _perLine = _shape == JFShapePoster ? 6 : _shape == JFShapeSquare ? 5 : 4;
        _items = [NSMutableArray array];
        _lines = [NSMutableArray array];

        _linesView = [[UIView alloc] initWithFrame:CGRectMake(0, GRID_TOP, frame.size.width, frame.size.height)];
        [self addSubview:_linesView];

        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, GRID_TOP - JFS(6))];
        CAGradientLayer *g = [CAGradientLayer layer];
        g.frame = bar.bounds;
        g.colors = @[(id)JFColorBackground().CGColor, (id)JFColorBackground().CGColor, (id)[JFColorBackground() colorWithAlphaComponent:0].CGColor];
        g.locations = @[@0, @0.75, @1];
        [bar.layer addSublayer:g];
        [self addSubview:bar];

        _title = JFLabel(32, YES, JFColorText());
        _title.frame = CGRectMake(JFS(64), JFS(32), JFS(800), JFS(40));
        _title.text = [library[@"Type"] isEqualToString:@"Season"]
            ? [NSString stringWithFormat:@"%@ · %@", library[@"SeriesName"] ?: @"", library[@"Name"]] : library[@"Name"];
        [self addSubview:_title];
        _count = JFLabel(17, NO, JFColorDim());
        _count.textAlignment = NSTextAlignmentRight;
        _count.frame = CGRectMake(frame.size.width - JFS(364), JFS(44), JFS(300), JFS(24));
        [self addSubview:_count];
        [self loadMore];
    }
    return self;
}

- (NSDictionary *)query {
    NSString *type = _library[@"CollectionType"] ?: @"";
    NSMutableDictionary *q = [@{@"userId": [JFServer shared].userId, @"ParentId": _library[@"Id"],
                                @"SortBy": @"SortName", @"SortOrder": @"Ascending", @"Fields": JFItemFields,
                                @"EnableImageTypes": @"Primary,Backdrop,Thumb", @"ImageTypeLimit": @1,
                                @"StartIndex": @(_items.count), @"Limit": @120} mutableCopy];
    NSDictionary *kinds = @{@"movies": @"Movie", @"tvshows": @"Series", @"music": @"MusicAlbum",
                            @"boxsets": @"BoxSet", @"homevideos": @"Video,Photo"};
    if (kinds[type]) { q[@"IncludeItemTypes"] = kinds[type]; q[@"Recursive"] = @"true"; }
    if ([_library[@"Type"] isEqualToString:@"Season"]) { q[@"SortBy"] = @"IndexNumber"; q[@"ParentId"] = _library[@"Id"]; }
    return q;
}

- (void)loadMore {
    if (_loading || (_total && (NSInteger)_items.count >= _total)) return;
    _loading = YES;
    [[JFServer shared] get:@"/Items" query:[self query] done:^(id json, NSError *e) {
        self->_loading = NO;
        NSArray *page = json[@"Items"];
        if (!page) return;
        self->_total = [json[@"TotalRecordCount"] integerValue];
        self->_count.text = [NSString stringWithFormat:@"%ld items", (long)self->_total];
        [self->_items addObjectsFromArray:page];
        [self buildLines];
    }];
}

- (void)buildLines {
    NSInteger needed = (_items.count + _perLine - 1) / _perLine;
    CGFloat h = [JFRow heightForShape:_shape] - JFS(34);
    for (NSInteger i = 0; i < needed; i++) {
        NSArray *slice = [_items subarrayWithRange:NSMakeRange(i * _perLine, MIN(_perLine, (NSInteger)_items.count - i * _perLine))];
        if (i < (NSInteger)_lines.count) {
            JFRow *r = _lines[i];
            if (r.items.count != slice.count) { NSInteger idx = r.index; [r setItems:slice]; [r setIndex:idx]; }
            continue;
        }
        JFRow *r = [[JFRow alloc] initWithTitle:nil shape:_shape width:self.bounds.size.width];
        [r setItems:slice];
        r.frame = CGRectMake(0, i * h - JFS(34), r.frame.size.width, r.frame.size.height);
        [_linesView addSubview:r];
        [_lines addObject:r];
    }
    [self layoutLines:NO];
}

- (void)layoutLines:(BOOL)animated {
    CGFloat h = [JFRow heightForShape:_shape] - JFS(34);
    void (^apply)(void) = ^{
        CGRect f = self->_linesView.frame;
        f.origin.y = GRID_TOP - MAX(0, (self->_line - 1)) * h;
        self->_linesView.frame = f;
        for (NSInteger i = 0; i < (NSInteger)self->_lines.count; i++) [self->_lines[i] setActive:i == self->_line];
    };
    if (animated)
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:apply completion:nil];
    else apply();
}

- (void)arrow:(JFKey)k {
    if (!_lines.count) return;
    JFRow *r = _lines[_line];
    if (k == JFKeyLeft) { [r move:-1]; return; }
    if (k == JFKeyRight) { [r move:1]; return; }
    NSInteger n = _line + (k == JFKeyDown ? 1 : -1);
    if (n < 0 || n >= (NSInteger)_lines.count) return;
    NSInteger col = r.index;
    _line = n;
    [_lines[n] setIndex:col];
    [self layoutLines:YES];
    if (_line >= (NSInteger)_lines.count - 3) [self loadMore];
}

- (void)key:(JFKey)k {
    if (!_lines.count) return;
    NSDictionary *item = [_lines[_line] focusedItem];
    if (!item) return;
    if (k == JFKeyPlayPause && ![item[@"IsFolder"] boolValue])
        [self.nav pushScreen:[[JFPlayerScreen alloc] initWithFrame:self.bounds item:item fromStart:NO]];
    else if (k == JFKeySelect)
        JFOpenItem(self.nav, self.bounds, item);
}
@end
