#import "Tweak.h"

// MARK: - Global Configurations
static BOOL kEnabled = YES;
static BOOL p_dragModeEnabled = NO;
static NSInteger kDockMode = 0; // 0 = Auto-detect, 1 = Standalone, 2 = FloatingDock
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
static CGFloat kHomeRightInset = 88.0;
static BOOL kExpandBottomRows = YES;

static BOOL isLayingOutDock = NO;

// MARK: - FloatingDock Active Detection
static BOOL isFloatingDockActive(void) {
    Class fdc = objc_getClass("SBFloatingDockController");
    if (fdc) {
        @try {
            id ctrl = [fdc performSelector:@selector(sharedInstance)];
            if (ctrl && [ctrl respondsToSelector:@selector(isFloatingDockSupported)]) {
                BOOL sup = ((BOOL (*)(id, SEL))objc_msgSend)(ctrl, @selector(isFloatingDockSupported));
                if (sup) return YES;
            }
        } @catch (NSException *e) {}
    }
    return NO;
}

// MARK: - Preference Management
static void loadPreferences() {
    NSString *prefPath = PREF_PATH_ROOTLESS;
    if (![[NSFileManager defaultManager] fileExistsAtPath:prefPath]) {
        prefPath = PREF_PATH_ROOTFUL;
    }
    
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefPath];
    if (prefs) {
        kEnabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        p_dragModeEnabled = prefs[@"dragModeEnabled"] ? [prefs[@"dragModeEnabled"] boolValue] : NO;
        kDockMode = prefs[@"dockMode"] ? [prefs[@"dockMode"] integerValue] : 0;
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
        kHomeRightInset = prefs[@"homeRightInset"] ? [prefs[@"homeRightInset"] doubleValue] : 88.0;
        kExpandBottomRows = prefs[@"expandBottomRows"] ? [prefs[@"expandBottomRows"] boolValue] : YES;
    }
}

static void savePositionAndScale(CGFloat rightMargin, CGFloat verticalOffset, CGFloat iconScale) {
    NSString *path = PREF_PATH_ROOTLESS;
    NSString *dir = [path stringByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
    dict[@"rightMargin"] = @(rightMargin);
    dict[@"verticalOffset"] = @(verticalOffset);
    dict[@"dockIconScale"] = @(iconScale);
    [dict writeToFile:path atomically:YES];
    
    kRightMargin = rightMargin;
    kVerticalOffset = verticalOffset;
    kDockIconScale = iconScale;
}

static void triggerHapticFeedback() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen prepare];
        [gen impactOccurred];
    });
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
                [iconController relayout];
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
    
    // Đảm bảo containerView bao trọn khung của Dock để icon không bị bóp nghẹt
    containerView.frame = CGRectMake(0, 0, dockW, dockH);
    containerView.clipsToBounds = NO;
    
    NSMutableArray<SBIconView *> *icons = [NSMutableArray array];
    for (UIView *sub in containerView.subviews) {
        if ([sub isKindOfClass:%c(SBIconView)]) {
            [icons addObject:(SBIconView *)sub];
        }
    }
    
    NSUInteger count = icons.count;
    if (count == 0) return;
    
    CGFloat topPadding = 24.0;
    CGFloat bottomPadding = 24.0;
    CGFloat availableHeight = dockH - topPadding - bottomPadding;
    CGFloat slotHeight = availableHeight / (CGFloat)count;
    
    for (NSUInteger i = 0; i < count; i++) {
        SBIconView *iconView = icons[i];
        CGFloat centerY = topPadding + (i * slotHeight) + (slotHeight / 2.0);
        CGPoint targetCenter = CGPointMake(dockW / 2.0, centerY);
        
        // Không đụng vào iconView.bounds để tránh co lại thành chấm nhỏ!
        iconView.center = targetCenter;
        iconView.transform = CGAffineTransformMakeScale(kDockIconScale, kDockIconScale);
        
        if ([iconView respondsToSelector:@selector(setLabelHidden:)]) {
            [iconView setLabelHidden:YES];
        }
    }
}

// MARK: - Dedicated Capsule Setup
static void setupCapsuleBackground(UIView *dockView) {
    if (!dockView) return;
    
    UIVisualEffectView *pill = [dockView viewWithTag:887766];
    if (!pill) {
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark];
        pill = [[UIVisualEffectView alloc] initWithEffect:blur];
        pill.tag = 887766;
        pill.userInteractionEnabled = NO;
        [dockView insertSubview:pill atIndex:0];
    }
    
    pill.frame = dockView.bounds;
    CGFloat radius = (kCornerRadius > 0) ? kCornerRadius : (dockView.bounds.size.width / 2.0);
    pill.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) {
        pill.layer.cornerCurve = kCACornerCurveContinuous;
    }
    pill.layer.masksToBounds = YES;
    pill.alpha = kDockBlurAlpha;
    pill.hidden = !kDockBlurEnabled;
    
    // Viền xanh lá hiển thị khi đang ở chế độ kéo thả căn chỉnh trực tiếp
    if (p_dragModeEnabled) {
        pill.layer.borderWidth = 2.0;
        pill.layer.borderColor = [UIColor systemGreenColor].CGColor;
    } else {
        pill.layer.borderWidth = 0.0;
    }
}

// MARK: - Direct Drag & Pinch Gesture Handlers
static void handleDockPanGesture(UIView *dockView, UIPanGestureRecognizer *pan) {
    CGPoint translation = [pan translationInView:dockView.superview];
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
        dockView.center = CGPointMake(dockView.center.x + translation.x, dockView.center.y + translation.y);
        [pan setTranslation:CGPointZero inView:dockView.superview];
    } else if (pan.state == UIGestureRecognizerStateEnded) {
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        CGFloat newRightMargin = screenBounds.size.width - CGRectGetMaxX(dockView.frame);
        CGFloat newVerticalOffset = dockView.center.y - (screenBounds.size.height / 2.0);
        
        savePositionAndScale(newRightMargin, newVerticalOffset, kDockIconScale);
        triggerHapticFeedback();
    }
}

static void handleDockPinchGesture(UIView *dockView, UIPinchGestureRecognizer *pinch) {
    if (pinch.state == UIGestureRecognizerStateBegan || pinch.state == UIGestureRecognizerStateChanged) {
        CGFloat newScale = kDockIconScale * pinch.scale;
        if (newScale >= 0.55 && newScale <= 1.25) {
            kDockIconScale = newScale;
            // Áp dụng scale tức thì lên các icon
            UIView *iconList = nil;
            if ([dockView respondsToSelector:@selector(dockIconListView)]) {
                iconList = [dockView valueForKey:@"dockIconListView"];
            }
            if (!iconList) {
                @try { iconList = [dockView valueForKey:@"_userIconListView"]; } @catch (NSException *e) {}
            }
            if (!iconList) {
                @try { iconList = [dockView valueForKey:@"_iconListView"]; } @catch (NSException *e) {}
            }
            if (iconList) {
                applyVerticalIconLayout(iconList, dockView.bounds.size.width, dockView.bounds.size.height);
            }
        }
        pinch.scale = 1.0;
    } else if (pinch.state == UIGestureRecognizerStateEnded) {
        savePositionAndScale(kRightMargin, kVerticalOffset, kDockIconScale);
        triggerHapticFeedback();
    }
}

static void attachInteractiveGestures(UIView *dockView) {
    if (!dockView) return;
    
    UIPanGestureRecognizer *pan = objc_getAssociatedObject(dockView, "DuoDockPan");
    if (!pan) {
        pan = [[UIPanGestureRecognizer alloc] initWithTarget:dockView action:@selector(handleDuoDockPan:)];
        [dockView addGestureRecognizer:pan];
        objc_setAssociatedObject(dockView, "DuoDockPan", pan, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    pan.enabled = p_dragModeEnabled;
    
    UIPinchGestureRecognizer *pinch = objc_getAssociatedObject(dockView, "DuoDockPinch");
    if (!pinch) {
        pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:dockView action:@selector(handleDuoDockPinch:)];
        [dockView addGestureRecognizer:pinch];
        objc_setAssociatedObject(dockView, "DuoDockPinch", pinch, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    pinch.enabled = p_dragModeEnabled;
}

// MARK: - Hook SBRootFolderView
%hook SBRootFolderView

- (CGRect)_frameForDockView {
    if (kEnabled) {
        BOOL useFloating = (kDockMode == 2) || (kDockMode == 0 && isFloatingDockActive());
        if (useFloating) {
            return %orig;
        }
        // Cho dock độc lập: Đặt frame dock ảo ở mép dưới để SBRootFolderView giải phóng 90pt diện tích đáy
        // và không ép pageControl lên giữa màn hình. SBDockView sẽ tự định vị sang cạnh phải.
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        return CGRectMake(0, screenBounds.size.height, screenBounds.size.width, 0);
    }
    return %orig;
}

- (CGRect)_frameForIconListViewAtIndex:(NSUInteger)arg1 {
    CGRect orig = %orig;
    if (!kEnabled) return orig;
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    // GIỮ NGUYÊN orig.origin.x để mỗi trang (index 0, 1, 2...) có vị trí phân trang chính xác trong UIScrollView!
    // Kéo dài chiều cao xuống tận đáy: chỉ chừa 18pt cho thanh Home bar / page dots
    CGFloat bottomPadding = (kExpandBottomRows) ? 18.0 : 48.0;
    orig.size.height = screenBounds.size.height - orig.origin.y - bottomPadding;
    return orig;
}

%end

// MARK: - Hook SBIconListView (Anti-Overlap & Expand Bottom)
%hook SBIconListView

- (UIEdgeInsets)layoutInsetsForOrientation:(NSInteger)orientation {
    UIEdgeInsets insets = %orig;
    if (!kEnabled) return insets;
    
    NSString *loc = nil;
    if ([self respondsToSelector:@selector(iconLocation)]) {
        loc = [self iconLocation];
    }
    BOOL isDock = NO;
    if ([self respondsToSelector:@selector(isDock)]) {
        isDock = [self isDock];
    }
    
    if (!isDock && (!loc || [loc isEqualToString:@"SBIconLocationRoot"])) {
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        
        // 1. Thu hẹp lề phải để nhường chỗ cho DuoDock, không bao giờ để Dock đè lên icon
        if (kHomeCompressGrid) {
            CGFloat dockOccupied = (kHomeRightInset > 0) ? kHomeRightInset : (kDockWidth + kRightMargin + 10.0);
            CGFloat maxRight = screenWidth - insets.left - 240.0;
            if (maxRight > 20.0 && dockOccupied > maxRight) {
                dockOccupied = maxRight;
            }
            insets.right = dockOccupied;
            
            if (insets.left > 14.0) {
                insets.left = 12.0;
            }
        }
        
        // 2. Tràn xuống đáy màn hình (chiếm chỗ của Dock cũ)
        if (kExpandBottomRows) {
            insets.bottom = 12.0;
        }
    }
    return insets;
}

%end

// MARK: - Hook SBIconListGridLayoutConfiguration (Expand Rows & Insets)
%hook SBIconListGridLayoutConfiguration

- (NSUInteger)numberOfPortraitRows {
    NSUInteger orig = %orig;
    if (kEnabled && kExpandBottomRows) {
        if (orig >= 5) {
            return orig + 1;
        }
    }
    return orig;
}

- (UIEdgeInsets)portraitLayoutInsets {
    UIEdgeInsets insets = %orig;
    if (!kEnabled) return insets;
    
    if (kExpandBottomRows && insets.bottom > 40.0) {
        insets.bottom = 14.0;
    }
    
    if (kHomeCompressGrid && insets.bottom > 0) {
        CGFloat dockOccupied = (kHomeRightInset > 0) ? kHomeRightInset : (kDockWidth + kRightMargin + 10.0);
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        CGFloat maxRight = screenWidth - insets.left - 240.0;
        if (maxRight > 20.0 && dockOccupied > maxRight) {
            dockOccupied = maxRight;
        }
        insets.right = dockOccupied;
        if (insets.left > 14.0) {
            insets.left = 12.0;
        }
    }
    return insets;
}

%end

// MARK: - Hook SBDockView
%hook SBDockView

%new
- (void)handleDuoDockPan:(UIPanGestureRecognizer *)pan {
    handleDockPanGesture(self, pan);
}

%new
- (void)handleDuoDockPinch:(UIPinchGestureRecognizer *)pinch {
    handleDockPinchGesture(self, pinch);
}

- (void)layoutSubviews {
    %orig;
    if (!kEnabled) return;
    if (isLayingOutDock) return;
    
    @try {
        BOOL useFloating = (kDockMode == 2) || (kDockMode == 0 && isFloatingDockActive());
        if (useFloating) {
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
        
        setupCapsuleBackground(self);
        attachInteractiveGestures(self);
        
        SBDockIconListView *iconListView = nil;
        if ([self respondsToSelector:@selector(dockIconListView)]) {
            iconListView = [self dockIconListView];
        }
        if (!iconListView && [self respondsToSelector:@selector(valueForKey:)]) {
            @try { iconListView = [self valueForKey:@"_iconListView"]; } @catch (NSException *e) {}
        }
        if (iconListView) {
            applyVerticalIconLayout(iconListView, dockFrame.size.width, dockFrame.size.height);
        }
        isLayingOutDock = NO;
    } @catch (NSException *e) {
        isLayingOutDock = NO;
    }
}

%end

// MARK: - Hook SBFloatingDockView
%hook SBFloatingDockView

%new
- (void)handleDuoDockPan:(UIPanGestureRecognizer *)pan {
    handleDockPanGesture(self, pan);
}

%new
- (void)handleDuoDockPinch:(UIPinchGestureRecognizer *)pinch {
    handleDockPinchGesture(self, pinch);
}

- (void)layoutSubviews {
    %orig;
    if (!kEnabled) return;
    if (isLayingOutDock) return;
    
    @try {
        BOOL useFloating = (kDockMode == 2) || (kDockMode == 0 && isFloatingDockActive());
        if (!useFloating) {
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
        
        setupCapsuleBackground(self);
        attachInteractiveGestures(self);
        
        UIView *platter = [self valueForKey:@"_mainPlatterView"];
        if (platter) {
            platter.hidden = YES; // Dùng pill riêng để không bị FloatingDockXVI ghi đè
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
            applyVerticalIconLayout(userIcons, dockFrame.size.width, dockFrame.size.height);
        }
        isLayingOutDock = NO;
    } @catch (NSException *e) {
        isLayingOutDock = NO;
    }
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
