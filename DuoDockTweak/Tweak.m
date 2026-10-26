#import "Tweak.h"

// MARK: - Global Configurations
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

static BOOL isLayingOutDock = NO;

// MARK: - Preference Loader
static void loadPreferences(void) {
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

static void triggerRespring(void) {
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
            Class iconControllerClass = objc_getClass("SBIconController");
            if (iconControllerClass) {
                id iconController = [iconControllerClass performSelector:@selector(sharedInstance)];
                if ([iconController respondsToSelector:@selector(relayout)]) {
                    [iconController performSelector:@selector(relayout)];
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

// MARK: - Frame Calculation & Icon Layout Helpers
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
    
    Class iconViewClass = objc_getClass("SBIconView");
    NSMutableArray<UIView *> *icons = [NSMutableArray array];
    for (UIView *sub in containerView.subviews) {
        if ([sub isKindOfClass:iconViewClass]) {
            [icons addObject:sub];
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
        UIView *iconView = icons[i];
        CGFloat centerY = topPadding + (i * slotHeight) + (slotHeight / 2.0);
        CGPoint targetCenter = CGPointMake(dockW / 2.0, centerY);
        CGRect targetBounds = CGRectMake(0, 0, iconSize, iconSize);
        
        if (!CGPointEqualToPoint(iconView.center, targetCenter)) {
            iconView.center = targetCenter;
        }
        if (!CGRectEqualToRect(iconView.bounds, targetBounds)) {
            iconView.bounds = targetBounds;
        }
        
        if ([iconView respondsToSelector:@selector(setLabelHidden:)]) {
            [((SBIconView *)iconView) setLabelHidden:YES];
        }
    }
}

// MARK: - SBDockView Hooks
static void (*orig_SBDockView_layoutSubviews)(id, SEL);
static void custom_SBDockView_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_SBDockView_layoutSubviews) {
        orig_SBDockView_layoutSubviews(self, _cmd);
    }
    if (!kEnabled) return;
    if (isLayingOutDock) return;
    
    @try {
        if (kDockMode == 1) {
            if (!self.hidden) {
                self.hidden = YES;
                self.alpha = 0.0;
            }
            return;
        }
        
        isLayingOutDock = YES;
        self.hidden = NO;
        self.alpha = 1.0;
        
        CGRect dockFrame = calculateDuoDockFrame();
        if (!CGRectEqualToRect(self.frame, dockFrame)) {
            self.frame = dockFrame;
        }
        
        CGFloat radius = (kCornerRadius > 0) ? kCornerRadius : (dockFrame.size.width / 2.0);
        self.layer.cornerRadius = radius;
        if (@available(iOS 13.0, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
        self.layer.masksToBounds = YES;
        self.clipsToBounds = YES;
        
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
            bg.hidden = !kDockBlurEnabled;
            bg.alpha = kDockBlurEnabled ? kDockBlurAlpha : 0.0;
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
        isLayingOutDock = NO;
    } @catch (NSException *e) {
        isLayingOutDock = NO;
    }
}

static UIView *(*orig_SBDockView_hitTest)(id, SEL, CGPoint, UIEvent *);
static UIView *custom_SBDockView_hitTest(UIView *self, SEL _cmd, CGPoint point, UIEvent *event) {
    if (kEnabled) {
        if (kDockMode == 1 || self.hidden || self.alpha < 0.01) return nil;
        if (!CGRectContainsPoint(self.bounds, point)) return nil;
    }
    if (orig_SBDockView_hitTest) {
        return orig_SBDockView_hitTest(self, _cmd, point, event);
    }
    return nil;
}

// MARK: - SBRootFolderView Hooks
static CGRect (*orig_SBRootFolderView_frameForDockView)(id, SEL);
static CGRect custom_SBRootFolderView_frameForDockView(id self, SEL _cmd) {
    if (kEnabled) {
        if (kDockMode == 1) {
            return CGRectMake(0, [UIScreen mainScreen].bounds.size.height + 200, 0, 0);
        }
        return calculateDuoDockFrame();
    }
    if (orig_SBRootFolderView_frameForDockView) {
        return orig_SBRootFolderView_frameForDockView(self, _cmd);
    }
    return CGRectZero;
}

// MARK: - SBIconListView Hooks (Native Layout Insets)
static UIEdgeInsets (*orig_SBIconListView_layoutInsetsForOrientation)(id, SEL, NSInteger);
static UIEdgeInsets custom_SBIconListView_layoutInsetsForOrientation(SBIconListView *self, SEL _cmd, NSInteger orientation) {
    UIEdgeInsets insets = UIEdgeInsetsZero;
    if (orig_SBIconListView_layoutInsetsForOrientation) {
        insets = orig_SBIconListView_layoutInsetsForOrientation(self, _cmd, orientation);
    }
    if (!kEnabled) return insets;
    
    @try {
        if (!self.isDock && [self.iconLocation isEqualToString:@"SBIconLocationRoot"]) {
            insets.right += (kDockWidth + kRightMargin + 10.0);
            if (kExpandBottomRows) {
                insets.bottom = 8.0;
            }
        }
    } @catch (NSException *e) {}
    
    return insets;
}

static NSUInteger (*orig_SBIconListView_maximumIconCount)(id, SEL);
static NSUInteger custom_SBIconListView_maximumIconCount(SBIconListView *self, SEL _cmd) {
    if (kEnabled && self.isDock) {
        return kDockIconCount;
    }
    if (orig_SBIconListView_maximumIconCount) {
        return orig_SBIconListView_maximumIconCount(self, _cmd);
    }
    return 4;
}

// MARK: - SBFloatingDockView Hooks
static void (*orig_SBFloatingDockView_layoutSubviews)(id, SEL);
static void custom_SBFloatingDockView_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_SBFloatingDockView_layoutSubviews) {
        orig_SBFloatingDockView_layoutSubviews(self, _cmd);
    }
    if (!kEnabled) return;
    if (isLayingOutDock) return;
    
    @try {
        if (kDockMode == 0) {
            if (!self.hidden) {
                self.hidden = YES;
                self.alpha = 0.0;
            }
            return;
        }
        
        isLayingOutDock = YES;
        self.hidden = NO;
        self.alpha = 1.0;
        
        CGRect dockFrame = calculateDuoDockFrame();
        if (!CGRectEqualToRect(self.frame, dockFrame)) {
            self.frame = dockFrame;
        }
        
        CGFloat radius = (kCornerRadius > 0) ? kCornerRadius : (dockFrame.size.width / 2.0);
        self.layer.cornerRadius = radius;
        if (@available(iOS 13.0, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
        self.layer.masksToBounds = YES;
        self.clipsToBounds = YES;
        
        UIView *platter = nil;
        @try { platter = [self valueForKey:@"_mainPlatterView"]; } @catch (NSException *e) {}
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
        isLayingOutDock = NO;
    } @catch (NSException *e) {
        isLayingOutDock = NO;
    }
}

static UIView *(*orig_SBFloatingDockView_hitTest)(id, SEL, CGPoint, UIEvent *);
static UIView *custom_SBFloatingDockView_hitTest(UIView *self, SEL _cmd, CGPoint point, UIEvent *event) {
    if (kEnabled) {
        if (kDockMode == 0 || self.hidden || self.alpha < 0.01) return nil;
        if (!CGRectContainsPoint(self.bounds, point)) return nil;
    }
    if (orig_SBFloatingDockView_hitTest) {
        return orig_SBFloatingDockView_hitTest(self, _cmd, point, event);
    }
    return nil;
}

// MARK: - Constructor
__attribute__((constructor)) static void DuoDockInit(void) {
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
        
        // Swizzle SBDockView
        Class dockViewClass = objc_getClass("SBDockView");
        if (dockViewClass) {
            Method mLayout = class_getInstanceMethod(dockViewClass, @selector(layoutSubviews));
            if (mLayout) {
                orig_SBDockView_layoutSubviews = (void (*)(id, SEL))method_getImplementation(mLayout);
                method_setImplementation(mLayout, (IMP)custom_SBDockView_layoutSubviews);
            }
            
            Method mHitTest = class_getInstanceMethod(dockViewClass, @selector(hitTest:withEvent:));
            if (mHitTest) {
                orig_SBDockView_hitTest = (UIView *(*)(id, SEL, CGPoint, UIEvent *))method_getImplementation(mHitTest);
                method_setImplementation(mHitTest, (IMP)custom_SBDockView_hitTest);
            }
        }
        
        // Swizzle SBRootFolderView
        Class rootFolderClass = objc_getClass("SBRootFolderView");
        if (rootFolderClass) {
            Method mDockFrame = class_getInstanceMethod(rootFolderClass, @selector(_frameForDockView));
            if (mDockFrame) {
                orig_SBRootFolderView_frameForDockView = (CGRect (*)(id, SEL))method_getImplementation(mDockFrame);
                method_setImplementation(mDockFrame, (IMP)custom_SBRootFolderView_frameForDockView);
            }
        }
        
        // Swizzle SBIconListView (Layout insets only)
        Class iconListViewClass = objc_getClass("SBIconListView");
        if (iconListViewClass) {
            Method mInsets = class_getInstanceMethod(iconListViewClass, @selector(layoutInsetsForOrientation:));
            if (mInsets) {
                orig_SBIconListView_layoutInsetsForOrientation = (UIEdgeInsets (*)(id, SEL, NSInteger))method_getImplementation(mInsets);
                method_setImplementation(mInsets, (IMP)custom_SBIconListView_layoutInsetsForOrientation);
            }
            
            Method mMaxIcons = class_getInstanceMethod(iconListViewClass, @selector(maximumIconCount));
            if (mMaxIcons) {
                orig_SBIconListView_maximumIconCount = (NSUInteger (*)(id, SEL))method_getImplementation(mMaxIcons);
                method_setImplementation(mMaxIcons, (IMP)custom_SBIconListView_maximumIconCount);
            }
        }
        
        // Swizzle SBFloatingDockView
        Class floatDockClass = objc_getClass("SBFloatingDockView");
        if (floatDockClass) {
            Method mFLayout = class_getInstanceMethod(floatDockClass, @selector(layoutSubviews));
            if (mFLayout) {
                orig_SBFloatingDockView_layoutSubviews = (void (*)(id, SEL))method_getImplementation(mFLayout);
                method_setImplementation(mFLayout, (IMP)custom_SBFloatingDockView_layoutSubviews);
            }
            
            Method mFHit = class_getInstanceMethod(floatDockClass, @selector(hitTest:withEvent:));
            if (mFHit) {
                orig_SBFloatingDockView_hitTest = (UIView *(*)(id, SEL, CGPoint, UIEvent *))method_getImplementation(mFHit);
                method_setImplementation(mFHit, (IMP)custom_SBFloatingDockView_hitTest);
            }
        }
    }
}
