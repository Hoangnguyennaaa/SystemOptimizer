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

// MARK: - View hiển thị Pin 3-trong-1 bằng CAShapeLayer (An toàn 100%, không crash)
@interface CompactStatusView : UIView
@property (nonatomic, strong) CAShapeLayer *bgCircleLayer;
@property (nonatomic, strong) CAShapeLayer *trackLayer;
@property (nonatomic, strong) CAShapeLayer *progressLayer;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) NSMutableArray<CAShapeLayer *> *dotLayers;
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

        // 1. Nền tròn
        _bgCircleLayer = [CAShapeLayer layer];
        _bgCircleLayer.fillColor = [UIColor colorWithWhite:0.0 alpha:0.85].CGColor;
        [self.layer addSublayer:_bgCircleLayer];

        // 2. Track nền khuyết
        _trackLayer = [CAShapeLayer layer];
        _trackLayer.fillColor = [UIColor clearColor].CGColor;
        _trackLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
        _trackLayer.lineWidth = 2.0;
        _trackLayer.lineCap = kCALineCapRound;
        [self.layer addSublayer:_trackLayer];

        // 3. Tiến trình pin/RAM
        _progressLayer = [CAShapeLayer layer];
        _progressLayer.fillColor = [UIColor clearColor].CGColor;
        _progressLayer.lineWidth = 2.0;
        _progressLayer.lineCap = kCALineCapRound;
        [self.layer addSublayer:_progressLayer];

        // 4. Nhãn ở giữa
        _label = [[UILabel alloc] init];
        _label.font = [UIFont systemFontOfSize:7.5 weight:UIFontWeightBold];
        _label.textColor = [UIColor whiteColor];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.backgroundColor = [UIColor clearColor];
        [self addSubview:_label];

        // 5. 5 Chấm sóng
        _dotLayers = [NSMutableArray array];
        for (int i = 0; i < 5; i++) {
            CAShapeLayer *dot = [CAShapeLayer layer];
            dot.fillColor = [UIColor whiteColor].CGColor;
            [self.layer addSublayer:dot];
            [_dotLayers addObject:dot];
        }

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        [self updateLayers];

        // Cử chỉ chạm 2 lần đổi Pin/RAM
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap)];
        tap.numberOfTapsRequired = 2;
        [self addGestureRecognizer:tap];

        // Lắng nghe thay đổi mức pin
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateLayers) name:UIDeviceBatteryLevelDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateLayers) name:UIDeviceBatteryStateDidChangeNotification object:nil];

        _timer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(updateLayers) userInfo:nil repeats:YES];
    }
    return self;
}

- (void)handleDoubleTap {
    self.showRAM = !self.showRAM;
    [self updateLayers];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat sz = MIN(self.bounds.size.width, self.bounds.size.height);
    if (sz < 16.0) sz = 18.0;
    CGPoint c = CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0);
    CGFloat r = (sz / 2.0) - 1.5;

    _bgCircleLayer.path = [UIBezierPath bezierPathWithArcCenter:c radius:r + 1.0 startAngle:0 endAngle:2 * M_PI clockwise:YES].CGPath;

    CGFloat startAngle = 135.0 * M_PI / 180.0;
    CGFloat endAngle = 45.0 * M_PI / 180.0;
    UIBezierPath *arcPath = [UIBezierPath bezierPathWithArcCenter:c radius:r startAngle:startAngle endAngle:endAngle clockwise:YES];
    _trackLayer.path = arcPath.CGPath;
    _progressLayer.path = arcPath.CGPath;

    _label.frame = CGRectMake(c.x - r, c.y - r, r * 2, r * 2);

    CGFloat angles[5] = {60.0, 75.0, 90.0, 105.0, 120.0};
    for (int i = 0; i < 5; i++) {
        CGFloat rad = angles[i] * M_PI / 180.0;
        CGFloat dx = c.x + (r - 1.0) * cos(rad);
        CGFloat dy = c.y + (r - 1.0) * sin(rad);
        _dotLayers[i].path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(dx - 1.0, dy - 1.0, 2.0, 2.0)].CGPath;
    }
}

- (void)updateLayers {
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
            col = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
        }
        _label.text = [NSString stringWithFormat:@"%.0f", bat * 100];
    }
    _progressLayer.strokeColor = col.CGColor;
    _label.textColor = col;

    for (int i = 0; i < 5; i++) {
        _dotLayers[i].fillColor = (i < 4) ? [UIColor whiteColor].CGColor : [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
    }
}

- (void)dealloc {
    [_timer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

// MARK: - Hook an toàn vào _UIBatteryView (didMoveToWindow & layoutSubviews)
static void (*orig_battery_didMoveToWindow)(UIView *, SEL) = NULL;
static void hooked_battery_didMoveToWindow(UIView *self, SEL _cmd) {
    if (orig_battery_didMoveToWindow) {
        orig_battery_didMoveToWindow(self, _cmd);
    }
    if (!self.window || !p_enabled) return;

    for (UIView *sub in self.subviews) {
        if (sub.tag != 998811) {
            sub.hidden = YES;
            sub.alpha = 0.0;
        }
    }

    CompactStatusView *custom = (CompactStatusView *)[self viewWithTag:998811];
    if (!custom) {
        custom = [[CompactStatusView alloc] initWithFrame:self.bounds];
        custom.tag = 998811;
        custom.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:custom];
    }
}

static void (*orig_battery_layoutSubviews)(UIView *, SEL) = NULL;
static void hooked_battery_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_battery_layoutSubviews) {
        orig_battery_layoutSubviews(self, _cmd);
    }
    if (!p_enabled) return;
    for (UIView *sub in self.subviews) {
        if (sub.tag != 998811) {
            sub.hidden = YES;
            sub.alpha = 0.0;
        }
    }
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

// Respring
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

    // Hook _UIBatteryView
    Class bClass = objc_getClass("_UIBatteryView");
    if (bClass) {
        Method mMove = class_getInstanceMethod(bClass, @selector(didMoveToWindow));
        if (mMove) {
            orig_battery_didMoveToWindow = (void (*)(UIView *, SEL))method_getImplementation(mMove);
            method_setImplementation(mMove, (IMP)hooked_battery_didMoveToWindow);
        }

        Method mLayout = class_getInstanceMethod(bClass, @selector(layoutSubviews));
        if (mLayout) {
            orig_battery_layoutSubviews = (void (*)(UIView *, SEL))method_getImplementation(mLayout);
            method_setImplementation(mLayout, (IMP)hooked_battery_layoutSubviews);
        }
    }

    // Hook _UIStatusBarStringView
    Class stringViewClass = objc_getClass("_UIStatusBarStringView");
    if (stringViewClass) {
        Method m3 = class_getInstanceMethod(stringViewClass, @selector(setText:));
        if (m3) {
            orig_setText = (void (*)(id, SEL, NSString *))method_getImplementation(m3);
            method_setImplementation(m3, (IMP)hooked_setText);
        }
    }
}
