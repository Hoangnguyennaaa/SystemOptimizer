#import "Tweak.h"

// MARK: - Global Configuration Variables
static BOOL kEnabled = YES;
static NSInteger kDockMode = 1; // 0 = Standalone, 1 = Combined with FloatingDockXVI
static NSInteger kDockIconCount = 4;
static CGFloat kDockIconScale = 0.85;
static CGFloat kDockWidth = 78.0;
static CGFloat kDockHeight = 330.0;
static CGFloat kRightMargin = 10.0;
static CGFloat kVerticalOffset = 0.0;
static CGFloat kCornerRadius = 39.0;
static CGFloat kDockBlurAlpha = 0.82;
static BOOL kDockBlurEnabled = YES;
static BOOL kHomeCompressGrid = YES;
static CGFloat kHomeRightInset = 90.0;
static BOOL kExpandBottomRows = YES;

// MARK: - Preference Loader
static void loadPreferences() {
    NSString *prefPath = PREF_PATH_ROOTLESS;
    if (![[NSFileManager defaultManager] fileExistsAtPath:prefPath]) {
        prefPath = PREF_PATH_ROOTFUL;
    }
    
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefPath];
    if (prefs) {
        kEnabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        kDockMode = prefs[@"dockMode"] ? [prefs[@"dockMode"] integerValue] : 1;
        kDockIconCount = prefs[@"dockIconCount"] ? [prefs[@"dockIconCount"] integerValue] : 4;
        kDockIconScale = prefs[@"dockIconScale"] ? [prefs[@"dockIconScale"] doubleValue] : 0.85;
        kDockWidth = prefs[@"dockWidth"] ? [prefs[@"dockWidth"] doubleValue] : 78.0;
        kDockHeight = prefs[@"dockHeight"] ? [prefs[@"dockHeight"] doubleValue] : 330.0;
        kRightMargin = prefs[@"rightMargin"] ? [prefs[@"rightMargin"] doubleValue] : 10.0;
        kVerticalOffset = prefs[@"verticalOffset"] ? [prefs[@"verticalOffset"] doubleValue] : 0.0;
        kCornerRadius = prefs[@"cornerRadius"] ? [prefs[@"cornerRadius"] doubleValue] : (kDockWidth / 2.0);
        kDockBlurAlpha = prefs[@"dockBlurAlpha"] ? [prefs[@"dockBlurAlpha"] doubleValue] : 0.82;
        kDockBlurEnabled = prefs[@"dockBlurEnabled"] ? [prefs[@"dockBlurEnabled"] boolValue] : YES;
        kHomeCompressGrid = prefs[@"homeCompressGrid"] ? [prefs[@"homeCompressGrid"] boolValue] : YES;
        kHomeRightInset = prefs[@"homeRightInset"] ? [prefs[@"homeRightInset"] doubleValue] : 90.0;
        kExpandBottomRows = prefs[@"expandBottomRows"] ? [prefs[@"expandBottomRows"] boolValue] : YES;
    }
}

static void triggerRespring() {
    pid_t pid;
    const char *args_sbr_rootless[] = {"/var/jb/usr/bin/sbreload", NULL};
    if (access("/var/jb/usr/bin/sbreload", X_OK) == 0) {
        posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, (char *const *)args_sbr_rootless, NULL);
        return;
    }
    const char *args_sbr[] = {"/usr/bin/sbreload", NULL};
    if (access("/usr/bin/sbreload", X_OK) == 0) {
        posix_spawn(&pid, "/usr/bin/sbreload", NULL, NULL, (char *const *)args_sbr, NULL);
        return;
    }
    const char *args_killall[] = {"/var/jb/usr/bin/killall", "-9", "SpringBoard", NULL};
    posix_spawn(&pid, "/var/jb/usr/bin/killall", NULL, NULL, (char *const *)args_killall, NULL);
}

static void preferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    loadPreferences();
    
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            SBIconController *iconController = [%c(SBIconController) sharedInstance];
            if ([iconController respondsToSelector:@selector(relayout)]) {
                [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                    [iconController relayout];
                } completion:nil];
            }
        } @catch (NSException *e) {}
    });
}

static void respringNotificationReceived(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        triggerRespring();
    });
}

// MARK: - Helper Layout Functions
static CGRect calculateDuoDockFrame(void) {
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat w = kDockWidth;
    CGFloat h = kDockHeight;
    CGFloat x = screenBounds.size.width - w - kRightMargin;
    CGFloat y = ((screenBounds.size.height - h) / 2.0) + kVerticalOffset;
    return CGRectMake(x, y, w, h);
}

static void applyVerticalIconLayout(UIView *containerView, CGFloat dockW, CGFloat dockH) {
    if (!containerView) return;
    
    NSMutableArray<SBIconView *> *icons = [NSMutableArray array];
    for (UIView *sub in containerView.subviews) {
        if ([sub isKindOfClass:%c(SBIconView)]) {
            [icons addObject:(SBIconView *)sub];
        }
    }
    
    NSUInteger count = icons.count;
    if (count == 0) return;
    
    CGFloat topPadding = 22.0;
    CGFloat bottomPadding = 22.0;
    CGFloat availableHeight = dockH - topPadding - bottomPadding;
    CGFloat slotHeight = availableHeight / (CGFloat)count;
    CGFloat iconSize = (dockW < 75.0 ? 46.0 : 52.0) * kDockIconScale;
    
    for (NSUInteger i = 0; i < count; i++) {
        SBIconView *iconView = icons[i];
        CGFloat centerY = topPadding + (i * slotHeight) + (slotHeight / 2.0);
        
        iconView.bounds = CGRectMake(0, 0, iconSize, iconSize);
        iconView.center = CGPointMake(dockW / 2.0, centerY);
        iconView.transform = CGAffineTransformIdentity;
        
        if ([iconView respondsToSelector:@selector(setLabelHidden:)]) {
            [iconView setLabelHidden:YES];
        }
    }
}

// MARK: - Hook SBDockView
%hook SBDockView

- (void)layoutSubviews {
    %orig;
    if (!kEnabled) return;
    
    @try {
        // Chế độ 1: Kết hợp FloatingDockXVI -> Ẩn hoàn toàn SBDockView đáy để không bị đè 2 dock
        if (kDockMode == 1) {
            self.hidden = YES;
            self.alpha = 0.0;
            self.frame = CGRectZero;
            return;
        }
        
        // Chế độ 0: Độc lập -> Đưa SBDockView thành dock dọc bám phải
        self.hidden = NO;
        self.alpha = 1.0;
        
        CGRect dockFrame = calculateDuoDockFrame();
        self.frame = dockFrame;
        
        CGFloat radius = (kCornerRadius > 0) ? kCornerRadius : (dockFrame.size.width / 2.0);
        self.layer.cornerRadius = radius;
        if (@available(iOS 13.0, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
        self.layer.masksToBounds = YES;
        self.clipsToBounds = YES;
        
        UIView *bg = [self backgroundView];
        if (!bg && [self respondsToSelector:@selector(valueForKey:)]) {
            @try { bg = [self valueForKey:@"_backgroundView"]; } @catch (NSException *e) {}
        }
        if (bg) {
            bg.frame = self.bounds;
            bg.layer.cornerRadius = radius;
            if (@available(iOS 13.0, *)) {
                bg.layer.cornerCurve = kCACornerCurveContinuous;
            }
            bg.layer.masksToBounds = YES;
            bg.hidden = !kDockBlurEnabled;
            bg.alpha = kDockBlurEnabled ? kDockBlurAlpha : 0.0;
        }
        
        SBDockIconListView *iconListView = nil;
        if ([self respondsToSelector:@selector(dockIconListView)]) {
            iconListView = [self dockIconListView];
        }
        if (!iconListView && [self respondsToSelector:@selector(valueForKey:)]) {
            @try { iconListView = [self valueForKey:@"_iconListView"]; } @catch (NSException *e) {}
        }
        if (iconListView) {
            iconListView.frame = self.bounds;
            applyVerticalIconLayout(iconListView, dockFrame.size.width, dockFrame.size.height);
        }
    } @catch (NSException *e) {}
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (kEnabled) {
        if (kDockMode == 1) return nil; // Nếu đang chạy FloatingDockXVI, không nhận cảm ứng ở dock gốc
        if (!CGRectContainsPoint(self.bounds, point)) return nil;
    }
    return %orig(point, event);
}

%end

// MARK: - Hook SBRootFolderView
%hook SBRootFolderView

- (CGRect)_frameForDockView {
    if (kEnabled) {
        if (kDockMode == 1) {
            return CGRectZero; // Ẩn vùng dock đáy cho FloatingDock
        }
        return calculateDuoDockFrame();
    }
    return %orig;
}

- (CGRect)_frameForIconListViewAtIndex:(NSUInteger)arg1 {
    CGRect origFrame = %orig;
    if (!kEnabled) return origFrame;
    
    @try {
        CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
        if (kExpandBottomRows) {
            CGFloat bottomPadding = 32.0;
            origFrame.size.height = screenHeight - origFrame.origin.y - bottomPadding;
        }
    } @catch (NSException *e) {}
    
    return origFrame;
}

%end

// MARK: - Hook SBIconListView (Anti-Overlap & Scale)
%hook SBIconListView

- (void)layoutSubviews {
    %orig;
    if (!kEnabled) return;
    
    @try {
        // Chỉ xử lý màn hình chính (không xử lý trong dock)
        if (!self.isDock && [self.iconLocation isEqualToString:@"SBIconLocationRoot"]) {
            if (kHomeCompressGrid) {
                CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
                CGFloat dockOccupiedWidth = kDockWidth + kRightMargin + 14.0;
                CGFloat availableWidth = screenWidth - dockOccupiedWidth;
                CGFloat scaleRatio = availableWidth / screenWidth;
                
                for (UIView *subview in self.subviews) {
                    if ([subview isKindOfClass:%c(SBIconView)]) {
                        CGPoint center = subview.center;
                        CGFloat newX = (center.x * scaleRatio) + 6.0;
                        subview.center = CGPointMake(newX, center.y);
                        subview.transform = CGAffineTransformMakeScale(scaleRatio, scaleRatio);
                    }
                }
            }
        }
    } @catch (NSException *e) {}
}

- (NSUInteger)maximumIconCount {
    if (kEnabled && self.isDock) {
        return kDockIconCount;
    }
    return %orig;
}

%end

// MARK: - Hook SBFloatingDockView (Mode 1: FloatingDockXVI / GhostBoard)
%hook SBFloatingDockView

- (void)layoutSubviews {
    %orig;
    if (!kEnabled) return;
    
    @try {
        // Chế độ 0: Độc lập -> Ẩn FloatingDock để tránh capsule rỗng
        if (kDockMode == 0) {
            self.hidden = YES;
            self.alpha = 0.0;
            return;
        }
        
        // Chế độ 1: Kết hợp FloatingDockXVI
        self.hidden = NO;
        self.alpha = 1.0;
        
        CGRect dockFrame = calculateDuoDockFrame();
        self.frame = dockFrame;
        
        CGFloat radius = (kCornerRadius > 0) ? kCornerRadius : (dockFrame.size.width / 2.0);
        self.layer.cornerRadius = radius;
        if (@available(iOS 13.0, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
        self.layer.masksToBounds = YES;
        self.clipsToBounds = YES;
        
        UIView *platter = [self valueForKey:@"_mainPlatterView"];
        if (platter) {
            platter.frame = self.bounds;
            platter.layer.cornerRadius = radius;
            if (@available(iOS 13.0, *)) {
                platter.layer.cornerCurve = kCACornerCurveContinuous;
            }
            platter.layer.masksToBounds = YES;
            platter.hidden = !kDockBlurEnabled;
            platter.alpha = kDockBlurEnabled ? kDockBlurAlpha : 0.0;
        }
        
        UIView *divider = nil;
        @try { divider = [self valueForKey:@"_dividerView"]; } @catch (NSException *e) {}
        if (divider) {
            divider.hidden = YES;
            divider.alpha = 0.0;
        }
        
        UIView *userIcons = nil;
        @try { userIcons = [self valueForKey:@"_userIconListView"]; } @catch (NSException *e) {}
        if (userIcons) {
            userIcons.frame = self.bounds;
            applyVerticalIconLayout(userIcons, dockFrame.size.width, dockFrame.size.height);
        }
    } @catch (NSException *e) {}
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (kEnabled) {
        if (kDockMode == 0) return nil;
        if (!CGRectContainsPoint(self.bounds, point)) return nil;
    }
    return %orig(point, event);
}

%end

// MARK: - Constructor
%ctor {
    @autoreleasepool {
        loadPreferences();
        
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)preferencesChanged,
            CFSTR(PREF_CHANGED_NOTIFICATION),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)respringNotificationReceived,
            CFSTR(PREF_RESPRING_NOTIFICATION),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    }
}
