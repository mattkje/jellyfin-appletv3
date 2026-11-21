// JFServer -- the Jellyfin server connection: discovery, Quick Connect sign-in,
// and JSON / image requests.  Every completion block runs on the main queue.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef void (^JFJSONBlock)(id json, NSError *error);

@interface JFServer : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) NSString *address;     // http://host:8096
@property (nonatomic, readonly) NSString *serverName;
@property (nonatomic, readonly) NSString *userId;
@property (nonatomic, readonly) NSString *userName;
@property (nonatomic, readonly) NSString *token;
@property (nonatomic, readonly) NSString *deviceId;
@property (nonatomic, readonly) BOOL signedIn;

// Checks the saved address still answers; otherwise finds a server with
// Jellyfin's LAN discovery (UDP 7359).  done(nil) when none is found.
- (void)findServer:(void (^)(NSString *name))done;

// Quick Connect: `codeBlock` gets the code to show on the TV; `done` fires once
// the user approved it in another Jellyfin client and sign-in finished.
- (void)startQuickConnect:(void (^)(NSString *code, NSError *error))codeBlock
                     done:(void (^)(NSError *error))done;
- (void)cancelQuickConnect;
- (void)signOut;
- (void)forgetServer;            // sign out and look for a server again

// Username / password sign-in (also used by the simulator screenshot tool).
- (void)useAddress:(NSString *)address;
- (void)signInWithUser:(NSString *)user password:(NSString *)password done:(void (^)(NSError *error))done;

- (void)get:(NSString *)path query:(NSDictionary *)query done:(JFJSONBlock)done;
- (void)post:(NSString *)path query:(NSDictionary *)query body:(id)body done:(JFJSONBlock)done;

- (NSURL *)imageURL:(NSString *)itemId type:(NSString *)type tag:(NSString *)tag maxWidth:(int)w;
- (NSString *)urlString:(NSString *)path query:(NSDictionary *)query;   // with api_key

@end

// In-memory image cache with request coalescing.
@interface JFImages : NSObject
+ (void)load:(NSURL *)url done:(void (^)(UIImage *img))done;
@end
