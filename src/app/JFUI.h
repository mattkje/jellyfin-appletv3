// JFUI -- shared look (Jellyfin's dark theme) and the screen base class.
//
// Layout is written for a 1280x720 canvas; JFS() scales to the real interface
// size (BackRow uses 1280x720 or 1920x1080).
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "JFRootView.h"

extern CGFloat jf_scale;
static inline CGFloat JFS(CGFloat v) { return v * jf_scale; }

UIColor *JFColorBackground(void);   // #101010
UIColor *JFColorAccent(void);       // #00A4DC
UIColor *JFColorText(void);
UIColor *JFColorDim(void);
UIFont  *JFFont(CGFloat size, BOOL bold);
UILabel *JFLabel(CGFloat size, BOOL bold, UIColor *color);

// "2019 · 2h 14m · PG-13 · 7.8"
NSString *JFMetaLine(NSDictionary *item);
NSString *JFDisplayTitle(NSDictionary *item);     // "S1:E3 · Title" for episodes
double    JFPlayedFraction(NSDictionary *item);   // 0 when unwatched / no progress

@class JFScreen;

// The navigation stack owner (JFRootView).
@protocol JFNavigator <NSObject>
- (void)pushScreen:(JFScreen *)screen;
- (void)popScreen;
- (void)replaceWithScreen:(JFScreen *)screen;   // clears the stack
- (void)exitApp;
@end

@interface JFScreen : UIView
@property (nonatomic, weak) id<JFNavigator> nav;
- (void)screenDidAppear;        // also after returning from a pushed screen
- (void)screenWillDisappear;
- (void)arrow:(JFKey)k;         // repeats while held
- (void)key:(JFKey)k;           // Menu is handled by the host unless this returns YES from -handlesMenu
- (BOOL)handlesMenu;            // default NO: Menu pops this screen
@end

// Draws its image with UIKit in -drawRect: (aspect fill).  A UIImageView hands
// the CGImage to its layer, and inside BackRow's layer tree that comes out
// upside down; text and anything drawn in -drawRect: does not.
@interface JFImageView : UIView
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, assign) CGFloat cornerRadius;   // clipped while drawing, not by the layer
@end
