#import "JFScreens.h"
#import "JFServer.h"
#import "JFLog.h"
#import <AVFoundation/AVFoundation.h>

// Full-screen playback with the Apple TV's hardware decoder (AVPlayer).
//
// The server is told what this box can play (PlaybackInfo + a device profile):
// H.264 up to 1080p / level 4.1 with AAC or AC-3, in MP4 directly, anything
// else as an HLS transcode.  Progress goes back every 10 seconds, so Continue
// Watching and resume points work everywhere.

static NSString *jf_clock(double secs) {
    if (!isfinite(secs) || secs < 0) secs = 0;
    long s = (long)secs;
    return s >= 3600 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", s / 3600, (s / 60) % 60, s % 60]
                     : [NSString stringWithFormat:@"%ld:%02ld", s / 60, s % 60];
}

// Seconds -> Jellyfin ticks; 0 while the player has no time yet (NaN).
static long long jf_ticks(double secs) { return isfinite(secs) && secs > 0 ? (long long)(secs * 1e7) : 0; }

static NSDictionary *jf_device_profile(void) {
    return @{
        @"Name": @"Apple TV 3",
        @"MaxStreamingBitrate": @12000000,
        @"MaxStaticBitrate": @40000000,
        @"DirectPlayProfiles": @[
            @{@"Container": @"mp4,m4v,mov", @"Type": @"Video", @"VideoCodec": @"h264", @"AudioCodec": @"aac,ac3"},
            @{@"Container": @"mp3,aac,m4a", @"Type": @"Audio"}],
        @"TranscodingProfiles": @[
            @{@"Container": @"ts", @"Type": @"Video", @"Protocol": @"hls", @"VideoCodec": @"h264",
              @"AudioCodec": @"aac,ac3", @"Context": @"Streaming", @"MaxAudioChannels": @"6",
              @"MinSegments": @"1", @"BreakOnNonKeyFrames": @YES},
            @{@"Container": @"aac", @"Type": @"Audio", @"AudioCodec": @"aac", @"Context": @"Streaming", @"Protocol": @"http"}],
        @"CodecProfiles": @[
            @{@"Type": @"Video", @"Codec": @"h264", @"Conditions": @[
                @{@"Condition": @"LessThanEqual", @"Property": @"VideoLevel", @"Value": @"41"},   // the A5 decoder refuses level 5.0 streams (AVFoundation -11848)
                @{@"Condition": @"LessThanEqual", @"Property": @"Width", @"Value": @"1920"},
                @{@"Condition": @"LessThanEqual", @"Property": @"Height", @"Value": @"1080"},
                @{@"Condition": @"LessThanEqual", @"Property": @"VideoBitDepth", @"Value": @"8"},
                @{@"Condition": @"NotEquals", @"Property": @"IsAnamorphic", @"Value": @"true"},
                @{@"Condition": @"EqualsAny", @"Property": @"VideoProfile", @"Value": @"high|main|baseline|constrained baseline"}]},
            @{@"Type": @"VideoAudio", @"Codec": @"aac,ac3", @"Conditions": @[
                @{@"Condition": @"LessThanEqual", @"Property": @"AudioChannels", @"Value": @"6"}]}],
        @"SubtitleProfiles": @[
            @{@"Format": @"vtt", @"Method": @"Hls"},
            @{@"Format": @"srt", @"Method": @"Encode"}, @{@"Format": @"ass", @"Method": @"Encode"},
            @{@"Format": @"ssa", @"Method": @"Encode"}, @{@"Format": @"pgssub", @"Method": @"Encode"}],
    };
}

@implementation JFPlayerScreen {
    NSDictionary *_item;
    BOOL _fromStart;
    AVPlayer *_player;
    AVPlayerLayer *_videoLayer;
    id _timeObserver;
    NSString *_mediaSourceId, *_playSessionId, *_playMethod;
    double _startSecs;
    BOOL _started, _stopped, _seekedToStart;
    NSTimer *_reportTimer, *_hudTimer;

    UIView *_hud;
    UILabel *_hudTitle, *_hudSub, *_elapsed, *_remaining, *_status;
    UIView *_bar, *_barFill;
    UIActivityIndicatorView *_spinner;
    double _pendingSeek;               // accumulated arrow seeking, seconds
    NSTimer *_seekTimer;
}

- (instancetype)initWithFrame:(CGRect)frame item:(NSDictionary *)item fromStart:(BOOL)fromStart {
    if ((self = [super initWithFrame:frame])) {
        _item = item;
        _fromStart = fromStart;
        self.backgroundColor = [UIColor blackColor];
        _startSecs = fromStart ? 0 : [item[@"UserData"][@"PlaybackPositionTicks"] longLongValue] / 1e7;

        _spinner = [[UIActivityIndicatorView alloc] initWithFrame:CGRectMake(0, 0, JFS(40), JFS(40))];
        _spinner.activityIndicatorViewStyle = UIActivityIndicatorViewStyleWhiteLarge;
        _spinner.center = CGPointMake(frame.size.width / 2, frame.size.height / 2);
        [_spinner startAnimating];
        [self addSubview:_spinner];

        _status = JFLabel(18, NO, JFColorDim());
        _status.textAlignment = NSTextAlignmentCenter;
        _status.numberOfLines = 2;
        _status.frame = CGRectMake(JFS(100), frame.size.height / 2 + JFS(40), frame.size.width - JFS(200), JFS(50));
        [self addSubview:_status];
        [self buildHud];
    }
    return self;
}

- (void)buildHud {
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    _hud = [[UIView alloc] initWithFrame:self.bounds];
    _hud.alpha = 0;
    CAGradientLayer *g = [CAGradientLayer layer];
    g.frame = self.bounds;
    g.colors = @[(id)[UIColor colorWithWhite:0 alpha:0.6].CGColor, (id)[UIColor clearColor].CGColor,
                 (id)[UIColor clearColor].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.85].CGColor];
    g.locations = @[@0, @0.22, @0.6, @1];
    [_hud.layer addSublayer:g];

    BOOL ep = [_item[@"Type"] isEqualToString:@"Episode"];
    _hudTitle = JFLabel(30, YES, JFColorText());
    _hudTitle.frame = CGRectMake(JFS(64), JFS(40), W - JFS(128), JFS(40));
    _hudTitle.text = ep ? _item[@"SeriesName"] : _item[@"Name"];
    [_hud addSubview:_hudTitle];
    _hudSub = JFLabel(18, NO, JFColorDim());
    _hudSub.frame = CGRectMake(JFS(64), JFS(82), W - JFS(128), JFS(26));
    _hudSub.text = ep ? JFDisplayTitle(_item) : JFMetaLine(_item);
    [_hud addSubview:_hudSub];

    _bar = [[UIView alloc] initWithFrame:CGRectMake(JFS(64), H - JFS(70), W - JFS(128), JFS(6))];
    _bar.backgroundColor = [UIColor colorWithWhite:1 alpha:0.25];
    _bar.layer.cornerRadius = JFS(3);
    [_hud addSubview:_bar];
    _barFill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, JFS(6))];
    _barFill.backgroundColor = JFColorAccent();
    _barFill.layer.cornerRadius = JFS(3);
    [_bar addSubview:_barFill];
    _elapsed = JFLabel(17, NO, JFColorText());
    _elapsed.frame = CGRectMake(JFS(64), H - JFS(56), JFS(200), JFS(24));
    [_hud addSubview:_elapsed];
    _remaining = JFLabel(17, NO, JFColorText());
    _remaining.textAlignment = NSTextAlignmentRight;
    _remaining.frame = CGRectMake(W - JFS(264), H - JFS(56), JFS(200), JFS(24));
    [_hud addSubview:_remaining];
    [self addSubview:_hud];
}

// ---- starting --------------------------------------------------------------------------

- (void)screenDidAppear {
    if (_started) return;
    _started = YES;
    JFServer *srv = [JFServer shared];
    NSDictionary *body = @{@"DeviceProfile": jf_device_profile(), @"MaxStreamingBitrate": @12000000,
                           @"AutoOpenLiveStream": @YES,   // resume by seeking: the HLS playlist covers the whole item
                           @"EnableDirectPlay": @YES, @"EnableDirectStream": @YES, @"EnableTranscoding": @YES,
                           @"AllowVideoStreamCopy": @YES, @"AllowAudioStreamCopy": @YES};
    [srv post:[NSString stringWithFormat:@"/Items/%@/PlaybackInfo", _item[@"Id"]]
        query:@{@"userId": srv.userId} body:body done:^(id json, NSError *e) {
        NSDictionary *src = [json[@"MediaSources"] firstObject];
        if (!src || self->_stopped) { [self fail:@"This item can't be played."]; return; }
        self->_mediaSourceId = src[@"Id"];
        self->_playSessionId = json[@"PlaySessionId"];
        NSString *url;
        if ([src[@"SupportsDirectPlay"] boolValue] || [src[@"SupportsDirectStream"] boolValue]) {
            self->_playMethod = [src[@"SupportsDirectPlay"] boolValue] ? @"DirectPlay" : @"DirectStream";
            url = [srv urlString:[NSString stringWithFormat:@"/Videos/%@/stream.%@", self->_item[@"Id"], src[@"Container"] ?: @"mp4"]
                           query:@{@"static": @"true", @"MediaSourceId": src[@"Id"], @"PlaySessionId": self->_playSessionId ?: @"",
                                   @"DeviceId": srv.deviceId}];
        } else if (src[@"TranscodingUrl"]) {
            self->_playMethod = @"Transcode";
            url = [srv.address stringByAppendingString:src[@"TranscodingUrl"]];
            if (![url containsString:@"api_key="] && ![url containsString:@"ApiKey="])
                url = [url stringByAppendingFormat:@"&api_key=%@", srv.token];
        } else { [self fail:@"The server can't stream this item in a format the Apple TV plays."]; return; }
        jf_log(@"play %@ (%@): %@", self->_item[@"Name"], self->_playMethod, url);
        [self startURL:[NSURL URLWithString:url]];
    }];
}

- (void)startURL:(NSURL *)url {
    _player = [AVPlayer playerWithURL:url];
    _videoLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
    _videoLayer.frame = self.bounds;
    _videoLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    [self.layer insertSublayer:_videoLayer atIndex:0];

    __weak JFPlayerScreen *w = self;
    _timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 2) queue:dispatch_get_main_queue()
                                                     usingBlock:^(CMTime t) { [w tick]; }];
    [_player.currentItem addObserver:self forKeyPath:@"status" options:0 context:NULL];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ended:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification object:_player.currentItem];
    [_player play];
    [self report:@"/Sessions/Playing"];
    _reportTimer = [NSTimer scheduledTimerWithTimeInterval:10 target:self selector:@selector(progressTick) userInfo:nil repeats:YES];
}

- (void)observeValueForKeyPath:(NSString *)k ofObject:(id)o change:(NSDictionary *)c context:(void *)ctx {
    AVPlayerItem *item = _player.currentItem;
    if (item.status == AVPlayerItemStatusReadyToPlay && !_seekedToStart) {
        _seekedToStart = YES;
        [_spinner stopAnimating];
        if (_startSecs > 5) [_player seekToTime:CMTimeMakeWithSeconds(_startSecs, 600)];
        [self showHud];
    } else if (item.status == AVPlayerItemStatusFailed) {
        jf_log(@"player failed: %@", item.error);
        [self fail:[NSString stringWithFormat:@"Playback failed: %@", item.error.localizedDescription]];
    }
}

- (void)fail:(NSString *)msg {
    [_spinner stopAnimating];
    _status.text = [msg stringByAppendingString:@"\nPress Menu to go back."];
}

- (double)position { return _player ? CMTimeGetSeconds(_player.currentTime) : 0; }
- (double)duration {
    double d = _player ? CMTimeGetSeconds(_player.currentItem.duration) : NAN;
    if (!isfinite(d)) d = [_item[@"RunTimeTicks"] longLongValue] / 1e7;
    return d;
}

- (void)tick {
    double pos = [self position] + _pendingSeek, dur = [self duration];
    pos = MAX(0, MIN(pos, dur > 0 ? dur : pos));
    _elapsed.text = jf_clock(pos);
    _remaining.text = dur > 0 ? [@"-" stringByAppendingString:jf_clock(dur - pos)] : @"";
    CGRect f = _barFill.frame;
    f.size.width = dur > 0 ? _bar.bounds.size.width * pos / dur : 0;
    _barFill.frame = f;
    if (_player.rate > 0 && [_spinner isAnimating] && _seekedToStart) [_spinner stopAnimating];
}

// ---- HUD and controls -------------------------------------------------------------------

- (void)showHud {
    [self tick];
    [UIView animateWithDuration:0.25 animations:^{ self->_hud.alpha = 1; }];
    [_hudTimer invalidate];
    _hudTimer = [NSTimer scheduledTimerWithTimeInterval:4 target:self selector:@selector(hideHud) userInfo:nil repeats:NO];
}
- (void)hideHud {
    if (_player.rate == 0 || _pendingSeek != 0) return;      // stays up while paused / seeking
    [UIView animateWithDuration:0.4 animations:^{ self->_hud.alpha = 0; }];
}

- (void)arrow:(JFKey)k {
    if (!_player) return;
    if (k == JFKeyLeft || k == JFKeyRight) {
        _pendingSeek += k == JFKeyRight ? 10 : -10;
        [self showHud];
        [_seekTimer invalidate];
        _seekTimer = [NSTimer scheduledTimerWithTimeInterval:0.6 target:self selector:@selector(commitSeek) userInfo:nil repeats:NO];
    } else {
        [self showHud];
    }
}

- (void)commitSeek {
    double target = MAX(0, [self position] + _pendingSeek);
    _pendingSeek = 0;
    [_player seekToTime:CMTimeMakeWithSeconds(target, 600) toleranceBefore:kCMTimeZero toleranceAfter:CMTimeMakeWithSeconds(1, 600)];
    [self showHud];
    [self report:@"/Sessions/Playing/Progress"];
}

- (void)key:(JFKey)k {
    if (!_player) return;
    if (k == JFKeySelect || k == JFKeyPlayPause) {
        if (_player.rate > 0) [_player pause]; else [_player play];
        [self showHud];
        [self report:@"/Sessions/Playing/Progress"];
    } else if (k == JFKeyForward || k == JFKeyRewind) {
        [self arrow:k == JFKeyForward ? JFKeyRight : JFKeyLeft];
    }
}

- (void)ended:(NSNotification *)n { [self.nav popScreen]; }

// ---- reporting ---------------------------------------------------------------------------

- (void)report:(NSString *)path {
    if (!_mediaSourceId) return;
    NSDictionary *body = @{@"ItemId": _item[@"Id"], @"MediaSourceId": _mediaSourceId, @"PlaySessionId": _playSessionId ?: @"",
                           @"PositionTicks": @(jf_ticks([self position])),
                           @"IsPaused": [NSNumber numberWithBool:_player.rate == 0],   // a JSON bool, not 0/1
                           @"CanSeek": @YES, @"PlayMethod": _playMethod ?: @"Transcode"};
    [[JFServer shared] post:path query:nil body:body done:nil];
}
- (void)progressTick { [self report:@"/Sessions/Playing/Progress"]; }

- (void)screenWillDisappear {
    if (_stopped) return;
    _stopped = YES;
    [self report:@"/Sessions/Playing/Stopped"];
    [_reportTimer invalidate];
    [_hudTimer invalidate];
    [_seekTimer invalidate];
    if (_timeObserver) [_player removeTimeObserver:_timeObserver];
    if (_player.currentItem) {
        [_player.currentItem removeObserver:self forKeyPath:@"status"];
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
    [_player pause];
    [_videoLayer removeFromSuperlayer];
    _player = nil;
}
@end
