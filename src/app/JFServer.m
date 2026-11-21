#import "JFServer.h"
#import "JFLog.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

#define JF_SETTINGS @"/var/mobile/Library/Preferences/org.jellyfin.atv3.plist"
#define JF_CLIENT   @"Jellyfin for Apple TV 3"
#define JF_VERSION  @"0.1.0"

@interface JFServer ()
@property (nonatomic, strong) NSMutableDictionary *settings;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, assign) BOOL qcCancelled;
@end

@implementation JFServer

+ (instancetype)shared {
    static JFServer *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[JFServer alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _settings = [NSMutableDictionary dictionaryWithContentsOfFile:JF_SETTINGS] ?: [NSMutableDictionary dictionary];
        if (!_settings[@"DeviceId"]) {
            _settings[@"DeviceId"] = [[NSUUID UUID] UUIDString];
            [self save];
        }
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 20;
        cfg.HTTPMaximumConnectionsPerHost = 6;
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

- (void)save { [self.settings writeToFile:JF_SETTINGS atomically:YES]; }

- (NSString *)address    { return self.settings[@"Address"]; }
- (NSString *)serverName { return self.settings[@"ServerName"]; }
- (NSString *)userId     { return self.settings[@"UserId"]; }
- (NSString *)userName   { return self.settings[@"UserName"]; }
- (NSString *)token      { return self.settings[@"Token"]; }
- (NSString *)deviceId   { return self.settings[@"DeviceId"]; }
- (BOOL)signedIn         { return self.token.length && self.userId.length; }

- (NSString *)authHeader {
    NSMutableString *h = [NSMutableString stringWithFormat:
        @"MediaBrowser Client=\"%@\", Device=\"Apple TV\", DeviceId=\"%@\", Version=\"%@\"",
        JF_CLIENT, self.deviceId, JF_VERSION];
    if (self.token.length) [h appendFormat:@", Token=\"%@\"", self.token];
    return h;
}

// ---- requests ---------------------------------------------------------------------------

static NSString *jf_escape(NSString *s) {
    NSMutableCharacterSet *ok = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    [ok removeCharactersInString:@"&=+?/,"];
    return [s stringByAddingPercentEncodingWithAllowedCharacters:ok];
}

- (NSString *)queryString:(NSDictionary *)q {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *k in q) {
        id v = q[k];
        NSString *sv = [v isKindOfClass:[NSString class]] ? v : [v description];
        [parts addObject:[NSString stringWithFormat:@"%@=%@", jf_escape(k), jf_escape(sv)]];
    }
    return [parts componentsJoinedByString:@"&"];
}

- (NSURL *)url:(NSString *)path query:(NSDictionary *)query {
    NSString *s = [self.address stringByAppendingString:path];
    if (query.count) s = [s stringByAppendingFormat:@"?%@", [self queryString:query]];
    return [NSURL URLWithString:s];
}

- (NSString *)urlString:(NSString *)path query:(NSDictionary *)query {
    NSMutableDictionary *q = [query mutableCopy] ?: [NSMutableDictionary dictionary];
    if (self.token) q[@"api_key"] = self.token;
    return [[self url:path query:q] absoluteString];
}

- (void)send:(NSString *)method path:(NSString *)path query:(NSDictionary *)query body:(id)body done:(JFJSONBlock)done {
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:[self url:path query:query]];
    r.HTTPMethod = method;
    [r setValue:[self authHeader] forHTTPHeaderField:@"Authorization"];
    [r setValue:[self authHeader] forHTTPHeaderField:@"X-Emby-Authorization"];
    [r setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if (body) {
        r.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
        [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    [[self.session dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger status = [(NSHTTPURLResponse *)resp statusCode];
        id json = nil;
        if (!err && (status < 200 || status >= 300))
            err = [NSError errorWithDomain:@"Jellyfin" code:status
                                  userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)status]}];
        if (!err && data.length) json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if (err) jf_log(@"%@ %@ failed: %@", method, path, err.localizedDescription);
        if (done) dispatch_async(dispatch_get_main_queue(), ^{ done(json, err); });
    }] resume];
}

- (void)get:(NSString *)path query:(NSDictionary *)query done:(JFJSONBlock)done {
    [self send:@"GET" path:path query:query body:nil done:done];
}
- (void)post:(NSString *)path query:(NSDictionary *)query body:(id)body done:(JFJSONBlock)done {
    [self send:@"POST" path:path query:query body:body done:done];
}

- (NSURL *)imageURL:(NSString *)itemId type:(NSString *)type tag:(NSString *)tag maxWidth:(int)w {
    if (!itemId) return nil;
    NSMutableDictionary *q = [@{@"maxWidth": @(w), @"quality": @85} mutableCopy];
    if (tag) q[@"tag"] = tag;
    return [self url:[NSString stringWithFormat:@"/Items/%@/Images/%@", itemId, type] query:q];
}

// ---- finding the server -------------------------------------------------------------

// Jellyfin answers "who is JellyfinServer?" on UDP 7359 with its address.
static NSArray *jf_discover_blocking(void) {
    NSMutableArray *found = [NSMutableArray array];
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return found;
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, sizeof yes);
    struct timeval tv = {2, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    struct sockaddr_in to = {0};
    to.sin_len = sizeof to;
    to.sin_family = AF_INET;
    to.sin_port = htons(7359);
    to.sin_addr.s_addr = htonl(INADDR_BROADCAST);
    const char *msg = "who is JellyfinServer?";
    sendto(fd, msg, strlen(msg), 0, (struct sockaddr *)&to, sizeof to);
    char buf[2048];
    for (;;) {
        ssize_t n = recv(fd, buf, sizeof buf, 0);
        if (n <= 0) break;
        id json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:buf length:n] options:0 error:NULL];
        if ([json isKindOfClass:[NSDictionary class]] && json[@"Address"]) [found addObject:json];
    }
    close(fd);
    return found;
}

- (void)findServer:(void (^)(NSString *name))done {
    NSString *addr = self.address;
    if (!addr) { [self discoverThen:done]; return; }
    [self get:@"/System/Info/Public" query:nil done:^(id json, NSError *err) {
        if (!err && json[@"ServerName"]) {
            self.settings[@"Address"] = addr;
            self.settings[@"ServerName"] = json[@"ServerName"];
            [self save];
            jf_log(@"server %@ at %@ (%@)", json[@"ServerName"], addr, json[@"Version"]);
            done(json[@"ServerName"]);
            return;
        }
        [self discoverThen:done];
    }];
}

- (void)discoverThen:(void (^)(NSString *name))done {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            NSArray *servers = jf_discover_blocking();
            dispatch_async(dispatch_get_main_queue(), ^{
                NSDictionary *s = servers.firstObject;
                jf_log(@"discovery found %lu server(s)", (unsigned long)servers.count);
                if (!s) { done(nil); return; }
                self.settings[@"Address"] = s[@"Address"];
                self.settings[@"ServerName"] = s[@"Name"] ?: @"Jellyfin";
                [self save];
                done(self.serverName);
            });
        });
}

// ---- Quick Connect ------------------------------------------------------------------

- (void)startQuickConnect:(void (^)(NSString *, NSError *))codeBlock done:(void (^)(NSError *))done {
    self.qcCancelled = NO;
    [self post:@"/QuickConnect/Initiate" query:nil body:nil done:^(id json, NSError *err) {
        NSString *secret = json[@"Secret"];
        if (err || !secret) { codeBlock(nil, err ?: [NSError errorWithDomain:@"Jellyfin" code:1 userInfo:nil]); return; }
        codeBlock(json[@"Code"], nil);
        [self pollQuickConnect:secret done:done];
    }];
}

- (void)pollQuickConnect:(NSString *)secret done:(void (^)(NSError *))done {
    if (self.qcCancelled) return;
    [self get:@"/QuickConnect/Connect" query:@{@"secret": secret} done:^(id json, NSError *err) {
        if (self.qcCancelled) return;
        if ([json[@"Authenticated"] boolValue]) {
            [self post:@"/Users/AuthenticateWithQuickConnect" query:nil body:@{@"Secret": secret} done:^(id auth, NSError *e2) {
                if (e2 || !auth[@"AccessToken"]) { done(e2 ?: [NSError errorWithDomain:@"Jellyfin" code:2 userInfo:nil]); return; }
                self.settings[@"Token"] = auth[@"AccessToken"];
                self.settings[@"UserId"] = auth[@"User"][@"Id"];
                self.settings[@"UserName"] = auth[@"User"][@"Name"];
                [self save];
                jf_log(@"signed in as %@", self.userName);
                done(nil);
            }];
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self pollQuickConnect:secret done:done];
        });
    }];
}

- (void)cancelQuickConnect { self.qcCancelled = YES; }

- (void)signOut {
    [self.settings removeObjectsForKeys:@[@"Token", @"UserId", @"UserName"]];
    [self save];
}

@end

// ---- images ---------------------------------------------------------------------------

@implementation JFImages

static NSCache *s_cache;
static NSMutableDictionary *s_waiting;   // url -> array of blocks

+ (void)load:(NSURL *)url done:(void (^)(UIImage *))done {
    if (!url) { done(nil); return; }
    if (!s_cache) {
        s_cache = [[NSCache alloc] init];
        s_cache.totalCostLimit = 40 * 1024 * 1024;   // decoded bytes
        s_waiting = [NSMutableDictionary dictionary];
    }
    UIImage *hit = [s_cache objectForKey:url];
    if (hit) { done(hit); return; }
    NSMutableArray *w = s_waiting[url];
    if (w) { [w addObject:[done copy]]; return; }
    s_waiting[url] = [NSMutableArray arrayWithObject:[done copy]];
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
        // Decode off the main thread so scrolling stays smooth.
        UIImage *img = nil;
        if (data) {
            UIImage *raw = [UIImage imageWithData:data];
            if (raw) {
                UIGraphicsBeginImageContextWithOptions(raw.size, YES, 1);
                [raw drawAtPoint:CGPointZero];
                img = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (img) [s_cache setObject:img forKey:url cost:(NSUInteger)(img.size.width * img.size.height * 4)];
            NSArray *blocks = s_waiting[url];
            [s_waiting removeObjectForKey:url];
            for (void (^b)(UIImage *) in blocks) b(img);
        });
    }] resume];
}

@end
