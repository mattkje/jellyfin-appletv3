#import "JFUI.h"

CGFloat jf_scale = 1;

UIColor *JFColorBackground(void) { return [UIColor colorWithRed:0.063 green:0.063 blue:0.063 alpha:1]; }
UIColor *JFColorAccent(void)     { return [UIColor colorWithRed:0 green:0.643 blue:0.863 alpha:1]; }
UIColor *JFColorText(void)       { return [UIColor colorWithWhite:0.96 alpha:1]; }
UIColor *JFColorDim(void)        { return [UIColor colorWithWhite:0.66 alpha:1]; }

// Named fonts only: inside AppleTV.app the generic system font resolves to no
// glyphs at all (every character drew as a missing-glyph box).  Avenir Next
// and Helvetica Neue ship in /System/Library/Fonts on the Apple TV 3.
UIFont *JFFont(CGFloat size, BOOL bold) {
    UIFont *f = [UIFont fontWithName:bold ? @"AvenirNext-DemiBold" : @"AvenirNext-Regular" size:JFS(size)];
    if (!f) f = [UIFont fontWithName:bold ? @"HelveticaNeue-Medium" : @"HelveticaNeue" size:JFS(size)];
    return f;
}

UILabel *JFLabel(CGFloat size, BOOL bold, UIColor *color) {
    UILabel *l = [[UILabel alloc] init];
    l.font = JFFont(size, bold);
    l.textColor = color;
    l.backgroundColor = [UIColor clearColor];
    return l;
}

NSString *JFMetaLine(NSDictionary *item) {
    NSMutableArray *parts = [NSMutableArray array];
    if (item[@"ProductionYear"]) [parts addObject:[item[@"ProductionYear"] description]];
    long long ticks = [item[@"RunTimeTicks"] longLongValue];
    if (ticks > 0) {
        long mins = (long)(ticks / 600000000LL);
        [parts addObject:mins >= 60 ? [NSString stringWithFormat:@"%ldh %ldm", mins / 60, mins % 60]
                                    : [NSString stringWithFormat:@"%ldm", mins]];
    }
    if ([item[@"OfficialRating"] length]) [parts addObject:item[@"OfficialRating"]];
    if (item[@"CommunityRating"]) [parts addObject:[NSString stringWithFormat:@"★ %.1f", [item[@"CommunityRating"] doubleValue]]];
    return [parts componentsJoinedByString:@"  ·  "];
}

NSString *JFDisplayTitle(NSDictionary *item) {
    if ([item[@"Type"] isEqualToString:@"Episode"]) {
        NSMutableString *s = [NSMutableString string];
        if (item[@"ParentIndexNumber"] && item[@"IndexNumber"])
            [s appendFormat:@"S%@:E%@ · ", item[@"ParentIndexNumber"], item[@"IndexNumber"]];
        [s appendString:item[@"Name"] ?: @""];
        return s;
    }
    return item[@"Name"] ?: @"";
}

double JFPlayedFraction(NSDictionary *item) {
    NSDictionary *ud = item[@"UserData"];
    if (ud[@"PlayedPercentage"]) return [ud[@"PlayedPercentage"] doubleValue] / 100.0;
    return 0;
}

@implementation JFScreen
- (void)screenDidAppear {}
- (void)screenWillDisappear {}
- (void)arrow:(JFKey)k {}
- (void)key:(JFKey)k {}
- (BOOL)handlesMenu { return NO; }
@end

@implementation JFImageView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}
- (void)setImage:(UIImage *)image { _image = image; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect {
    if (!_image) return;
    CGSize b = self.bounds.size, s = _image.size;
    CGFloat k = MAX(b.width / s.width, b.height / s.height);
    CGSize d = CGSizeMake(s.width * k, s.height * k);
    // Rounding by clipping here costs nothing per frame; layer.cornerRadius with
    // masksToBounds renders offscreen every frame, which the A5 cannot afford.
    if (_cornerRadius > 0) [[UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:_cornerRadius] addClip];
    [_image drawInRect:CGRectMake((b.width - d.width) / 2, (b.height - d.height) / 2, d.width, d.height)];
}
@end
