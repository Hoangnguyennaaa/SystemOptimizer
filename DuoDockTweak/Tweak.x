#import "Tweak.h"

// MARK: - Global Configurations (Deep Native Dock)
static BOOL kEnabled = YES;
static NSInteger kDockSide = 1; // 0 = Trái (Left), 1 = Phải (Right - Mặc định)
static NSInteger kDockIconCount = 4;
static CGFloat kDockIconScale = 0.85;
static CGFloat kDockWidth = 74.0;
static CGFloat kDockHeight = 320.0;
static CGFloat kRightMargin = 10.0;
static CGFloat kVerticalOffset = 0.0;
static CGFloat kCornerRadius = 37.0;

// Deep Dock Styling
static BOOL kDockBlurEnabled = YES;
static NSInteger kDockBlurStyle = 0; // 0 = Kính Tối, 1 = Kính Sáng, 2 = Siêu Mỏng, 3 = Trong Suốt
static CGFloat kDockBlurAlpha = 0.82;
static BOOL kDockBorderEnabled = NO;
static CGFloat kDockBorderWidth = 1.0;
static BOOL kDockShadowEnabled = YES;
static BOOL kHideDockLabels = YES;

// Home Screen Layout
static BOOL kHomeCompressGrid = YES;
static CGFloat kHomeRightInset = 80.0;
static BOOL kExpandBottomRows = YES;

// MARK: - Helper to Read Preference with Fallback
static id getPref(NSString *key, id defaultVal) {
    CFPreferencesAppSynchronize(CFSTR("com.hoangnguyen.duodock"));
    CFPropertyListRef val = CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.hoangnguyen.duodock"));
    if (val) {
        return (__bridge_transfer id)val;
    }
    
    NSString *path1 = PREF_PATH_ROOTLESS;
    NSString *path2 = PREF_PATH_ROOTFUL;
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path1] ?: [NSDictionary dictionaryWithContentsOfFile:path2];
    if (dict && dict[key] != nil) {
        return dict[key];
    }
    return defaultVal;
}

// MARK: - Preference Loader
static void loadPreferences(void) {
    kEnabled = [getPref(@"enabled", @YES) boolValue];
    kDockSide = [getPref(@"dockSide", @1) integerValue];
    kDockIconCount = [getPref(@"dockIconCount", @4) integerValue];
    kDockIconScale = [getPref(@"dockIconScale", @(0.85)) doubleValue];
    kDockWidth = [getPref(@"dockWidth", @(74.0)) doubleValue];
    kDockHeight = [getPref(@"dockHeight", @(320.0)) doubleValue];
    kRightMargin = [getPref(@"rightMargin", @(10.0)) doubleValue];
    kVerticalOffset = [getPref(@"verticalOffset", @(0.0)) doubleValue];
    kCornerRadius = [getPref(@"cornerRadius", @(37.0)) doubleValue];
    
    kDockBlurEnabled = [getPref(@"dockBlurEnabled", @YES) boolValue];
    kDockBlurStyle = [getPref(@"dockBlurStyle", @0) integerValue];
    kDockBlurAlpha = [getPref(@"dockBlurAlpha", @(0.82)) doubleValue];
    kDockBorderEnabled = [getPref(@"dockBorderEnabled", @NO) boolValue];
    kDockBorderWidth = [getPref(@"dockBorderWidth", @(1.0)) doubleValue];
    kDockShadowEnabled = [getPref(@"dockShadowEnabled", @YES) boolValue];
    kHideDockLabels = [getPref(@"hideDockLabels", @YES) boolValue];
    
    kHomeCompressGrid = [getPref(@"homeCompressGrid", @YES) boolValue];
    kHomeRightInset = [getPref(@"homeRightInset", @(80.0)) doubleValue];
    kExpandBottomRows = [getPref(@"expandBottomRows", @YES) boolValue];
}

// MARK: - Respring Implementation (SpringBoard Process)
static void triggerRespring(void) {
    pid_t pid;
    const char *args_sbreload_rootless[] = {"/var/jb/usr/bin/sbreload", NULL};
    if (access("/var/jb/usr/bin/sbreload", X_OK) == 0) {
        posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, (char *const *)args_sbreload_rootless, NULL);
        return;
    }
    const char *args_sbreload[] = {"/usr/bin/sbreload", NULL};
    if (access("/usr/bin/sbreload", X_OK) == 0) {
        posix_spawn(&pid, "/usr/bin/sbreload", NULL, NULL, (char *const *)args_sbreload, NULL);
        return;
    }
    const char *args_killall[] = {"/var/jb/usr/bin/killall", "-9", "SpringBoard", NULL};
    if (access("/var/jb/usr/bin/killall", X_OK) == 0) {
        posix_spawn(&pid, "/var/jb/usr/bin/killall", NULL, NULL, (char *const *)args_killall, NULL);
        return;
    }
    const char *args_killall_sys[] = {"/usr/bin/killall", "-9", "SpringBoard", NULL};
    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)args_killall_sys, NULL);
    exit(0);
}

// MARK: - Notifications Callbacks (SpringBoard Process)
static void preferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    loadPreferences();
    
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            Class iconControllerClass = objc_getClass("SBIconController");
            if (iconControllerClass) {
                id iconController = [iconControllerClass performSelector:@selector(sharedInstance)];
                if ([iconController respondsToSelector:@selector(relayout)]) {
                    [UIView animateWithDuration:0.35 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                        [iconController performSelector:@selector(relayout)];
                    } completion:nil];
                }
            }
        } @catch (NSException *e) {}
    });
}

static void respringNotificationReceived(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        triggerRespring();
    });
}

static void resetNotificationReceived(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    CFPreferencesSetAppValue(CFSTR("enabled"), NULL, CFSTR("com.hoangnguyen.duodock"));
    CFPreferencesSetAppValue(CFSTR("dockSide"), NULL, CFSTR("com.hoangnguyen.duodock"));
    CFPreferencesSetAppValue(CFSTR("dockIconCount"), NULL, CFSTR("com.hoangnguyen.duodock"));
    CFPreferencesSetAppValue(CFSTR("dockIconScale"), NULL, CFSTR("com.hoangnguyen.duodock"));
    CFPreferencesSetAppValue(CFSTR("dockWidth"), NULL, CFSTR("com.hoangnguyen.duodock"));
    CFPreferencesSetAppValue(CFSTR("dockHeight"), NULL, CFSTR("com.hoangnguyen.duodock"));
    CFPreferencesSetAppValue(CFSTR("rightMargin"), NULL, CFSTR("com.hoangnguyen.duodock"));
    CFPreferencesSetAppValue(CFSTR("verticalOffset"), NULL, CFSTR("com.hoangnguyen.duodock"));
    CFPreferencesSetAppValue(CFSTR("cornerRadius"), NULL, CFSTR("com.hoangnguyen.duodock"));
    CFPreferencesSetAppValue(CFSTR("dockBlurEnabled"), NULL, CFSTR("com.hoangnguyen.duodock"));
    CFPreferencesSetAppValue(CFSTR("dockBlurStyle"), NULL, CFSTR("com.hoangnguyen.duodock"));
    CFPreferencesSetAppValue(CFSTR("dockBlurAlpha"), NULL, CFSTR("com.hoangnguyen.duodock"));
    CFPreferencesSetAppValue(CFSTR("dockBorderEnabled"), NULL, CFSTR("com.hoangnguyen.duodock"));
    CFPreferencesSetAppValue(CFSTR("dockBorderWidth"), NULL, CFSTR("com.hoangnguyen.duodock"));
    CFPreferencesSetAppValue(CFSTR("dockShadowEnabled"), NULL, CFSTR("com.hoangnguyen.duodock"));
    CFPreferencesSetAppValue(CFSTR("hideDockLabels"), NULL, CFSTR("com.hoangnguyen.duodock"));
    CFPreferencesSetAppValue(CFSTR("homeCompressGrid"), NULL, CFSTR("com.hoangnguyen.duodock"));
    CFPreferencesSetAppValue(CFSTR("homeRightInset"), NULL, CFSTR("com.hoangnguyen.duodock"));
    CFPreferencesSetAppValue(CFSTR("expandBottomRows"), NULL, CFSTR("com.hoangnguyen.duodock"));
    CFPreferencesAppSynchronize(CFSTR("com.hoangnguyen.duodock"));
    
    [[NSFileManager defaultManager] removeItemAtPath:PREF_PATH_ROOTLESS error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:PREF_PATH_ROOTFUL error:nil];
    
    preferencesChanged(NULL, NULL, NULL, NULL, NULL);
}

// MARK: - Frame Calculation & Icon Layout Helpers
static CGRect calculateDuoDockFrame(void) {
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat w = kDockWidth;
    CGFloat h = kDockHeight;
    if (h > screenBounds.size.height - 80.0) {
        h = screenBounds.size.height - 80.0;
    }
    CGFloat x;
    if (kDockSide == 0) { // Bám cạnh trái
        x = kRightMargin;
    } else { // Bám cạnh phải
        x = screenBounds.size.width - w - kRightMargin;
    }
    CGFloat y = ((screenBounds.size.height - h) / 2.0) + kVerticalOffset;
    if (y < 30.0) y = 30.0;
    if (y + h > screenBounds.size.height - 30.0) y = screenBounds.size.height - h - 30.0;
    return CGRectMake(x, y, w, h);
}

static void applyVerticalIconLayout(UIView *containerView, CGFloat dockW, CGFloat dockH) {
    if (!containerView) return;
    
    Class iconViewClass = objc_getClass("SBIconView");
    NSMutableArray<UIView *> *icons = [NSMutableArray array];
    for (UIView *sub in containerView.subviews) {
        if ([sub isKindOfClass:iconViewClass]) {
            [icons addObject:sub];
        }
    }
    
    NSUInteger count = icons.count;
    if (count == 0) return;
    
    CGFloat topPadding = 14.0;
    CGFloat bottomPadding = 14.0;
    CGFloat availableHeight = dockH - topPadding - bottomPadding;
    CGFloat slotHeight = availableHeight / (CGFloat)count;
    CGFloat iconSize = 60.0 * kDockIconScale;
    if (iconSize > dockW - 10.0) {
        iconSize = dockW - 10.0;
    }
    if (iconSize > slotHeight - 4.0) {
        iconSize = slotHeight - 4.0;
    }
    
    for (NSUInteger i = 0; i < count; i++) {
        UIView *iconView = icons[i];
        CGFloat iy = topPadding + (i * slotHeight) + (slotHeight - iconSize) / 2.0;
        CGFloat ix = (dockW - iconSize) / 2.0;
        
        iconView.frame = CGRectMake(ix, iy, iconSize, iconSize);
        iconView.transform = CGAffineTransformIdentity;
        
        if ([iconView respondsToSelector:@selector(setLabelHidden:)]) {
            [((SBIconView *)iconView) setLabelHidden:kHideDockLabels];
        }
    }
}

// MARK: - Hooks with Logos
%hook SBDockView

- (void)layoutSubviews {
    %orig;
    if (!kEnabled) return;
    
    @try {
        CGRect dockFrame = calculateDuoDockFrame();
        self.frame = dockFrame;
        
        CGFloat radius = (kCornerRadius > 0) ? kCornerRadius : (dockFrame.size.width / 2.0);
        self.layer.cornerRadius = radius;
        if (@available(iOS 13.0, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
        self.layer.masksToBounds = NO;
        self.clipsToBounds = NO;
        
        // Viền sáng viên thuốc
        if (kDockBorderEnabled) {
            self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
            self.layer.borderWidth = kDockBorderWidth;
        } else {
            self.layer.borderWidth = 0.0;
        }
        
        // Đổ bóng 3D
        if (kDockShadowEnabled) {
            self.layer.shadowColor = [UIColor blackColor].CGColor;
            self.layer.shadowOpacity = 0.35;
            self.layer.shadowRadius = 12.0;
            self.layer.shadowOffset = CGSizeMake(kDockSide == 0 ? 3.0 : -3.0, 4.0);
            self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:radius].CGPath;
        } else {
            self.layer.shadowOpacity = 0.0;
        }
        
        // Nền mờ viên thuốc & Phong cách kính
        UIView *bg = nil;
        if ([self respondsToSelector:@selector(backgroundView)]) {
            bg = [self valueForKey:@"backgroundView"];
        }
        if (!bg) {
            @try { bg = [self valueForKey:@"_backgroundView"]; } @catch (NSException *e) {}
        }
        
        if (bg) {
            bg.frame = self.bounds;
            bg.layer.cornerRadius = radius;
            if (@available(iOS 13.0, *)) {
                bg.layer.cornerCurve = kCACornerCurveContinuous;
            }
            bg.layer.masksToBounds = YES;
            bg.clipsToBounds = YES;
            
            if (!kDockBlurEnabled || kDockBlurStyle == 3) {
                bg.hidden = YES;
                bg.alpha = 0.0;
            } else {
                bg.hidden = NO;
                bg.alpha = kDockBlurAlpha;
                
                if (kDockBlurStyle == 0) {
                    bg.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.30];
                } else if (kDockBlurStyle == 1) {
                    bg.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.30];
                } else if (kDockBlurStyle == 2) {
                    bg.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.12];
                }
            }
        }
        
        UIView *iconListView = nil;
        if ([self respondsToSelector:@selector(dockIconListView)]) {
            iconListView = [self valueForKey:@"dockIconListView"];
        }
        if (!iconListView) {
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
        if (!CGRectContainsPoint(self.bounds, point)) {
            return nil;
        }
    }
    return %orig;
}

%end

%hook SBRootFolderView

- (CGRect)_frameForDockView {
    if (kEnabled) {
        return calculateDuoDockFrame();
    }
    return %orig;
}

%end

%hook SBIconListView

- (NSUInteger)maximumIconCount {
    if (kEnabled && self.isDock) {
        return kDockIconCount;
    }
    return %orig;
}

- (UIEdgeInsets)layoutInsetsForOrientation:(NSInteger)orientation {
    UIEdgeInsets insets = %orig;
    if (!kEnabled) return insets;
    
    @try {
        if (!self.isDock && [self.iconLocation isEqualToString:@"SBIconLocationRoot"]) {
            if (kHomeCompressGrid) {
                CGFloat dockOccupied = (kHomeRightInset > 0) ? kHomeRightInset : (kDockWidth + kRightMargin + 10.0);
                if (kDockSide == 0) {
                    insets.left += dockOccupied;
                } else {
                    insets.right += dockOccupied;
                }
                if (kExpandBottomRows) {
                    insets.bottom = 8.0;
                }
            }
        }
    } @catch (NSException *e) {}
    
    return insets;
}

%end

%hook SBFloatingDockView

- (void)layoutSubviews {
    if (kEnabled) {
        self.hidden = YES;
        self.alpha = 0.0;
        self.frame = CGRectZero;
        return;
    }
    %orig;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (kEnabled) {
        return nil;
    }
    return %orig;
}

%end

// MARK: - Preferences Hooks Handlers
static void prefs_performRespring(void) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(PREF_RESPRING_NOTIFICATION),
        NULL,
        NULL,
        YES
    );
    notify_post(PREF_RESPRING_NOTIFICATION);
    
    pid_t pid;
    const char *args_sbreload[] = {"/var/jb/usr/bin/sbreload", NULL};
    if (access("/var/jb/usr/bin/sbreload", X_OK) == 0) {
        posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, (char *const *)args_sbreload, NULL);
    }
}

static void prefs_respringPrompt(UIViewController *controller, SEL _cmd, id sender) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"DuoDock"
                                                                   message:@"Khởi động lại SpringBoard (Respring) để áp dụng toàn bộ thay đổi ngay bây giờ?"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *respringAction = [UIAlertAction actionWithTitle:@"Respring ngay"
                                                             style:UIAlertActionStyleDestructive
                                                           handler:^(UIAlertAction * _Nonnull action) {
        prefs_performRespring();
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Huỷ"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    
    [alert addAction:respringAction];
    [alert addAction:cancelAction];
    
    [controller presentViewController:alert animated:YES completion:nil];
}

static void prefs_resetToDefaults(UIViewController *controller, SEL _cmd, id sender) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Khôi phục mặc định"
                                                                   message:@"Đặt lại tất cả thiết lập DuoDock về ban đầu?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"Đồng ý"
                                                       style:UIAlertActionStyleDestructive
                                                     handler:^(UIAlertAction * _Nonnull action) {
        CFPreferencesSetAppValue(CFSTR("enabled"), NULL, CFSTR("com.hoangnguyen.duodock"));
        CFPreferencesSetAppValue(CFSTR("dockSide"), NULL, CFSTR("com.hoangnguyen.duodock"));
        CFPreferencesSetAppValue(CFSTR("dockIconCount"), NULL, CFSTR("com.hoangnguyen.duodock"));
        CFPreferencesSetAppValue(CFSTR("dockIconScale"), NULL, CFSTR("com.hoangnguyen.duodock"));
        CFPreferencesSetAppValue(CFSTR("dockWidth"), NULL, CFSTR("com.hoangnguyen.duodock"));
        CFPreferencesSetAppValue(CFSTR("dockHeight"), NULL, CFSTR("com.hoangnguyen.duodock"));
        CFPreferencesSetAppValue(CFSTR("rightMargin"), NULL, CFSTR("com.hoangnguyen.duodock"));
        CFPreferencesSetAppValue(CFSTR("verticalOffset"), NULL, CFSTR("com.hoangnguyen.duodock"));
        CFPreferencesSetAppValue(CFSTR("cornerRadius"), NULL, CFSTR("com.hoangnguyen.duodock"));
        CFPreferencesSetAppValue(CFSTR("dockBlurEnabled"), NULL, CFSTR("com.hoangnguyen.duodock"));
        CFPreferencesSetAppValue(CFSTR("dockBlurStyle"), NULL, CFSTR("com.hoangnguyen.duodock"));
        CFPreferencesSetAppValue(CFSTR("dockBlurAlpha"), NULL, CFSTR("com.hoangnguyen.duodock"));
        CFPreferencesSetAppValue(CFSTR("dockBorderEnabled"), NULL, CFSTR("com.hoangnguyen.duodock"));
        CFPreferencesSetAppValue(CFSTR("dockBorderWidth"), NULL, CFSTR("com.hoangnguyen.duodock"));
        CFPreferencesSetAppValue(CFSTR("dockShadowEnabled"), NULL, CFSTR("com.hoangnguyen.duodock"));
        CFPreferencesSetAppValue(CFSTR("hideDockLabels"), NULL, CFSTR("com.hoangnguyen.duodock"));
        CFPreferencesSetAppValue(CFSTR("homeCompressGrid"), NULL, CFSTR("com.hoangnguyen.duodock"));
        CFPreferencesSetAppValue(CFSTR("homeRightInset"), NULL, CFSTR("com.hoangnguyen.duodock"));
        CFPreferencesSetAppValue(CFSTR("expandBottomRows"), NULL, CFSTR("com.hoangnguyen.duodock"));
        CFPreferencesAppSynchronize(CFSTR("com.hoangnguyen.duodock"));
        
        [[NSFileManager defaultManager] removeItemAtPath:PREF_PATH_ROOTLESS error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:PREF_PATH_ROOTFUL error:nil];
        
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR(PREF_CHANGED_NOTIFICATION),
            NULL,
            NULL,
            YES
        );
        notify_post(PREF_RESET_NOTIFICATION);
        
        if ([controller respondsToSelector:@selector(reloadSpecifiers)]) {
            [controller performSelector:@selector(reloadSpecifiers)];
        }
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Huỷ"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    
    [alert addAction:okAction];
    [alert addAction:cancelAction];
    [controller presentViewController:alert animated:YES completion:nil];
}

%ctor {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if ([bundleID isEqualToString:@"com.apple.Preferences"]) {
            Class listClass = objc_getClass("PSListController");
            if (listClass) {
                class_addMethod(listClass, @selector(respringPrompt:), (IMP)prefs_respringPrompt, "v@:@");
                class_addMethod(listClass, @selector(respringPrompt), (IMP)prefs_respringPrompt, "v@:");
                class_addMethod(listClass, @selector(respring:), (IMP)prefs_performRespring, "v@:@");
                class_addMethod(listClass, @selector(respring), (IMP)prefs_performRespring, "v@:");
                class_addMethod(listClass, @selector(resetToDefaults:), (IMP)prefs_resetToDefaults, "v@:@");
                class_addMethod(listClass, @selector(resetToDefaults), (IMP)prefs_resetToDefaults, "v@:");
            }
            return;
        }
        
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
        
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)resetNotificationReceived,
            CFSTR(PREF_RESET_NOTIFICATION),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        %init;
    }
}
