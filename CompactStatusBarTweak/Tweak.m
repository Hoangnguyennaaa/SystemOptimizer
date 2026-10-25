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

// MARK: - View hiển thị Pin 3-trong-1 tùy biến vẽ bằng CoreGraphics
@interface CompactStatusView : UIView
@property (nonatomic, assign) CGFloat batteryLevel;
@property (nonatomic, assign) BOOL isCharging;
@property (nonatomic, assign) CGFloat ramFreeGB;
@property (nonatomic, assign) BOOL showRAM;
@property (nonatomic, assign) NSInteger signalBars;
@end

@implementation CompactStatusView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.batteryLevel = 1.0;
        self.isCharging = NO;
        self.signalBars = 4;
        self.showRAM = p_showRAM;

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        [self updateStats];

        // Lắng nghe thay đổi mức pin
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(updateStats)
                                                     name:UIDeviceBatteryLevelDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(updateStats)
                                                     name:UIDeviceBatteryStateDidChangeNotification
                                                   object:nil];

        // Timer cập nhật mỗi 2 giây
        [NSTimer scheduledTimerWithTimeInterval:2.0
                                         target:self
                                       selector:@selector(updateStats)
                                       userInfo:nil
                                        repeats:YES];

        // Cử chỉ chạm 2 lần đổi Pin <-> RAM
        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap)];
        doubleTap.numberOfTapsRequired = 2;
        [self addGestureRecognizer:doubleTap];
    }
    return self;
}

- (void)handleDoubleTap {
    self.showRAM = !self.showRAM;
    [self setNeedsDisplay];
}

- (void)updateStats {
    float rawLevel = [UIDevice currentDevice].batteryLevel;
    self.batteryLevel = rawLevel < 0 ? 1.0 : (CGFloat)rawLevel;
    UIDeviceBatteryState state = [UIDevice currentDevice].batteryState;
    self.isCharging = (state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull);

    // Đọc RAM trống từ Mach kernel (A10 Fusion 3GB)
    mach_msg_type_number_t count = (mach_msg_type_number_t)(sizeof(vm_statistics64_data_t) / sizeof(integer_t));
    vm_statistics64_data_t vmstat;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (integer_t *)&vmstat, &count) == KERN_SUCCESS) {
        vm_size_t pageSize = 16384;
        host_page_size(mach_host_self(), &pageSize);
        uint64_t freeBytes = (uint64_t)(vmstat.free_count + vmstat.inactive_count) * pageSize;
        self.ramFreeGB = (CGFloat)freeBytes / 1073741824.0;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self setNeedsDisplay];
    });
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGFloat size = MIN(rect.size.width, rect.size.height);
    CGPoint center = CGPointMake(rect.size.width / 2.0, rect.size.height / 2.0);
    CGFloat radius = (size / 2.0) - 2.5;

    // 1. Nền đen mờ
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.0 alpha:0.85].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(center.x - radius - 1, center.y - radius - 1, (radius + 1) * 2, (radius + 1) * 2));

    // 2. Vòng ray nền (khuyết đáy góc 135 -> 45)
    CGFloat startAngle = 135.0 * M_PI / 180.0;
    CGFloat endAngle = 45.0 * M_PI / 180.0;

    CGContextSetLineWidth(ctx, 2.5);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.2].CGColor);
    CGContextAddArc(ctx, center.x, center.y, radius, startAngle, endAngle, 0);
    CGContextStrokePath(ctx);

    // 3. Vòng tiến trình Pin / RAM
    CGFloat sweep = 270.0 * M_PI / 180.0;
    CGFloat val = self.showRAM ? MIN(MAX(self.ramFreeGB / 3.0, 0.0), 1.0) : self.batteryLevel;
    CGFloat currentEndAngle = startAngle + (sweep * val);

    UIColor *activeColor = [UIColor whiteColor];
    if (self.showRAM) {
        activeColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    } else {
        if (self.isCharging) {
            activeColor = [UIColor colorWithRed:0.2 green:0.9 blue:0.3 alpha:1.0];
        } else if (self.batteryLevel <= 0.20) {
            activeColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
        }
    }

    CGContextSetStrokeColorWithColor(ctx, activeColor.CGColor);
    CGContextAddArc(ctx, center.x, center.y, radius, startAngle, currentEndAngle, 0);
    CGContextStrokePath(ctx);

    // 4. Số % hoặc chữ hiển thị ở giữa
    NSString *centerText = self.showRAM ? [NSString stringWithFormat:@"%.1f", self.ramFreeGB] : [NSString stringWithFormat:@"%.0f", self.batteryLevel * 100];
    NSDictionary *attr = @{
        NSFontAttributeName: [UIFont systemFontOfSize:8.5 weight:UIFontWeightBold],
        NSForegroundColorAttributeName: activeColor
    };
    CGSize txtSize = [centerText sizeWithAttributes:attr];
    [centerText drawAtPoint:CGPointMake(center.x - txtSize.width / 2.0, center.y - txtSize.height / 2.0 - 1.5) withAttributes:attr];

    // 5. 5 Chấm sóng ở đáy
    CGFloat dotRadius = (size / 2.0) - 2.0;
    CGFloat angles[5] = {60.0, 75.0, 90.0, 105.0, 120.0};
    for (int i = 0; i < 5; i++) {
        CGFloat rad = angles[i] * M_PI / 180.0;
        CGFloat dx = center.x + dotRadius * cos(rad);
        CGFloat dy = center.y + dotRadius * sin(rad);
        BOOL lit = i < self.signalBars;
        CGContextSetFillColorWithColor(ctx, lit ? [UIColor whiteColor].CGColor : [UIColor colorWithWhite:1.0 alpha:0.25].CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(dx - 1.0, dy - 1.0, 2.0, 2.0));
    }
}

@end

// MARK: - Hook trực tiếp _UIBatteryView (Dùng cho cả iPhone X StatusBar, Little15, và iOS 15 Modern)
static void (*orig_battery_layoutSubviews)(UIView *, SEL) = NULL;
static void hooked_battery_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_battery_layoutSubviews) {
        orig_battery_layoutSubviews(self, _cmd);
    }

    if (!p_enabled) return;

    // 1. Ẩn triệt để view pin gốc của Apple
    self.hidden = YES;
    self.alpha = 0.0;

    // 2. Chèn CompactStatusView vào superview cùng tọa độ
    UIView *parent = self.superview;
    if (parent) {
        CompactStatusView *custom = (CompactStatusView *)[parent viewWithTag:998811];
        CGRect targetFrame = CGRectMake(self.frame.origin.x, self.frame.origin.y, 36, 18);
        if (!custom) {
            custom = [[CompactStatusView alloc] initWithFrame:targetFrame];
            custom.tag = 998811;
            [parent addSubview:custom];
        } else {
            custom.frame = targetFrame;
        }
        [parent bringSubviewToFront:custom];
    }
}

// Hook Legacy UIStatusBarBatteryItemView (Dùng cho giao diện iPhone 7 Plus chuẩn)
static void (*orig_legacy_layoutSubviews)(UIView *, SEL) = NULL;
static void hooked_legacy_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_legacy_layoutSubviews) {
        orig_legacy_layoutSubviews(self, _cmd);
    }

    if (!p_enabled) return;

    self.hidden = YES;
    self.alpha = 0.0;

    UIView *parent = self.superview;
    if (parent) {
        CompactStatusView *custom = (CompactStatusView *)[parent viewWithTag:998811];
        CGRect targetFrame = CGRectMake(self.frame.origin.x, self.frame.origin.y, 36, 18);
        if (!custom) {
            custom = [[CompactStatusView alloc] initWithFrame:targetFrame];
            custom.tag = 998811;
            [parent addSubview:custom];
        } else {
            custom.frame = targetFrame;
        }
        [parent bringSubviewToFront:custom];
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

// Lắng nghe lệnh Respring từ Cài đặt
static void handleRespringNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    pid_t pid;
    const char *args[] = {"killall", "-9", "SpringBoard", NULL};
    posix_spawn(&pid, "/var/jb/usr/bin/killall", NULL, NULL, (char *const *)args, NULL);
    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)args, NULL);
}

__attribute__((constructor)) static void initCompactStatusBarTweak(void) {
    loadPrefs();

    // Lắng nghe đổi cài đặt
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)loadPrefs,
        CFSTR("com.hoangnguyen.compactstatusbar/ReloadPrefs"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );

    // Lắng nghe Respring
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)handleRespringNotification,
        CFSTR("com.hoangnguyen.compactstatusbar/Respring"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );

    // 1. Hook _UIBatteryView (Toàn bộ StatusBar hiện đại iOS 15 & Little15)
    Class bClass = objc_getClass("_UIBatteryView");
    if (bClass) {
        Method m = class_getInstanceMethod(bClass, @selector(layoutSubviews));
        if (m) {
            orig_battery_layoutSubviews = (void (*)(UIView *, SEL))method_getImplementation(m);
            method_setImplementation(m, (IMP)hooked_battery_layoutSubviews);
        }
    }

    // 2. Hook UIStatusBarBatteryItemView (StatusBar truyền thống iPhone 7 Plus)
    Class legacyClass = objc_getClass("UIStatusBarBatteryItemView");
    if (legacyClass) {
        Method m2 = class_getInstanceMethod(legacyClass, @selector(layoutSubviews));
        if (m2) {
            orig_legacy_layoutSubviews = (void (*)(UIView *, SEL))method_getImplementation(m2);
            method_setImplementation(m2, (IMP)hooked_legacy_layoutSubviews);
        }
    }

    // 3. Hook _UIStatusBarStringView (Ẩn chữ số % mặc định)
    Class stringViewClass = objc_getClass("_UIStatusBarStringView");
    if (stringViewClass) {
        Method m3 = class_getInstanceMethod(stringViewClass, @selector(setText:));
        if (m3) {
            orig_setText = (void (*)(id, SEL, NSString *))method_getImplementation(m3);
            method_setImplementation(m3, (IMP)hooked_setText);
        }
    }
}
