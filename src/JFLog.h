// JFLog -- a log file the Mac can read over USB (AFC media folder), because the
// Apple TV keeps no syslog across restarts and HDMI is off while USB is in.
#import <Foundation/Foundation.h>

#define JF_MEDIA @"/var/mobile/Media"

// Appends one timestamped line to /var/mobile/Media/jf_log.txt (and NSLog).
void jf_log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
