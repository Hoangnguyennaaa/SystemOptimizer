#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <notify.h>
#import <spawn.h>

static BOOL p_enabled = YES;
static BOOL p_showRAM = NO;

static void loadPrefs(void) {
    NSString *prefPath = @"/var/jb/var/mobile/Library/Preferences/com.hoangnguyen.compactstatusbar.plist";
    if (![[NSFileManager defaultManager] fileExistsAtPath:prefPath]) {
        prefPath = @"/var/mobile/Library/Preferences/com.hoangnguyen.compactstatusbar.plist";
    }
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefPath];
    if (prefs) {
        p_enabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        p_showRAM = prefs[@"showRAM"] ? [prefs[@"showRAM"] boolValue] : NO;
    }
}

// Hàm Hook an toàn: Dùng class_addMethod để KHÔNG BAO GIỜ ghi đè lên UIView gốc
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

// MARK: - View hiển thị Pin 3-trong-1 bằng CAShapeLayer (An toàn tuyệt đối)
@interface CompactStatusView : UIView
@property (nonatomic, strong) CAShapeLayer *bgLayer;
@property (nonatomic, strong) CAShapeLayer *trackLayer;
@property (nonatomic, strong) CAShapeLayer *progressLayer;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, assign) BOOL showRAM;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation CompactStatusView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.clipsToBounds = NO;
        self.showRAM = p_showRAM;

        CGFloat w = 36.0;
        CGFloat h = 18.0;

        // 1. Nền bo tròn che khít toàn bộ khu vực pin cũ
        _bgLayer = [CAShapeLayer layer];
        _bgLayer.fillColor = [UIColor colorWithWhite:0.0 alpha:0.85].CGColor;
        _bgLayer.path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, w, h) cornerRadius:h / 2.0].CGPath;
        [self.layer addSublayer:_bgLayer];

        // 2. Vòng tròn tiến trình
        CGPoint c = CGPointMake(10.0, h / 2.0);
        CGFloat r = 6.0;
        UIBezierPath *circlePath = [UIBezierPath bezierPathWithArcCenter:c radius:r startAngle:-M_PI_2 endAngle:M_PI * 1.5 clockwise:YES];

        _trackLayer = [CAShapeLayer layer];
        _trackLayer.fillColor = [UIColor clearColor].CGColor;
        _trackLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
        _trackLayer.lineWidth = 1.8;
        _trackLayer.path = circlePath.CGPath;
        [self.layer addSublayer:_trackLayer];

        _progressLayer = [CAShapeLayer layer];
        _progressLayer.fillColor = [UIColor clearColor].CGColor;
        _progressLayer.lineWidth = 1.8;
        _progressLayer.lineCap = kCALineCapRound;
        _progressLayer.path = circlePath.CGPath;
        [self.layer addSublayer:_progressLayer];

        // 3. Số % hiển thị bên cạnh
        _label = [[UILabel alloc] initWithFrame:CGRectMake(19.0, 0, 16.0, h)];
        _label.font = [UIFont systemFontOfSize:8.0 weight:UIFontWeightBold];
        _label.textColor = [UIColor whiteColor];
        _label.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_label];

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        [self updateStats];

        // Cử chỉ chạm 2 lần đổi Pin <-> RAM
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap)];
        tap.numberOfTapsRequired = 2;
        [self addGestureRecognizer:tap];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateStats) name:UIDeviceBatteryLevelDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateStats) name:UIDeviceBatteryStateDidChangeNotification object:nil];

        _timer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(updateStats) userInfo:nil repeats:YES];
    }
    return self;
}

- (void)handleDoubleTap {
    self.showRAM = !self.showRAM;
    [self updateStats];
}

- (void)updateStats {
    float rawLevel = [UIDevice currentDevice].batteryLevel;
    CGFloat bat = rawLevel < 0 ? 1.0 : (CGFloat)rawLevel;
    BOOL charging = ([UIDevice currentDevice].batteryState == UIDeviceBatteryStateCharging || [UIDevice currentDevice].batteryState == UIDeviceBatteryStateFull);

    CGFloat freeRAM = 1.5;
    mach_msg_type_number_t count = (mach_msg_type_number_t)(sizeof(vm_statistics64_data_t) / sizeof(integer_t));
    vm_statistics64_data_t vmstat;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (integer_t *)&vmstat, &count) == KERN_SUCCESS) {
        vm_size_t pageSize = 16384;
        host_page_size(mach_host_self(), &pageSize);
        freeRAM = (CGFloat)((uint64_t)(vmstat.free_count + vmstat.inactive_count) * pageSize) / 1073741824.0;
    }

    CGFloat val = self.showRAM ? MIN(MAX(freeRAM / 3.0, 0.0), 1.0) : bat;
    _progressLayer.strokeEnd = val;

    UIColor *col = [UIColor whiteColor];
    if (self.showRAM) {
        col = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
        _label.text = [NSString stringWithFormat:@"%.1f", freeRAM];
    } else {
        if (charging) {
            col = [UIColor colorWithRed:0.2 green:0.9 blue:0.3 alpha:1.0];
        } else if (bat <= 0.20) {
            col = [UIColor colorWithRed:1.0 green:0.25 blue:0.25 alpha:1.0];
        }
        _label.text = [NSString stringWithFormat:@"%d", (int)(bat * 100)];
    }
    _progressLayer.strokeColor = col.CGColor;
    _label.textColor = col;
}

- (void)dealloc {
    [_timer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

// MARK: - Hook an toàn bằng dispatch_async, tránh tuyệt đối đệ quy Layout
static void (*orig_battery_didMoveToWindow)(UIView *, SEL) = NULL;
static void hooked_battery_didMoveToWindow(UIView *self, SEL _cmd) {
    if (orig_battery_didMoveToWindow) {
        orig_battery_didMoveToWindow(self, _cmd);
    }
    if (!self.window || !p_enabled) return;

    // Ẩn view pin gốc
    self.hidden = YES;
    self.alpha = 0.0;

    // Trì hoãn việc thêm subview sang vòng lặp kế tiếp để không làm gián đoạn layout engine
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *parent = self.superview;
        if (parent && ![parent viewWithTag:998811]) {
            CompactStatusView *custom = [[CompactStatusView alloc] initWithFrame:CGRectMake(self.frame.origin.x, self.frame.origin.y, 36, 18)];
            custom.tag = 998811;
            [parent addSubview:custom];
            [parent bringSubviewToFront:custom];
        }
    });
}

// Ẩn chữ số % mặc định
static void (*orig_setText)(id, SEL, NSString *) = NULL;
static void hooked_setText(id self, SEL _cmd, NSString *text) {
    if (p_enabled && text && [text containsString:@"%"]) {
        ((UIView *)self).hidden = YES;
        ((UIView *)self).alpha = 0.0;
        return;
    }
    if (orig_setText) {
        orig_setText(self, _cmd, text);
    }
}

// Lắng nghe lệnh Respring từ Cài đặt
static void handleRespringNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    pid_t pid;
    const char *args[] = {"killall", "-9", "SpringBoard", NULL};
    posix_spawn(&pid, "/var/jb/usr/bin/killall", NULL, NULL, (char *const *)args, NULL);
    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)args, NULL);
}

__attribute__((constructor)) static void initCompactStatusBarTweak(void) {
    loadPrefs();

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)loadPrefs,
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

    // 1. Hook an toàn _UIBatteryView
    Class bClass = objc_getClass("_UIBatteryView");
    if (bClass) {
        SafeSwizzle(bClass, @selector(didMoveToWindow), (IMP)hooked_battery_didMoveToWindow, (IMP *)&orig_battery_didMoveToWindow);
    }

    // 2. Hook an toàn UIStatusBarBatteryItemView (nếu máy ở StatusBar truyền thống)
    Class legacyClass = objc_getClass("UIStatusBarBatteryItemView");
    if (legacyClass) {
        SafeSwizzle(legacyClass, @selector(didMoveToWindow), (IMP)hooked_battery_didMoveToWindow, (IMP *)&orig_battery_didMoveToWindow);
    }

    // 3. Hook _UIStatusBarStringView để ẩn chữ số %
    Class stringViewClass = objc_getClass("_UIStatusBarStringView");
    if (stringViewClass) {
        SafeSwizzle(stringViewClass, @selector(setText:), (IMP)hooked_setText, (IMP *)&orig_setText);
    }
}
