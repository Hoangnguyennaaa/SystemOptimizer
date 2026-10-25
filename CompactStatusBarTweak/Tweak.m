#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <notify.h>
#import <spawn.h>
#import <unistd.h>
#import <sys/types.h>
#import <sys/socket.h>
#import <ifaddrs.h>
#import <net/if.h>

// MARK: - Protocols for Runtime SpringBoard Classes (No linker dependency)
@protocol SBWiFiManagerProtocol <NSObject>
- (NSString *)currentNetworkName;
- (BOOL)isPowered;
- (int)signalStrengthBars;
@end

@protocol SBTelephonyManagerProtocol <NSObject>
- (int)signalStrengthBars;
@end

@protocol SBLockScreenManagerProtocol <NSObject>
- (void)lockUIFromSource:(int)source withOptions:(id)options;
@end

@protocol SBControlCenterControllerProtocol <NSObject>
- (void)presentAnimated:(BOOL)animated;
@end

// Custom if_data layout on Darwin to avoid missing <net/if_var.h> in iOS SDK
struct if_data_compact {
    uint8_t   ifi_type;
    uint8_t   ifi_typelen;
    uint8_t   ifi_physical;
    uint8_t   ifi_addrlen;
    uint8_t   ifi_hdrlen;
    uint8_t   ifi_recvquota;
    uint8_t   ifi_xmitquota;
    uint8_t   ifi_unused1;
    uint32_t  ifi_mtu;
    uint32_t  ifi_metric;
    uint32_t  ifi_baudrate;
    uint32_t  ifi_ipackets;
    uint32_t  ifi_ierrors;
    uint32_t  ifi_opackets;
    uint32_t  ifi_oerrors;
    uint32_t  ifi_collisions;
    uint32_t  ifi_ibytes;
    uint32_t  ifi_obytes;
};

// MARK: - Global Preferences
static BOOL p_enabled = YES;
static BOOL p_dragModeEnabled = NO;
static CGFloat p_iconScale = 1.0;
static CGFloat p_iconOpacity = 1.0;
static CGFloat p_offsetX = 0.0;
static CGFloat p_offsetY = 0.0;
static int p_deviceModel = 0; // 0 = Auto, 1 = Island, 2 = Notch, 3 = Classic
static int p_batteryPercentMode = 0; // 0 = Ẩn, 1 = Ở tâm, 2 = Bên cạnh
static int p_speedThreshold = 2; // 0 = Tắt, 1 = >50K, 2 = >100K, 3 = Luôn hiện
static int p_colorMode = 0; // 0 = Dynamic, 1 = Monochrome, 2 = Neon Cyan, 3 = Neon Purple
static BOOL p_breathingGlow = YES;
static BOOL p_showRAM = NO;
static BOOL p_dotCount5 = NO;

// Stock Status Bar Item Hiding
static BOOL p_hideStockBattery = YES;
static BOOL p_hideStockBatteryPercent = YES;
static BOOL p_hideStockWifi = NO;
static BOOL p_hideStockCellular = NO;
static BOOL p_hideStockCarrier = NO;
static BOOL p_hideStockTime = NO;
static BOOL p_hideStockLocation = NO;
static BOOL p_hideStockVPN = NO;
static BOOL p_hideStockFocus = NO;
static BOOL p_hideStockAlarm = NO;
static BOOL p_hideStockBluetooth = NO;
static BOOL p_hideStockAirplane = NO;

// Gestures
static int p_actionSingleTap = 0;
static int p_actionDoubleTap = 4;
static int p_actionLongPress = 1;
static int p_hapticFeedback = 1;

static void loadPrefs(void) {
    NSString *prefPath = @"/var/jb/var/mobile/Library/Preferences/com.hoangnguyen.compactstatusbar.plist";
    if (![[NSFileManager defaultManager] fileExistsAtPath:prefPath]) {
        prefPath = @"/var/mobile/Library/Preferences/com.hoangnguyen.compactstatusbar.plist";
    }
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefPath];
    if (prefs) {
        p_enabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        p_dragModeEnabled = prefs[@"dragModeEnabled"] ? [prefs[@"dragModeEnabled"] boolValue] : NO;
        p_iconScale = prefs[@"iconScale"] ? [prefs[@"iconScale"] floatValue] : 1.0;
        p_iconOpacity = prefs[@"iconOpacity"] ? [prefs[@"iconOpacity"] floatValue] : 1.0;
        p_offsetX = prefs[@"offsetX"] ? [prefs[@"offsetX"] floatValue] : 0.0;
        p_offsetY = prefs[@"offsetY"] ? [prefs[@"offsetY"] floatValue] : 0.0;
        p_deviceModel = prefs[@"deviceModel"] ? [prefs[@"deviceModel"] intValue] : 0;
        p_batteryPercentMode = prefs[@"batteryPercentMode"] ? [prefs[@"batteryPercentMode"] intValue] : 0;
        p_speedThreshold = prefs[@"speedThreshold"] ? [prefs[@"speedThreshold"] intValue] : 2;
        p_colorMode = prefs[@"colorMode"] ? [prefs[@"colorMode"] intValue] : 0;
        p_breathingGlow = prefs[@"breathingGlow"] ? [prefs[@"breathingGlow"] boolValue] : YES;
        p_showRAM = prefs[@"showRAM"] ? [prefs[@"showRAM"] boolValue] : NO;
        p_dotCount5 = prefs[@"dotCount5"] ? [prefs[@"dotCount5"] boolValue] : NO;

        p_hideStockBattery = prefs[@"hideStockBattery"] ? [prefs[@"hideStockBattery"] boolValue] : YES;
        p_hideStockBatteryPercent = prefs[@"hideStockBatteryPercent"] ? [prefs[@"hideStockBatteryPercent"] boolValue] : YES;
        p_hideStockWifi = prefs[@"hideStockWifi"] ? [prefs[@"hideStockWifi"] boolValue] : NO;
        p_hideStockCellular = prefs[@"hideStockCellular"] ? [prefs[@"hideStockCellular"] boolValue] : NO;
        p_hideStockCarrier = prefs[@"hideStockCarrier"] ? [prefs[@"hideStockCarrier"] boolValue] : NO;
        p_hideStockTime = prefs[@"hideStockTime"] ? [prefs[@"hideStockTime"] boolValue] : NO;
        p_hideStockLocation = prefs[@"hideStockLocation"] ? [prefs[@"hideStockLocation"] boolValue] : NO;
        p_hideStockVPN = prefs[@"hideStockVPN"] ? [prefs[@"hideStockVPN"] boolValue] : NO;
        p_hideStockFocus = prefs[@"hideStockFocus"] ? [prefs[@"hideStockFocus"] boolValue] : NO;
        p_hideStockAlarm = prefs[@"hideStockAlarm"] ? [prefs[@"hideStockAlarm"] boolValue] : NO;
        p_hideStockBluetooth = prefs[@"hideStockBluetooth"] ? [prefs[@"hideStockBluetooth"] boolValue] : NO;
        p_hideStockAirplane = prefs[@"hideStockAirplane"] ? [prefs[@"hideStockAirplane"] boolValue] : NO;

        p_actionSingleTap = prefs[@"actionSingleTap"] ? [prefs[@"actionSingleTap"] intValue] : 0;
        p_actionDoubleTap = prefs[@"actionDoubleTap"] ? [prefs[@"actionDoubleTap"] intValue] : 4;
        p_actionLongPress = prefs[@"actionLongPress"] ? [prefs[@"actionLongPress"] intValue] : 1;
        p_hapticFeedback = prefs[@"hapticFeedback"] ? [prefs[@"hapticFeedback"] intValue] : 1;
    }
}

static void savePreferenceNumber(NSString *key, NSNumber *val) {
    NSString *prefPath = @"/var/jb/var/mobile/Library/Preferences/com.hoangnguyen.compactstatusbar.plist";
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/var/mobile/Library/Preferences"]) {
        prefPath = @"/var/mobile/Library/Preferences/com.hoangnguyen.compactstatusbar.plist";
    }
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:prefPath];
    if (!dict) dict = [NSMutableDictionary dictionary];
    dict[key] = val;
    [dict writeToFile:prefPath atomically:YES];

    NSString *fallback = @"/var/mobile/Library/Preferences/com.hoangnguyen.compactstatusbar.plist";
    if (![prefPath isEqualToString:fallback]) {
        [dict writeToFile:fallback atomically:YES];
    }

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.hoangnguyen.compactstatusbar/ReloadPrefs"),
        NULL,
        NULL,
        YES
    );
}

// MARK: - Helper Functions (Network, RAM, Cellular, Wi-Fi)

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
        id<SBWiFiManagerProtocol> wifiMgr = (id<SBWiFiManagerProtocol>)[wifiClass performSelector:@selector(sharedInstance)];
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
        id<SBTelephonyManagerProtocol> teleMgr = (id<SBTelephonyManagerProtocol>)[teleClass performSelector:@selector(sharedTelephonyManager)];
        if ([teleMgr respondsToSelector:@selector(signalStrengthBars)]) {
            return [teleMgr signalStrengthBars];
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

static void triggerHaptic(int level) {
    if (level == 0) return;
    UIImpactFeedbackStyle style = UIImpactFeedbackStyleLight;
    if (level == 2) style = UIImpactFeedbackStyleMedium;
    else if (level == 3) style = UIImpactFeedbackStyleHeavy;
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:style];
    [feedback impactOccurred];
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
@property (nonatomic, strong) UILabel *sidePercentLabel;

@property (nonatomic, assign) BOOL showRAM;
@property (nonatomic, assign) BOOL isBreathing;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) uint64_t lastDownloadBytes;
@property (nonatomic, assign) NSTimeInterval lastSampleTime;

@property (nonatomic, assign) CGPoint anchorCenter;
@property (nonatomic, strong) UIPanGestureRecognizer *dragPanGesture;

- (void)rebuildCellularDots;
- (void)applyPreferences;
- (void)updateStats;
- (void)showHUD;
- (void)toggleRAMDisplay;
- (void)handleDragPan:(UIPanGestureRecognizer *)pan;
- (void)updateDragHUDWithX:(CGFloat)x y:(CGFloat)y finished:(BOOL)finished;
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
        [self applyPreferences];

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

- (void)applyPreferences {
    self.transform = CGAffineTransformMakeScale(p_iconScale, p_iconScale);
    self.alpha = p_iconOpacity;
    if (p_dragModeEnabled) {
        self.layer.borderColor = [UIColor colorWithRed:0.2 green:0.9 blue:0.4 alpha:1.0].CGColor;
        self.layer.borderWidth = 1.5;
        self.layer.cornerRadius = 6.0;
        if (!self.dragPanGesture) {
            self.dragPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDragPan:)];
            [self addGestureRecognizer:self.dragPanGesture];
        }
        self.dragPanGesture.enabled = YES;
    } else {
        self.layer.borderWidth = 0.0;
        if (self.dragPanGesture) {
            self.dragPanGesture.enabled = NO;
        }
    }
}

- (void)handleDragPan:(UIPanGestureRecognizer *)pan {
    UIView *superview = self.superview;
    if (!superview) return;

    CGPoint translation = [pan translationInView:superview];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:superview];

    CGFloat curX = self.center.x - self.anchorCenter.x;
    CGFloat curY = self.center.y - self.anchorCenter.y;
    p_offsetX = curX;
    p_offsetY = curY;

    [self updateDragHUDWithX:curX y:curY finished:(pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled)];

    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        savePreferenceNumber(@"offsetX", @(curX));
        savePreferenceNumber(@"offsetY", @(curY));
        triggerHaptic(2);
    }
}

- (void)updateDragHUDWithX:(CGFloat)x y:(CGFloat)y finished:(BOOL)finished {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;

    UILabel *hud = (UILabel *)[keyWindow viewWithTag:998833];
    if (!hud) {
        hud = [[UILabel alloc] initWithFrame:CGRectMake((keyWindow.bounds.size.width - 220) / 2.0, 52.0, 220.0, 32.0)];
        hud.tag = 998833;
        hud.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
        hud.textColor = [UIColor colorWithRed:0.2 green:0.9 blue:0.5 alpha:1.0];
        hud.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightBold];
        hud.textAlignment = NSTextAlignmentCenter;
        hud.layer.cornerRadius = 16.0;
        hud.layer.masksToBounds = YES;
        hud.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:1.0].CGColor;
        hud.layer.borderWidth = 1.0;
        [keyWindow addSubview:hud];
    }
    [keyWindow bringSubviewToFront:hud];

    if (!finished) {
        hud.text = [NSString stringWithFormat:@"📍 X: %+.0f  |  Y: %+.0f", x, y];
        hud.alpha = 1.0;
    } else {
        hud.text = [NSString stringWithFormat:@"✅ Đã lưu (X: %+.0f, Y: %+.0f)", x, y];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{
                hud.alpha = 0.0;
            } completion:^(BOOL done) {
                [hud removeFromSuperview];
            }];
        });
    }
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

    UIBezierPath *baseDotPath = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(11.0 - 0.9, 13.0 - 0.9, 1.8, 1.8)];
    _wifiDotLayer = [CAShapeLayer layer];
    _wifiDotLayer.fillColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
    _wifiDotLayer.path = baseDotPath.CGPath;
    [self.layer addSublayer:_wifiDotLayer];

    CGFloat startWifi = 225.0 * M_PI / 180.0;
    CGFloat endWifi = 315.0 * M_PI / 180.0;

    UIBezierPath *w1 = [UIBezierPath bezierPathWithArcCenter:wifiOrigin radius:3.2 startAngle:startWifi endAngle:endWifi clockwise:YES];
    _wifiWave1Layer = [CAShapeLayer layer];
    _wifiWave1Layer.fillColor = [UIColor clearColor].CGColor;
    _wifiWave1Layer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
    _wifiWave1Layer.lineWidth = 1.1;
    _wifiWave1Layer.lineCap = kCALineCapRound;
    _wifiWave1Layer.path = w1.CGPath;
    [self.layer addSublayer:_wifiWave1Layer];

    UIBezierPath *w2 = [UIBezierPath bezierPathWithArcCenter:wifiOrigin radius:5.6 startAngle:startWifi endAngle:endWifi clockwise:YES];
    _wifiWave2Layer = [CAShapeLayer layer];
    _wifiWave2Layer.fillColor = [UIColor clearColor].CGColor;
    _wifiWave2Layer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
    _wifiWave2Layer.lineWidth = 1.1;
    _wifiWave2Layer.lineCap = kCALineCapRound;
    _wifiWave2Layer.path = w2.CGPath;
    [self.layer addSublayer:_wifiWave2Layer];

    // 3. Nhãn hiển thị tâm (Center Label: Tốc độ mạng / 4G / % Pin tâm)
    _centerLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 6.0, 22.0, 10.0)];
    _centerLabel.font = [UIFont systemFontOfSize:6.5 weight:UIFontWeightBold];
    _centerLabel.textColor = [UIColor whiteColor];
    _centerLabel.textAlignment = NSTextAlignmentCenter;
    _centerLabel.hidden = YES;
    [self addSubview:_centerLabel];

    // 4. Nhãn hiển thị số % Pin bên cạnh vòng tròn (Side Percent Label)
    _sidePercentLabel = [[UILabel alloc] initWithFrame:CGRectMake(-30.0, 3.0, 28.0, 16.0)];
    _sidePercentLabel.font = [UIFont systemFontOfSize:9.0 weight:UIFontWeightBold];
    _sidePercentLabel.textColor = [UIColor whiteColor];
    _sidePercentLabel.textAlignment = NSTextAlignmentRight;
    _sidePercentLabel.hidden = YES;
    [self addSubview:_sidePercentLabel];

    // 5. Các chấm sóng di động ở đáy
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
    longPress.minimumPressDuration = 0.55;
    [self addGestureRecognizer:longPress];
}

// MARK: - Actions Dispatcher
static void executeAction(int actionCode, CompactStatusView *view) {
    switch (actionCode) {
        case 0: // Hiện Popup HUD
            [view showHUD];
            break;
        case 1: { // Khóa màn hình
            Class lmClass = objc_getClass("SBLockScreenManager");
            if (lmClass && [lmClass respondsToSelector:@selector(sharedInstance)]) {
                id<SBLockScreenManagerProtocol> mgr = (id<SBLockScreenManagerProtocol>)[lmClass performSelector:@selector(sharedInstance)];
                if ([mgr respondsToSelector:@selector(lockUIFromSource:withOptions:)]) {
                    [mgr lockUIFromSource:1 withOptions:nil];
                }
            }
            break;
        }
        case 2: { // Mở Control Center
            Class ccClass = objc_getClass("SBControlCenterController");
            if (ccClass && [ccClass respondsToSelector:@selector(sharedInstance)]) {
                id<SBControlCenterControllerProtocol> cc = (id<SBControlCenterControllerProtocol>)[ccClass performSelector:@selector(sharedInstance)];
                if ([cc respondsToSelector:@selector(presentAnimated:)]) {
                    [cc presentAnimated:YES];
                }
            }
            break;
        }
        case 3: { // Chụp ảnh màn hình
            Class scClass = objc_getClass("SBScreenShotter");
            if (scClass && [scClass respondsToSelector:@selector(sharedInstance)]) {
                id sc = [scClass performSelector:@selector(sharedInstance)];
                if ([sc respondsToSelector:@selector(saveScreenshot)]) {
                    [sc performSelector:@selector(saveScreenshot)];
                }
            } else {
                Class sccClass = objc_getClass("SBScreenCaptureController");
                if (sccClass && [sccClass respondsToSelector:@selector(sharedInstance)]) {
                    id scc = [sccClass performSelector:@selector(sharedInstance)];
                    if ([scc respondsToSelector:@selector(takeScreenshot)]) {
                        [scc performSelector:@selector(takeScreenshot)];
                    }
                }
            }
            break;
        }
        case 4: // Đổi Pin / RAM
            [view toggleRAMDisplay];
            break;
        case 5: { // Respring
            dispatch_async(dispatch_get_main_queue(), ^{
                _exit(0);
            });
            break;
        }
        default:
            break;
    }
}

- (void)handleSingleTap {
    if (p_dragModeEnabled) return;
    triggerHaptic(p_hapticFeedback);
    executeAction(p_actionSingleTap, self);
}

- (void)handleDoubleTap {
    if (p_dragModeEnabled) return;
    triggerHaptic(p_hapticFeedback);
    executeAction(p_actionDoubleTap, self);
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (p_dragModeEnabled) return;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        triggerHaptic(p_hapticFeedback);
        executeAction(p_actionLongPress, self);
    }
}

- (void)toggleRAMDisplay {
    self.showRAM = !self.showRAM;
    [self updateStats];
}

// MARK: - HUD Popup
- (void)showHUD {
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

// MARK: - Update Statistics (1-second cycle)
- (void)updateStats {
    float rawLevel = [UIDevice currentDevice].batteryLevel;
    CGFloat bat = rawLevel < 0 ? 1.0 : (CGFloat)rawLevel;
    UIDeviceBatteryState bState = [UIDevice currentDevice].batteryState;
    BOOL charging = (bState == UIDeviceBatteryStateCharging || bState == UIDeviceBatteryStateFull);
    BOOL lowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;

    CGFloat ramRatio = getRAMUsedRatio(NULL, NULL);

    // 1. Tiến trình vòng cung ngoài
    CGFloat progressVal = self.showRAM ? MIN(MAX(ramRatio, 0.0), 1.0) : bat;
    _progressLayer.strokeEnd = progressVal;

    // 2. Màu sắc vòng cung theo ColorMode
    UIColor *col = [UIColor colorWithWhite:1.0 alpha:0.95];
    if (p_colorMode == 1) { // Đơn sắc thích ứng
        col = [UIColor colorWithWhite:1.0 alpha:0.95];
    } else if (p_colorMode == 2) { // Neon Cyan
        col = [UIColor colorWithRed:0.0 green:0.96 blue:1.0 alpha:1.0];
    } else if (p_colorMode == 3) { // Neon Tím
        col = [UIColor colorWithRed:0.75 green:0.33 blue:0.93 alpha:1.0];
    } else { // Dynamic hệ thống (0)
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
    }
    _progressLayer.strokeColor = col.CGColor;

    // 3. Hiệu ứng Breathing Glow khi đang sạc
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

    // 4. Đo lưu lượng mạng thời gian thực
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

    // Kiểm tra ngưỡng tốc độ mạng
    BOOL showSpeed = NO;
    if (p_speedThreshold == 1 && speed > 51200.0) showSpeed = YES;      // > 50 KB/s
    else if (p_speedThreshold == 2 && speed > 102400.0) showSpeed = YES; // > 100 KB/s
    else if (p_speedThreshold == 3) showSpeed = YES;                     // Luôn hiện

    // 5. Logic hiển thị ở tâm (Tâm: % Pin, Tốc độ mạng, hoặc Wi-Fi)
    if (p_batteryPercentMode == 1) {
        // Chế độ 1: Hiện % Pin ngay tại tâm
        _wifiDotLayer.hidden = YES;
        _wifiWave1Layer.hidden = YES;
        _wifiWave2Layer.hidden = YES;
        _centerLabel.hidden = NO;
        int pct = self.showRAM ? (int)(ramRatio * 100) : (int)(bat * 100);
        _centerLabel.text = [NSString stringWithFormat:@"%d", pct];
        _centerLabel.textColor = col;
    } else if (showSpeed) {
        // Hiện tốc độ mạng ở tâm
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
        // Hiện biểu tượng Wi-Fi chuẩn
        _centerLabel.hidden = YES;
        _wifiDotLayer.hidden = NO;
        _wifiWave1Layer.hidden = NO;
        _wifiWave2Layer.hidden = NO;
        _wifiDotLayer.opacity = 1.0;
        _wifiWave1Layer.opacity = 1.0;
        _wifiWave2Layer.opacity = 1.0;
    } else {
        // Dùng 4G
        _wifiDotLayer.hidden = YES;
        _wifiWave1Layer.hidden = YES;
        _wifiWave2Layer.hidden = YES;
        _centerLabel.hidden = NO;
        _centerLabel.text = @"4G";
        _centerLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.90];
    }

    // 6. Chế độ 2: Hiện số % pin bên cạnh vòng tròn
    if (p_batteryPercentMode == 2) {
        _sidePercentLabel.hidden = NO;
        int pct = self.showRAM ? (int)(ramRatio * 100) : (int)(bat * 100);
        _sidePercentLabel.text = [NSString stringWithFormat:@"%d%%", pct];
        _sidePercentLabel.textColor = col;
    } else {
        _sidePercentLabel.hidden = YES;
    }

    // 7. Các chấm sóng di động ở đáy
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

// MARK: - Respring Handler
static void doRespringFromPrefs(id self, SEL _cmd, id sender) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.hoangnguyen.compactstatusbar/Respring"),
        NULL,
        NULL,
        YES
    );

    pid_t pid;
    const char *sbrArgs[] = {"sbreload", NULL};
    posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, (char *const *)sbrArgs, NULL);
    posix_spawn(&pid, "/usr/bin/sbreload", NULL, NULL, (char *const *)sbrArgs, NULL);

    const char *kArgs[] = {"killall", "-9", "SpringBoard", NULL};
    posix_spawn(&pid, "/var/jb/usr/bin/killall", NULL, NULL, (char *const *)kArgs, NULL);
    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)kArgs, NULL);
}

// MARK: - CSBPreviewCell: Interactive Canvas & Preset Picker for PreferenceLoader
@interface CSBPreviewCell : UITableViewCell
@property (nonatomic, strong) UISegmentedControl *modelSegment;
@property (nonatomic, strong) UIView *bezelView;
@property (nonatomic, strong) UIView *islandNotchView;
@property (nonatomic, strong) UIView *speakerHole;
@property (nonatomic, strong) UILabel *clockLabel;
@property (nonatomic, strong) UIView *stockAnchorView;
@property (nonatomic, strong) CompactStatusView *gaugePreview;
@property (nonatomic, strong) UILabel *coordLabel;
@property (nonatomic, strong) UIButton *btn1;
@property (nonatomic, strong) UIButton *btn2;
@property (nonatomic, strong) UIButton *btn3;
@property (nonatomic, strong) UIButton *btn4;
@property (nonatomic, strong) UIButton *btnRespring;
@property (nonatomic, strong) id specifier;
- (void)setupUI;
- (void)updateModelDisplay;
- (void)syncFromPrefs;
@end

static void handlePreviewReloadNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    CSBPreviewCell *cell = (__bridge CSBPreviewCell *)observer;
    if (cell && [cell isKindOfClass:[CSBPreviewCell class]]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [cell syncFromPrefs];
        });
    }
}

@implementation CSBPreviewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(id)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _specifier = specifier;
        [self setupUI];
    }
    return self;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (instancetype)initWithSpecifier:(id)specifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    if (self) {
        _specifier = specifier;
        [self setupUI];
    }
    return self;
}

- (UITableView *)findParentTableView {
    UIView *v = self.superview;
    while (v && ![v isKindOfClass:[UITableView class]]) {
        v = v.superview;
    }
    return (UITableView *)v;
}

- (void)setupUI {
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    loadPrefs();

    // 1. Model Segmented Control
    NSArray *items = @[@"🏝️ Dynamic Island", @"📱 Tai thỏ", @"🔲 Cổ điển"];
    _modelSegment = [[UISegmentedControl alloc] initWithItems:items];
    int selIdx = (p_deviceModel >= 1 && p_deviceModel <= 3) ? (p_deviceModel - 1) : 0;
    _modelSegment.selectedSegmentIndex = selIdx;
    [_modelSegment addTarget:self action:@selector(modelChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:_modelSegment];

    // 2. Bezel Mockup
    _bezelView = [[UIView alloc] initWithFrame:CGRectZero];
    _bezelView.backgroundColor = [UIColor colorWithRed:0.07 green:0.08 blue:0.10 alpha:1.0];
    _bezelView.layer.cornerRadius = 18.0;
    _bezelView.layer.borderWidth = 1.2;
    _bezelView.layer.borderColor = [UIColor colorWithWhite:0.28 alpha:1.0].CGColor;
    _bezelView.clipsToBounds = YES;
    _bezelView.userInteractionEnabled = YES;
    [self.contentView addSubview:_bezelView];

    // Clock
    _clockLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, 45, 18)];
    _clockLabel.text = @"9:41";
    _clockLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightBold];
    _clockLabel.textColor = [UIColor whiteColor];
    [_bezelView addSubview:_clockLabel];

    // Notch / Island view
    _islandNotchView = [[UIView alloc] initWithFrame:CGRectZero];
    _islandNotchView.backgroundColor = [UIColor blackColor];
    _speakerHole = [[UIView alloc] initWithFrame:CGRectZero];
    _speakerHole.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    [_islandNotchView addSubview:_speakerHole];
    [_bezelView addSubview:_islandNotchView];

    // Stock Battery Anchor (0, 0 watermark)
    _stockAnchorView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
    _stockAnchorView.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.7].CGColor;
    _stockAnchorView.layer.borderWidth = 1.0;
    _stockAnchorView.layer.cornerRadius = 4.0;
    _stockAnchorView.userInteractionEnabled = NO;
    [_bezelView addSubview:_stockAnchorView];

    // Interactive Gauge Preview
    _gaugePreview = [[CompactStatusView alloc] initWithFrame:CGRectMake(0, 0, 22, 22)];
    _gaugePreview.userInteractionEnabled = YES;
    [_bezelView addSubview:_gaugePreview];

    // Pan gesture on bezel
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleCanvasPan:)];
    [_bezelView addGestureRecognizer:pan];

    // Coordinates Label
    _coordLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _coordLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
    _coordLabel.textColor = [UIColor colorWithRed:0.20 green:0.85 blue:0.50 alpha:1.0];
    _coordLabel.textAlignment = NSTextAlignmentCenter;
    _coordLabel.text = [NSString stringWithFormat:@"📍 Toạ độ: X: %+.0f | Y: %+.0f (Kéo để chỉnh)", p_offsetX, p_offsetY];
    [_bezelView addSubview:_coordLabel];

    // 3. Preset Buttons
    _btn1 = [self makeButtonWithTitle:@"🎯 Gốc phải" tag:101];
    _btn2 = [self makeButtonWithTitle:@"📍 Cạnh Đảo" tag:102];
    _btn3 = [self makeButtonWithTitle:@"◀️ Góc trái" tag:103];
    _btn4 = [self makeButtonWithTitle:@"⏬ Hạ thấp" tag:104];
    [self.contentView addSubview:_btn1];
    [self.contentView addSubview:_btn2];
    [self.contentView addSubview:_btn3];
    [self.contentView addSubview:_btn4];

    // 4. Respring Button
    _btnRespring = [UIButton buttonWithType:UIButtonTypeSystem];
    [_btnRespring setTitle:@"⚡ Khởi động lại SpringBoard (Respring)" forState:UIControlStateNormal];
    _btnRespring.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];
    [_btnRespring setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _btnRespring.backgroundColor = [UIColor colorWithRed:0.12 green:0.42 blue:0.88 alpha:1.0];
    _btnRespring.layer.cornerRadius = 9.0;
    _btnRespring.layer.masksToBounds = YES;
    [_btnRespring addTarget:self action:@selector(respringTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_btnRespring];

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)(self),
        (CFNotificationCallback)handlePreviewReloadNotification,
        CFSTR("com.hoangnguyen.compactstatusbar/ReloadPrefs"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );
}

- (UIButton *)makeButtonWithTitle:(NSString *)title tag:(NSInteger)tag {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor colorWithWhite:0.20 alpha:1.0];
    btn.layer.cornerRadius = 7.0;
    btn.layer.masksToBounds = YES;
    btn.tag = tag;
    [btn addTarget:self action:@selector(presetTapped:) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    if (w <= 0) w = 360.0;

    _modelSegment.frame = CGRectMake(16, 6, w - 32, 28);
    _bezelView.frame = CGRectMake(16, 40, w - 32, 88);

    CGFloat bW = _bezelView.bounds.size.width;
    _stockAnchorView.frame = CGRectMake(bW - 40, 10, 24, 24);
    _gaugePreview.center = CGPointMake(_stockAnchorView.center.x + p_offsetX, _stockAnchorView.center.y + p_offsetY);
    _coordLabel.frame = CGRectMake(10, 66, bW - 20, 16);

    [self updateModelDisplay];

    CGFloat sp = 5.0;
    CGFloat totalW = w - 32;
    CGFloat btnW = (totalW - (sp * 3.0)) / 4.0;
    _btn1.frame = CGRectMake(16, 134, btnW, 28);
    _btn2.frame = CGRectMake(16 + (btnW + sp), 134, btnW, 28);
    _btn3.frame = CGRectMake(16 + (btnW + sp) * 2, 134, btnW, 28);
    _btn4.frame = CGRectMake(16 + (btnW + sp) * 3, 134, btnW, 28);

    _btnRespring.frame = CGRectMake(16, 168, w - 32, 34);
}

- (void)updateModelDisplay {
    CGFloat bW = _bezelView.bounds.size.width;
    NSInteger seg = _modelSegment.selectedSegmentIndex;
    if (seg == 0) { // Dynamic Island
        _islandNotchView.hidden = NO;
        _islandNotchView.frame = CGRectMake((bW - 84) / 2.0, 10, 84, 20);
        _islandNotchView.layer.cornerRadius = 10;
        _speakerHole.hidden = NO;
        _speakerHole.frame = CGRectMake(64, 5, 10, 10);
        _speakerHole.layer.cornerRadius = 5;
    } else if (seg == 1) { // Notch
        _islandNotchView.hidden = NO;
        _islandNotchView.frame = CGRectMake((bW - 120) / 2.0, 0, 120, 22);
        _islandNotchView.layer.cornerRadius = 7;
        _speakerHole.hidden = NO;
        _speakerHole.frame = CGRectMake((120 - 34) / 2.0, 4, 34, 4);
        _speakerHole.layer.cornerRadius = 2;
    } else { // Classic
        _islandNotchView.hidden = YES;
    }
}

- (void)modelChanged:(UISegmentedControl *)seg {
    p_deviceModel = (int)seg.selectedSegmentIndex + 1;
    savePreferenceNumber(@"deviceModel", @(p_deviceModel));
    [self updateModelDisplay];
    triggerHaptic(1);
}

- (void)handleCanvasPan:(UIPanGestureRecognizer *)pan {
    UITableView *tv = [self findParentTableView];
    if (pan.state == UIGestureRecognizerStateBegan) {
        if (tv) tv.scrollEnabled = NO;
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        if (tv) tv.scrollEnabled = YES;
    }

    CGPoint loc = [pan locationInView:_bezelView];
    CGFloat newX = MAX(16, MIN(_bezelView.bounds.size.width - 16, loc.x));
    CGFloat newY = MAX(12, MIN(_bezelView.bounds.size.height - 12, loc.y));

    _gaugePreview.center = CGPointMake(newX, newY);

    CGFloat curX = _gaugePreview.center.x - _stockAnchorView.center.x;
    CGFloat curY = _gaugePreview.center.y - _stockAnchorView.center.y;

    _coordLabel.text = [NSString stringWithFormat:@"📍 Toạ độ: X: %+.0f | Y: %+.0f (Kéo để chỉnh)", curX, curY];

    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        p_offsetX = curX;
        p_offsetY = curY;
        savePreferenceNumber(@"offsetX", @(curX));
        savePreferenceNumber(@"offsetY", @(curY));
        triggerHaptic(1);
    }
}

- (void)presetTapped:(UIButton *)btn {
    CGFloat newX = 0, newY = 0;
    if (btn.tag == 101) { newX = 0; newY = 0; }
    else if (btn.tag == 102) { newX = -55; newY = 0; }
    else if (btn.tag == 103) { newX = -240; newY = 0; }
    else if (btn.tag == 104) { newX = 0; newY = 16; }

    [UIView animateWithDuration:0.25 animations:^{
        self.gaugePreview.center = CGPointMake(self.stockAnchorView.center.x + newX, self.stockAnchorView.center.y + newY);
    }];
    _coordLabel.text = [NSString stringWithFormat:@"📍 Toạ độ: X: %+.0f | Y: %+.0f (Kéo để chỉnh)", newX, newY];

    p_offsetX = newX;
    p_offsetY = newY;
    savePreferenceNumber(@"offsetX", @(newX));
    savePreferenceNumber(@"offsetY", @(newY));
    triggerHaptic(2);
}

- (void)respringTapped:(UIButton *)btn {
    triggerHaptic(2);
    doRespringFromPrefs(self, @selector(respring:), nil);
}

- (void)syncFromPrefs {
    loadPrefs();
    _gaugePreview.center = CGPointMake(_stockAnchorView.center.x + p_offsetX, _stockAnchorView.center.y + p_offsetY);
    _coordLabel.text = [NSString stringWithFormat:@"📍 Toạ độ: X: %+.0f | Y: %+.0f (Kéo để chỉnh)", p_offsetX, p_offsetY];
    [_gaugePreview applyPreferences];
    [_gaugePreview updateStats];
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)(self),
        CFSTR("com.hoangnguyen.compactstatusbar/ReloadPrefs"),
        NULL
    );
}

@end

// MARK: - Stock Status Bar Item Hiding Helpers
static inline BOOL shouldHideStatusBarImageView(UIImageView *self) {
    if (!p_enabled) return NO;

    NSString *desc = [self description];
    NSString *parentDesc = self.superview ? [self.superview description] : @"";
    NSString *imgDesc = self.image ? [self.image description] : @"";
    NSString *allInfo = [NSString stringWithFormat:@"%@ %@ %@", desc, parentDesc, imgDesc].lowercaseString;

    if (p_hideStockLocation && ([allInfo containsString:@"location"] || [allInfo containsString:@"compass"])) return YES;
    if (p_hideStockVPN && [allInfo containsString:@"vpn"]) return YES;
    if (p_hideStockFocus && ([allInfo containsString:@"moon"] || [allInfo containsString:@"focus"] || [allInfo containsString:@"quietmode"] || [allInfo containsString:@"dnd"])) return YES;
    if (p_hideStockAlarm && [allInfo containsString:@"alarm"]) return YES;
    if (p_hideStockBluetooth && ([allInfo containsString:@"bluetooth"] || [allInfo containsString:@"headphone"] || [allInfo containsString:@"airpod"])) return YES;
    if (p_hideStockAirplane && [allInfo containsString:@"airplane"]) return YES;
    if (p_hideStockWifi && ([allInfo containsString:@"wifi"] || [allInfo containsString:@"airport"])) return YES;
    if (p_hideStockCellular && ([allInfo containsString:@"cellular"] || [allInfo containsString:@"signal"])) return YES;
    return NO;
}

static inline void checkAndApplyImageVisibility(UIImageView *self) {
    if (!p_enabled) return;
    if (shouldHideStatusBarImageView(self)) {
        self.hidden = YES;
        self.alpha = 0.0;
    }
}

static inline BOOL shouldHideStatusBarStringView(UIView *self, NSString *text) {
    if (!p_enabled || !text || text.length == 0) return NO;

    if (p_hideStockBatteryPercent && [text containsString:@"%"]) {
        return YES;
    }
    if (p_hideStockTime && [text containsString:@":"]) {
        return YES;
    }
    if (p_hideStockCarrier) {
        if (![text containsString:@"%"] && ![text containsString:@":"]) {
            NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            static NSSet *netTypes = nil;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                netTypes = [NSSet setWithObjects:@"LTE", @"4G", @"5G", @"3G", @"E", @"GPRS", @"1X", @"SOS", @"5G+", @"5G UW", @"5G UC", nil];
            });
            if (![netTypes containsObject:trimmed.uppercaseString]) {
                NSString *allInfo = [NSString stringWithFormat:@"%@ %@", [self description], self.superview ? [self.superview description] : @""].lowercaseString;
                if ([allInfo containsString:@"service"] || [allInfo containsString:@"carrier"] || [allInfo containsString:@"cellular"] || [allInfo containsString:@"telephony"] || trimmed.length > 2) {
                    return YES;
                }
            }
        }
    }
    return NO;
}

// MARK: - Hooks for SpringBoard Status Bar Items

static void (*orig_battery_didMoveToWindow)(UIView *, SEL) = NULL;
static void hooked_battery_didMoveToWindow(UIView *self, SEL _cmd) {
    if (orig_battery_didMoveToWindow) {
        orig_battery_didMoveToWindow(self, _cmd);
    }
    if (!self.window || !p_enabled) return;

    if (p_hideStockBattery) {
        self.hidden = YES;
        self.alpha = 0.0;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *parent = self.superview;
        if (parent) {
            CompactStatusView *custom = (CompactStatusView *)[parent viewWithTag:998811];
            if (!custom) {
                custom = [[CompactStatusView alloc] initWithFrame:CGRectMake(0, 0, 22.0, 22.0)];
                custom.tag = 998811;
                [parent addSubview:custom];
            }
            custom.anchorCenter = self.center;
            custom.center = CGPointMake(self.center.x + p_offsetX, self.center.y + p_offsetY);
            [parent bringSubviewToFront:custom];
            [custom applyPreferences];
        }
    });
}

static void (*orig_battery_layoutSubviews)(UIView *, SEL) = NULL;
static void hooked_battery_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_battery_layoutSubviews) {
        orig_battery_layoutSubviews(self, _cmd);
    }
    if (p_enabled) {
        if (p_hideStockBattery) {
            self.hidden = YES;
            self.alpha = 0.0;
        }
        UIView *parent = self.superview;
        if (parent) {
            CompactStatusView *custom = (CompactStatusView *)[parent viewWithTag:998811];
            if (custom) {
                custom.anchorCenter = self.center;
                if (!p_dragModeEnabled) {
                    custom.center = CGPointMake(self.center.x + p_offsetX, self.center.y + p_offsetY);
                }
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

static void (*orig_wifi_layoutSubviews)(UIView *, SEL) = NULL;
static void hooked_wifi_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_wifi_layoutSubviews) orig_wifi_layoutSubviews(self, _cmd);
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

static void (*orig_cell_layoutSubviews)(UIView *, SEL) = NULL;
static void hooked_cell_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_cell_layoutSubviews) orig_cell_layoutSubviews(self, _cmd);
    if (p_enabled && p_hideStockCellular) {
        self.hidden = YES;
        self.alpha = 0.0;
    }
}

static void (*orig_setText)(id, SEL, NSString *) = NULL;
static void hooked_setText(id self, SEL _cmd, NSString *text) {
    if (shouldHideStatusBarStringView((UIView *)self, text)) {
        ((UIView *)self).hidden = YES;
        ((UIView *)self).alpha = 0.0;
        return;
    }
    if (orig_setText) {
        orig_setText(self, _cmd, text);
    }
}

static void (*orig_string_layoutSubviews)(UIView *, SEL) = NULL;
static void hooked_string_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_string_layoutSubviews) orig_string_layoutSubviews(self, _cmd);
    NSString *text = [self respondsToSelector:@selector(text)] ? [self performSelector:@selector(text)] : nil;
    if (shouldHideStatusBarStringView(self, text)) {
        self.hidden = YES;
        self.alpha = 0.0;
    }
}

static void (*orig_img_didMoveToWindow)(UIView *, SEL) = NULL;
static void hooked_img_didMoveToWindow(UIView *self, SEL _cmd) {
    if (orig_img_didMoveToWindow) orig_img_didMoveToWindow(self, _cmd);
    checkAndApplyImageVisibility((UIImageView *)self);
}

static void (*orig_img_layoutSubviews)(UIView *, SEL) = NULL;
static void hooked_img_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_img_layoutSubviews) orig_img_layoutSubviews(self, _cmd);
    checkAndApplyImageVisibility((UIImageView *)self);
}

static void (*orig_img_setImage)(id, SEL, UIImage *) = NULL;
static void hooked_img_setImage(UIImageView *self, SEL _cmd, UIImage *image) {
    if (orig_img_setImage) orig_img_setImage(self, _cmd, image);
    checkAndApplyImageVisibility(self);
}

// MARK: - Notifications
static void handleRespringNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        _exit(0);
    });
}

static void handleReloadNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    loadPrefs();
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (keyWindow) {
            CompactStatusView *custom = (CompactStatusView *)[keyWindow viewWithTag:998811];
            if (custom) {
                [custom rebuildCellularDots];
                [custom applyPreferences];
                [custom updateStats];
            }
        }
    });
}

// MARK: - Constructor
__attribute__((constructor)) static void initCompactStatusBarTweak(void) {
    Class psListClass = objc_getClass("PSListController");
    if (psListClass) {
        class_replaceMethod(psListClass, sel_registerName("respring"), (IMP)doRespringFromPrefs, "v@:");
        class_replaceMethod(psListClass, sel_registerName("respring:"), (IMP)doRespringFromPrefs, "v@:@");
    }
    class_replaceMethod([UIViewController class], sel_registerName("respring"), (IMP)doRespringFromPrefs, "v@:");
    class_replaceMethod([UIViewController class], sel_registerName("respring:"), (IMP)doRespringFromPrefs, "v@:@");
    class_replaceMethod([NSObject class], sel_registerName("respring"), (IMP)doRespringFromPrefs, "v@:");
    class_replaceMethod([NSObject class], sel_registerName("respring:"), (IMP)doRespringFromPrefs, "v@:@");

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if ([bundleID isEqualToString:@"com.apple.Preferences"]) {
        return;
    }

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
        SafeSwizzle(wifiClass, @selector(layoutSubviews), (IMP)hooked_wifi_layoutSubviews, (IMP *)&orig_wifi_layoutSubviews);
    }
    Class legacyWifiClass = objc_getClass("UIStatusBarDataNetworkItemView");
    if (legacyWifiClass) {
        SafeSwizzle(legacyWifiClass, @selector(didMoveToWindow), (IMP)hooked_wifi_didMoveToWindow, (IMP *)&orig_wifi_didMoveToWindow);
        SafeSwizzle(legacyWifiClass, @selector(layoutSubviews), (IMP)hooked_wifi_layoutSubviews, (IMP *)&orig_wifi_layoutSubviews);
    }

    // 3. Hook Stock Cellular View
    Class cellClass = objc_getClass("_UIStatusBarCellularSignalView");
    if (cellClass) {
        SafeSwizzle(cellClass, @selector(didMoveToWindow), (IMP)hooked_cell_didMoveToWindow, (IMP *)&orig_cell_didMoveToWindow);
        SafeSwizzle(cellClass, @selector(layoutSubviews), (IMP)hooked_cell_layoutSubviews, (IMP *)&orig_cell_layoutSubviews);
    }
    Class legacyCellClass = objc_getClass("UIStatusBarSignalStrengthItemView");
    if (legacyCellClass) {
        SafeSwizzle(legacyCellClass, @selector(didMoveToWindow), (IMP)hooked_cell_didMoveToWindow, (IMP *)&orig_cell_didMoveToWindow);
        SafeSwizzle(legacyCellClass, @selector(layoutSubviews), (IMP)hooked_cell_layoutSubviews, (IMP *)&orig_cell_layoutSubviews);
    }

    // 4. Hook String View (% text, Time/Clock, Carrier)
    Class stringViewClass = objc_getClass("_UIStatusBarStringView");
    if (stringViewClass) {
        SafeSwizzle(stringViewClass, @selector(setText:), (IMP)hooked_setText, (IMP *)&orig_setText);
        SafeSwizzle(stringViewClass, @selector(layoutSubviews), (IMP)hooked_string_layoutSubviews, (IMP *)&orig_string_layoutSubviews);
    }

    // 5. Hook Image View (Indicators: Location, VPN, Focus/DND, Alarm, Bluetooth, Airplane)
    Class imgViewClass = objc_getClass("_UIStatusBarImageView");
    if (imgViewClass) {
        SafeSwizzle(imgViewClass, @selector(didMoveToWindow), (IMP)hooked_img_didMoveToWindow, (IMP *)&orig_img_didMoveToWindow);
        SafeSwizzle(imgViewClass, @selector(layoutSubviews), (IMP)hooked_img_layoutSubviews, (IMP *)&orig_img_layoutSubviews);
        SafeSwizzle(imgViewClass, @selector(setImage:), (IMP)hooked_img_setImage, (IMP *)&orig_img_setImage);
    }
}
