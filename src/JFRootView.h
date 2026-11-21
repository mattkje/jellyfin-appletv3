// JFRootView -- the full-screen UIKit view the appliance shows.  It is not in a
// UIWindow (BackRow owns the window), so input arrives through -arrow:/-key:
// from the appliance's remote handler instead of UIKit events.
#import <UIKit/UIKit.h>

typedef enum {
    JFKeyNone, JFKeyUp, JFKeyDown, JFKeyLeft, JFKeyRight,
    JFKeySelect, JFKeySelectHold, JFKeyPlayPause, JFKeyMenu, JFKeyMenuHold,
    JFKeyForward, JFKeyRewind
} JFKey;

@interface JFRootView : UIView
@property (nonatomic, copy) void (^onExit)(void);
- (void)didAppear;
- (void)willDisappear;
- (void)arrow:(JFKey)k pressed:(BOOL)pressed;   // press starts auto-repeat, release stops it
- (void)key:(JFKey)k;
@end
