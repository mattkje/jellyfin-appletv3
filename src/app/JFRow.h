// JFRow -- a titled horizontal row of item cards (posters, wide thumbnails or
// squares) with a focus ring, eased scrolling and progress bars.
#import "JFUI.h"

typedef enum { JFShapePoster, JFShapeWide, JFShapeSquare } JFShape;

@interface JFRow : UIView
@property (nonatomic, copy) void (^onFocus)(NSDictionary *item);
@property (nonatomic, copy) void (^onSelect)(NSDictionary *item);
@property (nonatomic, readonly) NSArray *items;
@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, assign) BOOL active;

- (instancetype)initWithTitle:(NSString *)title shape:(JFShape)shape width:(CGFloat)width;
- (void)setItems:(NSArray *)items;
- (NSDictionary *)focusedItem;
- (BOOL)move:(int)delta;                 // NO at either end
- (void)setIndex:(NSInteger)index;
+ (CGFloat)heightForShape:(JFShape)shape;
@end

// Which image an item shows for a shape, falling back to the series/parent.
NSURL *JFCardImageURL(NSDictionary *item, JFShape shape);
