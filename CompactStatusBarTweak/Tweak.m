#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <ifaddrs.h>
#import <net/if.h>

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
        self.showRAM = NO;

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
    self.batteryLevel = rawLevel < 0 ? 1.0 : rawLevel;
    UIDeviceBatteryState state = [UIDevice currentDevice].batteryState;
    self.isCharging = (state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull);

    // Đọc RAM trống từ Mach kernel
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

// MARK: - Swizzle SpringBoard Status Bar
static void (*orig_applyUpdate)(id, SEL, id, id);
static id hooked_applyUpdate(id self, SEL _cmd, id arg1, id arg2) {
    id result = orig_applyUpdate(self, _cmd, arg1, arg2);

    @try {
        UIView *bView = [self valueForKey:@"_batteryView"];
        if (bView) {
            bView.hidden = YES;
            bView.alpha = 0.0;
        }

        UIView *itemView = [self valueForKey:@"_itemView"];
        if (!itemView && [self respondsToSelector:@selector(view)]) {
            itemView = [self performSelector:@selector(view)];
        }

        if (itemView) {
            CompactStatusView *customView = [itemView viewWithTag:998811];
            if (!customView) {
                customView = [[CompactStatusView alloc] initWithFrame:CGRectMake(0, 0, 36, 18)];
                customView.tag = 998811;
                [itemView addSubview:customView];
            }
        }
    } @catch (NSException *e) {}

    return result;
}

static void (*orig_setText)(id, SEL, NSString *);
static void hooked_setText(id self, SEL _cmd, NSString *text) {
    if (text && [text containsString:@"%"]) {
        ((UIView *)self).hidden = YES;
        ((UIView *)self).alpha = 0.0;
        return;
    }
    orig_setText(self, _cmd, text);
}

__attribute__((constructor)) static void initCompactStatusBarTweak(void) {
    Class batteryItemClass = objc_getClass("_UIStatusBarBatteryItem");
    if (batteryItemClass) {
        Method m = class_getInstanceMethod(batteryItemClass, NSSelectorFromString(@"applyUpdate:toDisplayItem:"));
        if (m) {
            orig_applyUpdate = (void *)method_getImplementation(m);
            method_setImplementation(m, (IMP)hooked_applyUpdate);
        }
    }

    Class stringViewClass = objc_getClass("_UIStatusBarStringView");
    if (stringViewClass) {
        Method m2 = class_getInstanceMethod(stringViewClass, @selector(setText:));
        if (m2) {
            orig_setText = (void *)method_getImplementation(m2);
            method_setImplementation(m2, (IMP)hooked_setText);
        }
    }
}
