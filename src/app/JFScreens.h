// The app's screens.
#import "JFUI.h"

@interface JFConnectScreen : JFScreen          // find server, Quick Connect
@end

@interface JFHomeScreen : JFScreen             // backdrop hero + rows
@end

@interface JFLibraryScreen : JFScreen          // poster grid of one library / folder
- (instancetype)initWithFrame:(CGRect)frame library:(NSDictionary *)library;
@end

@interface JFDetailScreen : JFScreen           // movie / episode / series details
- (instancetype)initWithFrame:(CGRect)frame item:(NSDictionary *)item;
@end

@interface JFPlayerScreen : JFScreen           // full-screen playback
- (instancetype)initWithFrame:(CGRect)frame item:(NSDictionary *)item fromStart:(BOOL)fromStart;
@end

// Opens the right screen for an item (folder/library -> grid, else details).
void JFOpenItem(id<JFNavigator> nav, CGRect frame, NSDictionary *item);

// Fields every item request asks for.
extern NSString *const JFItemFields;
