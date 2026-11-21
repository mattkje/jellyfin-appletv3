#import "JFLog.h"

void jf_log(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[[NSString alloc] initWithFormat:fmt arguments:ap] autorelease];
    va_end(ap);
    NSLog(@"[Jellyfin] %@", msg);

    static NSDateFormatter *df;
    if (!df) { df = [[NSDateFormatter alloc] init]; df.dateFormat = @"HH:mm:ss.SSS"; }
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [df stringFromDate:[NSDate date]], msg];
    NSString *path = [JF_MEDIA stringByAppendingPathComponent:@"jf_log.txt"];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!h) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        h = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    [h seekToEndOfFile];
    [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
}
