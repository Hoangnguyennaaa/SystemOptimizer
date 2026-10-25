#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <notify.h>
#import <spawn.h>
#import <sys/types.h>
#import <sys/socket.h>
#import <ifaddrs.h>
#import <net/if.h>

// MARK: - Global Preferences
static BOOL p_enabled = YES;
static BOOL p_showRAM = NO;
static BOOL p_hideStockWifi = NO;
static BOOL p_hideStockCellular = NO;
static BOOL p_hideStockBatteryPercent = YES;
static BOOL p_autoSpeed = YES;
static BOOL p_breathingGlow = YES;
static BOOL p_dotCount5 = NO; // NO: 4 chấm (chuẩn ảnh mẫu), YES: 5 chấm

static void loadPrefs(void) {
    NSString *prefPath = @"/var/jb/var/mobile/Library/Preferences/com.hoangnguyen.compactstatusbar.plist";
    if (![[NSFileManager defaultManager] fileExistsAtPath:prefPath]) {
        prefPath = @"/var/mobile/Library/Preferences/com.hoangnguyen.compactstatusbar.plist";
    }
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefPath];
    if (prefs) {
        p_enabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        p_showRAM = prefs[@"showRAM"] ? [prefs[@"showRAM"] boolValue] : NO;
        p_hideStockWifi = prefs[@"hideStockWifi"] ? [prefs[@"hideStockWifi"] boolValue] : NO;
        p_hideStockCellular = prefs[@"hideStockCellular"] ? [prefs[@"hideStockCellular"] boolValue] : NO;
        p_hideStockBatteryPercent = prefs[@"hideStockBatteryPercent"] ? [prefs[@"hideStockBatteryPercent"] boolValue] : YES;
        p_autoSpeed = prefs[@"autoSpeed"] ? [prefs[@"autoSpeed"] boolValue] : YES;
        p_breathingGlow = prefs[@"breathingGlow"] ? [prefs[@"breathingGlow"] boolValue] : YES;
        p_dotCount5 = prefs[@"dotCount5"] ? [prefs[@"dotCount5"] boolValue] : NO;
    }
}

// MARK: - Helper Functions (Network, RAM, Cellular, Wi-Fi)

// Custom if_data layout on Darwin to avoid missing <net/if_var.h> in iOS SDK
struct if_data_compact {
    u_char   ifi_type;
    u_char   ifi_typelen;
    u_char   ifi_physical;
    u_char   ifi_addrlen;
    u_char   ifi_hdrlen;
    u_char   ifi_recvquota;
    u_char   ifi_xmitquota;
    u_char   ifi_unused1;
    u_int32_t ifi_mtu;
    u_int32_t ifi_metric;
    u_int32_t ifi_baudrate;
    u_int32_t ifi_ipackets;
    u_int32_t ifi_ierrors;
    u_int32_t ifi_opackets;
    u_int32_t ifi_oerrors;
    u_int32_t ifi_collisions;
    u_int32_t ifi_ibytes;
    u_int32_t ifi_obytes;
};

static uint64_t getNetworkDownloadBytes(void) {
    struct ifaddrs *ifa_list = NULL;
    uint64_t totalBytes = 0;
    if (getifaddrs(&ifa_list) == 0) {
        for (struct ifaddrs *ifa = ifa_list; ifa != NULL; ifa = ifa->ifa_next) {
            if (ifa->ifa_addr && ifa->ifa_addr->sa_family == AF_LINK) {
                struct if_data_compact *ifd = (struct if_data_compact *)ifa->ifa_data;
                if (ifd) {
                    if (strncmp(ifa->ifa_name, "en", 2) == 0 || strncmp(ifa->ifa_name, "pdp_ip", 6) == 0) {
                        totalBytes += ifd->ifi_ibytes;
                    }
                }
            }
        }
        freeifaddrs(ifa_list);
    }
    return totalBytes;
}

static BOOL isWifiActive(void) {
    Class wifiClass = objc_getClass("SBWiFiManager");
    if (wifiClass && [wifiClass respondsToSelector:@selector(sharedInstance)]) {
        id wifiMgr = [wifiClass sharedInstance];
        if ([wifiMgr respondsToSelector:@selector(currentNetworkName)]) {
            NSString *name = [wifiMgr currentNetworkName];
            if (name && name.length > 0) return YES;
        }
        if ([wifiMgr respondsToSelector:@selector(isPowered)]) {
            return [wifiMgr isPowered];
        }
    }
    return YES;
}

static int getCellularSignalBars(void) {
    Class teleClass = objc_getClass("SBTelephonyManager");
    if (teleClass && [teleClass respondsToSelector:@selector(sharedTelephonyManager)]) {
        id teleMgr = [teleClass sharedTelephonyManager];
        if ([teleMgr respondsToSelector:@selector(signalStrengthBars)]) {
            return (int)[teleMgr signalStrengthBars];
        }
    }
    return 4;
}

static CGFloat getRAMUsedRatio(uint64_t *outUsedBytes, uint64_t *outTotalBytes) {
    uint64_t totalBytes = [NSProcessInfo processInfo].physicalMemory;
    if (totalBytes == 0) totalBytes = 3ULL * 1024ULL * 1024ULL * 1024ULL;
    if (outTotalBytes) *outTotalBytes = totalBytes;

    mach_msg_type_number_t count = (mach_msg_type_number_t)(sizeof(vm_statistics64_data_t) / sizeof(integer_t));
    vm_statistics64_data_t vmstat;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (integer_t *)&vmstat, &count) == KERN_SUCCESS) {
        vm_size_t pageSize = 16384;
        host_page_size(mach_host_self(), &pageSize);
        uint64_t freeBytes = (uint64_t)(vmstat.free_count + vmstat.inactive_count) * pageSize;
        uint64_t usedBytes = (totalBytes > freeBytes) ? (totalBytes - freeBytes) : (totalBytes / 2);
        if (outUsedBytes) *outUsedBytes = usedBytes;
        return (CGFloat)usedBytes / (CGFloat)totalBytes;
    }
    if (outUsedBytes) *outUsedBytes = totalBytes / 2;
    return 0.5;
}

// MARK: - Safe Method Swizzling
static void SafeSwizzle(Class cls, SEL origSel, IMP newImp, IMP *origImp) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, origSel);
    if (!m) return;

    BOOL added = class_addMethod(cls, origSel, newImp, method_getTypeEncoding(m));
    if (added) {
        if (origImp) *origImp = method_getImplementation(m);
    } else {
        if (origImp) *origImp = method_getImplementation(m);
        method_setImplementation(m, newImp);
    }
}

// MARK: - CompactStatusView: Vector 3-in-1 Gauge View
@interface CompactStatusView : UIView
@property (nonatomic, strong) CAShapeLayer *trackLayer;
@property (nonatomic, strong) CAShapeLayer *progressLayer;
@property (nonatomic, strong) CAShapeLayer *wifiDotLayer;
@property (nonatomic, strong) CAShapeLayer *wifiWave1Layer;
@property (nonatomic, strong) CAShapeLayer *wifiWave2Layer;
@property (nonatomic, strong) NSMutableArray<CAShapeLayer *> *dotLayers;
@property (nonatomic, strong) UILabel *centerLabel;

@property (nonatomic, assign) BOOL showRAM;
@property (nonatomic, assign) BOOL isBreathing;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) uint64_t lastDownloadBytes;
@property (nonatomic, assign) NSTimeInterval lastSampleTime;
@end

@implementation CompactStatusView

- (CGSize)intrinsicContentSize {
    return CGSizeMake(22.0, 22.0);
}

- (CGSize)sizeThatFits:(CGSize)size {
    return CGSizeMake(22.0, 22.0);
}

- (instancetype)initWithFrame:(CGRect)frame {
    CGRect sqFrame = CGRectMake(frame.origin.x, frame.origin.y, 22.0, 22.0);
    if (self = [super initWithFrame:sqFrame]) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.clipsToBounds = NO;
        self.showRAM = p_showRAM;

        [self setupLayers];
        [self setupGestures];

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        self.lastDownloadBytes = getNetworkDownloadBytes();
        self.lastSampleTime = [NSDate timeIntervalSinceReferenceDate];

        [self updateStats];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateStats) name:UIDeviceBatteryLevelDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateStats) name:UIDeviceBatteryStateDidChangeNotification object:nil];

        _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateStats) userInfo:nil repeats:YES];
    }
    return self;
}

- (void)setupLayers {
    CGPoint center = CGPointMake(11.0, 11.0);
    CGFloat radius = 9.2;
    CGFloat strokeWidth = 1.8;

    // 1. Vòng cung Pin / RAM (Outer Arc): quét 270 độ theo chiều kim đồng hồ từ 135 độ đến 45 độ
    CGFloat startAngle = 135.0 * M_PI / 180.0;
    CGFloat endAngle = 45.0 * M_PI / 180.0;
    UIBezierPath *arcPath = [UIBezierPath bezierPathWithArcCenter:center
                                                           radius:radius
                                                       startAngle:startAngle
                                                         endAngle:endAngle
                                                        clockwise:YES];

    _trackLayer = [CAShapeLayer layer];
    _trackLayer.fillColor = [UIColor clearColor].CGColor;
    _trackLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
    _trackLayer.lineWidth = strokeWidth;
    _trackLayer.lineCap = kCALineCapRound;
    _trackLayer.path = arcPath.CGPath;
    [self.layer addSublayer:_trackLayer];

    _progressLayer = [CAShapeLayer layer];
    _progressLayer.fillColor = [UIColor clearColor].CGColor;
    _progressLayer.lineWidth = strokeWidth;
    _progressLayer.lineCap = kCALineCapRound;
    _progressLayer.path = arcPath.CGPath;
    _progressLayer.strokeEnd = 1.0;
    [self.layer addSublayer:_progressLayer];

    // 2. Wi-Fi ở tâm (Center Wi-Fi): Tâm phát sóng tại (11.0, 13.5)
    CGPoint wifiOrigin = CGPointMake(11.0, 13.5);

    // Chấm gốc tâm Wi-Fi
    UIBezierPath *baseDotPath = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(11.0 - 0.9, 13.0 - 0.9, 1.8, 1.8)];
    _wifiDotLayer = [CAShapeLayer layer];
    _wifiDotLayer.fillColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
    _wifiDotLayer.path = baseDotPath.CGPath;
    [self.layer addSublayer:_wifiDotLayer];

    CGFloat startWifi = 225.0 * M_PI / 180.0;
    CGFloat endWifi = 315.0 * M_PI / 180.0;

    // Vòng sóng 1 (trong)
    UIBezierPath *w1 = [UIBezierPath bezierPathWithArcCenter:wifiOrigin radius:3.2 startAngle:startWifi endAngle:endWifi clockwise:YES];
    _wifiWave1Layer = [CAShapeLayer layer];
    _wifiWave1Layer.fillColor = [UIColor clearColor].CGColor;
    _wifiWave1Layer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
    _wifiWave1Layer.lineWidth = 1.1;
    _wifiWave1Layer.lineCap = kCALineCapRound;
    _wifiWave1Layer.path = w1.CGPath;
    [self.layer addSublayer:_wifiWave1Layer];

    // Vòng sóng 2 (ngoài)
    UIBezierPath *w2 = [UIBezierPath bezierPathWithArcCenter:wifiOrigin radius:5.6 startAngle:startWifi endAngle:endWifi clockwise:YES];
    _wifiWave2Layer = [CAShapeLayer layer];
    _wifiWave2Layer.fillColor = [UIColor clearColor].CGColor;
    _wifiWave2Layer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
    _wifiWave2Layer.lineWidth = 1.1;
    _wifiWave2Layer.lineCap = kCALineCapRound;
    _wifiWave2Layer.path = w2.CGPath;
    [self.layer addSublayer:_wifiWave2Layer];

    // 3. Nhãn hiển thị tốc độ mạng / 4G ở tâm (Center Label)
    _centerLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 6.0, 22.0, 10.0)];
    _centerLabel.font = [UIFont systemFontOfSize:6.5 weight:UIFontWeightBold];
    _centerLabel.textColor = [UIColor whiteColor];
    _centerLabel.textAlignment = NSTextAlignmentCenter;
    _centerLabel.hidden = YES;
    [self addSubview:_centerLabel];

    // 4. Các chấm sóng di động ở đáy
    [self rebuildCellularDots];
}

- (void)rebuildCellularDots {
    if (_dotLayers) {
        for (CAShapeLayer *l in _dotLayers) [l removeFromSuperlayer];
    }
    _dotLayers = [NSMutableArray array];

    CGPoint center = CGPointMake(11.0, 11.0);
    CGFloat radius = 9.2;
    BOOL is5 = p_dotCount5;
    // Góc quét từ trái qua phải theo đường tròn đáy
    NSArray *angles = is5 ? @[@(122.0), @(106.0), @(90.0), @(74.0), @(58.0)]
                          : @[@(122.0), @(101.0), @(79.0), @(58.0)];
    CGFloat dr = is5 ? 0.75 : 0.85;

    for (NSNumber *degNum in angles) {
        CGFloat deg = [degNum doubleValue];
        CGFloat rad = deg * M_PI / 180.0;
        CGFloat dx = center.x + radius * cos(rad);
        CGFloat dy = center.y + radius * sin(rad);
        UIBezierPath *dp = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(dx - dr, dy - dr, dr * 2.0, dr * 2.0)];
        CAShapeLayer *dl = [CAShapeLayer layer];
        dl.path = dp.CGPath;
        dl.fillColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
        [self.layer addSublayer:dl];
        [_dotLayers addObject:dl];
    }
}

- (void)setupGestures {
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap)];
    doubleTap.numberOfTapsRequired = 2;
    [self addGestureRecognizer:doubleTap];

    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap)];
    singleTap.numberOfTapsRequired = 1;
    [singleTap requireGestureRecognizerToFail:doubleTap];
    [self addGestureRecognizer:singleTap];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.6;
    [self addGestureRecognizer:longPress];
}

// MARK: - Gestures
- (void)handleDoubleTap {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
    self.showRAM = !self.showRAM;
    [self updateStats];
}

- (void)handleSingleTap {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];

    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;

    UIView *existingHUD = [keyWindow viewWithTag:998822];
    if (existingHUD) {
        [UIView animateWithDuration:0.2 animations:^{
            existingHUD.alpha = 0.0;
        } completion:^(BOOL finished) {
            [existingHUD removeFromSuperview];
        }];
        return;
    }

    float rawBat = [UIDevice currentDevice].batteryLevel;
    int batPercent = (rawBat < 0) ? 100 : (int)(rawBat * 100);
    BOOL charging = ([UIDevice currentDevice].batteryState == UIDeviceBatteryStateCharging || [UIDevice currentDevice].batteryState == UIDeviceBatteryStateFull);

    uint64_t ramUsed = 0, ramTotal = 0;
    getRAMUsedRatio(&ramUsed, &ramTotal);
    double ramUsedGB = (double)ramUsed / 1073741824.0;
    double ramTotalGB = (double)ramTotal / 1073741824.0;
    int ramPercent = (int)((double)ramUsed / (double)ramTotal * 100);

    NSString *netStr = isWifiActive() ? @"Wi-Fi" : @"4G/LTE";

    CGFloat hudW = 230.0;
    CGFloat hudH = 34.0;
    CGFloat hudX = (keyWindow.bounds.size.width - hudW) / 2.0;
    CGFloat hudY = 48.0;

    UIVisualEffectView *hud = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    hud.frame = CGRectMake(hudX, hudY, hudW, hudH);
    hud.layer.cornerRadius = 17.0;
    hud.layer.masksToBounds = YES;
    hud.tag = 998822;
    hud.alpha = 0.0;

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, hudW - 20, hudH)];
    titleLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightMedium];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 1;
    titleLabel.text = [NSString stringWithFormat:@"🔋 %d%%%@  |  🧠 %.1f/%.0fGB (%d%%)  |  📶 %@",
                       batPercent, charging ? @"⚡" : @"",
                       ramUsedGB, ramTotalGB, ramPercent,
                       netStr];
    [hud.contentView addSubview:titleLabel];
    [keyWindow addSubview:hud];

    [UIView animateWithDuration:0.25 animations:^{
        hud.alpha = 1.0;
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.25 animations:^{
            hud.alpha = 0.0;
        } completion:^(BOOL finished) {
            [hud removeFromSuperview];
        }];
    });
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
        [feedback impactOccurred];

        Class lmClass = objc_getClass("SBLockScreenManager");
        if (lmClass && [lmClass respondsToSelector:@selector(sharedInstance)]) {
            id mgr = [lmClass sharedInstance];
            if ([mgr respondsToSelector:@selector(lockUIFromSource:withOptions:)]) {
                [mgr lockUIFromSource:1 withOptions:nil];
            }
        }
    }
}

// MARK: - Update Statistics (1-second cycle)
- (void)updateStats {
    float rawLevel = [UIDevice currentDevice].batteryLevel;
    CGFloat bat = rawLevel < 0 ? 1.0 : (CGFloat)rawLevel;
    UIDeviceBatteryState bState = [UIDevice currentDevice].batteryState;
    BOOL charging = (bState == UIDeviceBatteryStateCharging || bState == UIDeviceBatteryStateFull);
    BOOL lowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;

    CGFloat ramRatio = getRAMUsedRatio(NULL, NULL);

    // 1. Tiến trình & Màu sắc vòng cung ngoài
    CGFloat progressVal = self.showRAM ? MIN(MAX(ramRatio, 0.0), 1.0) : bat;
    _progressLayer.strokeEnd = progressVal;

    UIColor *col = [UIColor colorWithWhite:1.0 alpha:0.95];
    if (self.showRAM) {
        if (ramRatio > 0.85) col = [UIColor colorWithRed:1.0 green:0.25 blue:0.25 alpha:1.0];
        else if (ramRatio > 0.65) col = [UIColor colorWithRed:1.0 green:0.60 blue:0.10 alpha:1.0];
        else col = [UIColor colorWithRed:0.20 green:0.80 blue:1.0 alpha:1.0];
    } else {
        if (charging) {
            col = [UIColor colorWithRed:0.20 green:0.85 blue:0.35 alpha:1.0];
        } else if (lowPower) {
            col = [UIColor colorWithRed:1.0 green:0.82 blue:0.0 alpha:1.0];
        } else if (bat <= 0.20) {
            col = [UIColor colorWithRed:1.0 green:0.25 blue:0.25 alpha:1.0];
        }
    }
    _progressLayer.strokeColor = col.CGColor;

    // 2. Hiệu ứng Breathing Glow khi đang sạc
    if (charging && p_breathingGlow) {
        if (!self.isBreathing) {
            _progressLayer.shadowColor = col.CGColor;
            _progressLayer.shadowRadius = 4.0;
            _progressLayer.shadowOffset = CGSizeZero;
            CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
            pulse.duration = 1.2;
            pulse.fromValue = @(0.2);
            pulse.toValue = @(0.95);
            pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            pulse.autoreverses = YES;
            pulse.repeatCount = HUGE_VALF;
            [_progressLayer addAnimation:pulse forKey:@"breathingGlow"];
            self.isBreathing = YES;
        }
    } else {
        if (self.isBreathing) {
            [_progressLayer removeAnimationForKey:@"breathingGlow"];
            _progressLayer.shadowOpacity = 0.0;
            self.isBreathing = NO;
        }
    }

    // 3. Tốc độ mạng thời gian thực (> 100 KB/s)
    uint64_t currentBytes = getNetworkDownloadBytes();
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    double speed = 0.0;
    if (self.lastSampleTime > 0 && now > self.lastSampleTime) {
        double dt = now - self.lastSampleTime;
        uint64_t deltaBytes = (currentBytes >= self.lastDownloadBytes) ? (currentBytes - self.lastDownloadBytes) : 0;
        speed = (double)deltaBytes / dt;
    }
    self.lastDownloadBytes = currentBytes;
    self.lastSampleTime = now;

    BOOL wifiOn = isWifiActive();

    if (p_autoSpeed && speed > 100000.0) {
        _wifiDotLayer.hidden = YES;
        _wifiWave1Layer.hidden = YES;
        _wifiWave2Layer.hidden = YES;
        _centerLabel.hidden = NO;

        if (speed >= 1048576.0) {
            _centerLabel.text = [NSString stringWithFormat:@"%.1fM", speed / 1048576.0];
        } else {
            _centerLabel.text = [NSString stringWithFormat:@"%dK", (int)(speed / 1024.0)];
        }
        _centerLabel.textColor = [UIColor colorWithRed:0.25 green:0.90 blue:0.40 alpha:1.0];
    } else if (wifiOn) {
        _centerLabel.hidden = YES;
        _wifiDotLayer.hidden = NO;
        _wifiWave1Layer.hidden = NO;
        _wifiWave2Layer.hidden = NO;
        _wifiDotLayer.opacity = 1.0;
        _wifiWave1Layer.opacity = 1.0;
        _wifiWave2Layer.opacity = 1.0;
    } else {
        _wifiDotLayer.hidden = YES;
        _wifiWave1Layer.hidden = YES;
        _wifiWave2Layer.hidden = YES;
        _centerLabel.hidden = NO;
        _centerLabel.text = @"4G";
        _centerLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.90];
    }

    // 4. Các chấm sóng di động ở đáy
    int cellBars = getCellularSignalBars();
    int totalDots = (int)_dotLayers.count;
    int litCount = 0;
    if (totalDots == 4) {
        litCount = MIN(MAX(cellBars, 0), 4);
    } else {
        if (cellBars >= 4) litCount = 5;
        else if (cellBars == 3) litCount = 4;
        else if (cellBars == 2) litCount = 2;
        else if (cellBars == 1) litCount = 1;
        else litCount = 0;
    }

    for (int i = 0; i < totalDots; i++) {
        CAShapeLayer *dot = _dotLayers[i];
        BOOL isLit = (i < litCount);
        dot.fillColor = isLit ? [UIColor colorWithWhite:1.0 alpha:0.95].CGColor
                              : [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
    }
}

- (void)dealloc {
    [_timer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

// MARK: - Hooks for SpringBoard Status Bar Items

static void (*orig_battery_didMoveToWindow)(UIView *, SEL) = NULL;
static void hooked_battery_didMoveToWindow(UIView *self, SEL _cmd) {
    if (orig_battery_didMoveToWindow) {
        orig_battery_didMoveToWindow(self, _cmd);
    }
    if (!self.window || !p_enabled) return;

    self.hidden = YES;
    self.alpha = 0.0;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *parent = self.superview;
        if (parent) {
            CompactStatusView *custom = (CompactStatusView *)[parent viewWithTag:998811];
            if (!custom) {
                custom = [[CompactStatusView alloc] initWithFrame:CGRectMake(0, 0, 22.0, 22.0)];
                custom.tag = 998811;
                [parent addSubview:custom];
            }
            custom.center = self.center;
            [parent bringSubviewToFront:custom];
        }
    });
}

static void (*orig_battery_layoutSubviews)(UIView *, SEL) = NULL;
static void hooked_battery_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_battery_layoutSubviews) {
        orig_battery_layoutSubviews(self, _cmd);
    }
    if (p_enabled) {
        self.hidden = YES;
        self.alpha = 0.0;
        UIView *parent = self.superview;
        if (parent) {
            UIView *custom = [parent viewWithTag:998811];
            if (custom) {
                custom.center = self.center;
            }
        }
    }
}

static void (*orig_wifi_didMoveToWindow)(UIView *, SEL) = NULL;
static void hooked_wifi_didMoveToWindow(UIView *self, SEL _cmd) {
    if (orig_wifi_didMoveToWindow) orig_wifi_didMoveToWindow(self, _cmd);
    if (p_enabled && p_hideStockWifi) {
        self.hidden = YES;
        self.alpha = 0.0;
    }
}

static void (*orig_cell_didMoveToWindow)(UIView *, SEL) = NULL;
static void hooked_cell_didMoveToWindow(UIView *self, SEL _cmd) {
    if (orig_cell_didMoveToWindow) orig_cell_didMoveToWindow(self, _cmd);
    if (p_enabled && p_hideStockCellular) {
        self.hidden = YES;
        self.alpha = 0.0;
    }
}

static void (*orig_setText)(id, SEL, NSString *) = NULL;
static void hooked_setText(id self, SEL _cmd, NSString *text) {
    if (p_enabled && p_hideStockBatteryPercent && text && [text containsString:@"%"]) {
        ((UIView *)self).hidden = YES;
        ((UIView *)self).alpha = 0.0;
        return;
    }
    if (orig_setText) {
        orig_setText(self, _cmd, text);
    }
}

// MARK: - Notifications
static void handleRespringNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    pid_t pid;
    const char *args[] = {"killall", "-9", "SpringBoard", NULL};
    posix_spawn(&pid, "/var/jb/usr/bin/killall", NULL, NULL, (char *const *)args, NULL);
    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)args, NULL);
}

static void handleReloadNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    loadPrefs();
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (keyWindow) {
            CompactStatusView *custom = (CompactStatusView *)[keyWindow viewWithTag:998811];
            if (custom) {
                [custom rebuildCellularDots];
                [custom updateStats];
            }
        }
    });
}

// MARK: - Constructor
__attribute__((constructor)) static void initCompactStatusBarTweak(void) {
    loadPrefs();

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)handleReloadNotification,
        CFSTR("com.hoangnguyen.compactstatusbar/ReloadPrefs"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)handleRespringNotification,
        CFSTR("com.hoangnguyen.compactstatusbar/Respring"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );

    // 1. Hook Battery View
    Class bClass = objc_getClass("_UIBatteryView");
    if (bClass) {
        SafeSwizzle(bClass, @selector(didMoveToWindow), (IMP)hooked_battery_didMoveToWindow, (IMP *)&orig_battery_didMoveToWindow);
        SafeSwizzle(bClass, @selector(layoutSubviews), (IMP)hooked_battery_layoutSubviews, (IMP *)&orig_battery_layoutSubviews);
    }

    Class legacyBClass = objc_getClass("UIStatusBarBatteryItemView");
    if (legacyBClass) {
        SafeSwizzle(legacyBClass, @selector(didMoveToWindow), (IMP)hooked_battery_didMoveToWindow, (IMP *)&orig_battery_didMoveToWindow);
        SafeSwizzle(legacyBClass, @selector(layoutSubviews), (IMP)hooked_battery_layoutSubviews, (IMP *)&orig_battery_layoutSubviews);
    }

    // 2. Hook Stock Wi-Fi View
    Class wifiClass = objc_getClass("_UIStatusBarWifiSignalView");
    if (wifiClass) {
        SafeSwizzle(wifiClass, @selector(didMoveToWindow), (IMP)hooked_wifi_didMoveToWindow, (IMP *)&orig_wifi_didMoveToWindow);
    }
    Class legacyWifiClass = objc_getClass("UIStatusBarDataNetworkItemView");
    if (legacyWifiClass) {
        SafeSwizzle(legacyWifiClass, @selector(didMoveToWindow), (IMP)hooked_wifi_didMoveToWindow, (IMP *)&orig_wifi_didMoveToWindow);
    }

    // 3. Hook Stock Cellular View
    Class cellClass = objc_getClass("_UIStatusBarCellularSignalView");
    if (cellClass) {
        SafeSwizzle(cellClass, @selector(didMoveToWindow), (IMP)hooked_cell_didMoveToWindow, (IMP *)&orig_cell_didMoveToWindow);
    }
    Class legacyCellClass = objc_getClass("UIStatusBarSignalStrengthItemView");
    if (legacyCellClass) {
        SafeSwizzle(legacyCellClass, @selector(didMoveToWindow), (IMP)hooked_cell_didMoveToWindow, (IMP *)&orig_cell_didMoveToWindow);
    }

    // 4. Hook String View (% text)
    Class stringViewClass = objc_getClass("_UIStatusBarStringView");
    if (stringViewClass) {
        SafeSwizzle(stringViewClass, @selector(setText:), (IMP)hooked_setText, (IMP *)&orig_setText);
    }
}
