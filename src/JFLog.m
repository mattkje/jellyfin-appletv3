#import "JFLog.h"
#include <stdio.h>
#include <time.h>
#include <sys/time.h>

// Plain stdio: it is the simplest thing that keeps working in AppleTV.app's
// sandbox (an NSFileHandle version stopped appending after the first launch).
void jf_log(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[[NSString alloc] initWithFormat:fmt arguments:ap] autorelease];
    va_end(ap);
    NSLog(@"[Jellyfin] %@", msg);

    struct timeval tv;
    gettimeofday(&tv, NULL);
    struct tm tm;
    localtime_r(&tv.tv_sec, &tm);
    FILE *f = fopen("/var/mobile/Media/jf_log.txt", "a");
    if (!f) return;
    fprintf(f, "%02d:%02d:%02d.%03d %s\n", tm.tm_hour, tm.tm_min, tm.tm_sec, (int)(tv.tv_usec / 1000), msg.UTF8String);
    fclose(f);
}
