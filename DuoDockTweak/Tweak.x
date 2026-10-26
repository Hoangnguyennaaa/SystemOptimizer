#import "Tweak.h"

// MARK: - Global Configurations
static BOOL kEnabled = YES;
static BOOL p_dragModeEnabled = NO;
static NSInteger kDockSide = 1; // 0 = Trái (Left), 1 = Phải (Right - Default)
static NSInteger kDockIconCount = 4;
static CGFloat kDockIconScale = 0.85;
static CGFloat kDockWidth = 78.0;
static CGFloat kDockHeight = 330.0;
static CGFloat kRightMargin = 10.0;
static CGFloat kVerticalOffset = 0.0;
static CGFloat kCornerRadius = 39.0;
static CGFloat kDockBlurAlpha = 0.82;
static BOOL kDockBlurEnabled = YES;
static NSInteger kDockBlurStyle = 0; // 0 = Tối (Dark), 1 = Sáng (Light), 2 = Siêu mỏng (Ultra Thin), 3 = Trong suốt
static BOOL kDockBorderEnabled = NO;
static CGFloat kDockBorderWidth = 1.0;
static BOOL kDockShadowEnabled = YES;
static BOOL kHideDockLabels = YES;

static BOOL kHomeCompressGrid = YES;
static CGFloat kHomeRightInset = 88.0;
static BOOL kExpandBottomRows = YES;
static BOOL kCustomGridEnabled = NO;
static NSInteger kHomeRows = 7;
static NSInteger kHomeColumns = 4;
static CGFloat kHomeIconScale = 0.90;

static BOOL isLayingOutDock = NO;

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
        kDockSide = prefs[@"dockSide"] ? [prefs[@"dockSide"] integerValue] : 1;
        kDockIconCount = prefs[@"dockIconCount"] ? [prefs[@"dockIconCount"] integerValue] : 4;
        kDockIconScale = prefs[@"dockIconScale"] ? [prefs[@"dockIconScale"] doubleValue] : 0.85;
        kDockWidth = prefs[@"dockWidth"] ? [prefs[@"dockWidth"] doubleValue] : 78.0;
        kDockHeight = prefs[@"dockHeight"] ? [prefs[@"dockHeight"] doubleValue] : 330.0;
        kRightMargin = prefs[@"rightMargin"] ? [prefs[@"rightMargin"] doubleValue] : 10.0;
        kVerticalOffset = prefs[@"verticalOffset"] ? [prefs[@"verticalOffset"] doubleValue] : 0.0;
        kCornerRadius = prefs[@"cornerRadius"] ? [prefs[@"cornerRadius"] doubleValue] : (kDockWidth / 2.0);
        kDockBlurAlpha = prefs[@"dockBlurAlpha"] ? [prefs[@"dockBlurAlpha"] doubleValue] : 0.82;
        kDockBlurEnabled = prefs[@"dockBlurEnabled"] ? [prefs[@"dockBlurEnabled"] boolValue] : YES;
        kDockBlurStyle = prefs[@"dockBlurStyle"] ? [prefs[@"dockBlurStyle"] integerValue] : 0;
        kDockBorderEnabled = prefs[@"dockBorderEnabled"] ? [prefs[@"dockBorderEnabled"] boolValue] : NO;
        kDockBorderWidth = prefs[@"dockBorderWidth"] ? [prefs[@"dockBorderWidth"] doubleValue] : 1.0;
        kDockShadowEnabled = prefs[@"dockShadowEnabled"] ? [prefs[@"dockShadowEnabled"] boolValue] : YES;
        kHideDockLabels = prefs[@"hideDockLabels"] ? [prefs[@"hideDockLabels"] boolValue] : YES;
        
        kHomeCompressGrid = prefs[@"homeCompressGrid"] ? [prefs[@"homeCompressGrid"] boolValue] : YES;
        kHomeRightInset = prefs[@"homeRightInset"] ? [prefs[@"homeRightInset"] doubleValue] : 88.0;
        kExpandBottomRows = prefs[@"expandBottomRows"] ? [prefs[@"expandBottomRows"] boolValue] : YES;
        kCustomGridEnabled = prefs[@"customGridEnabled"] ? [prefs[@"customGridEnabled"] boolValue] : NO;
        kHomeRows = prefs[@"homeRows"] ? [prefs[@"homeRows"] integerValue] : 7;
        kHomeColumns = prefs[@"homeColumns"] ? [prefs[@"homeColumns"] integerValue] : 4;
        kHomeIconScale = prefs[@"homeIconScale"] ? [prefs[@"homeIconScale"] doubleValue] : 0.90;
    }
}

static void savePositionAndScale(CGFloat rightMargin, CGFloat verticalOffset, CGFloat iconScale, NSInteger dockSide) {
    NSString *path = PREF_PATH_ROOTLESS;
    NSString *dir = [path stringByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
    dict[@"rightMargin"] = @(rightMargin);
    dict[@"verticalOffset"] = @(verticalOffset);
    dict[@"dockIconScale"] = @(iconScale);
    dict[@"dockSide"] = @(dockSide);
    [dict writeToFile:path atomically:YES];
    
    kRightMargin = rightMargin;
    kVerticalOffset = verticalOffset;
    kDockIconScale = iconScale;
    kDockSide = dockSide;
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
    CGFloat x;
    if (kDockSide == 0) {
        x = kRightMargin;
    } else {
        x = screenBounds.size.width - w - kRightMargin;
    }
    CGFloat y = ((screenBounds.size.height - h) / 2.0) + kVerticalOffset;
    return CGRectMake(x, y, w, h);
}

static void applyVerticalIconLayout(UIView *containerView, CGFloat dockW, CGFloat dockH) {
    if (!containerView) return;
    
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
    
    if (kDockIconCount > 0 && count > (NSUInteger)kDockIconCount) {
        count = (NSUInteger)kDockIconCount;
    }
    
    CGFloat topPadding = 24.0;
    CGFloat bottomPadding = 24.0;
    CGFloat availableHeight = dockH - topPadding - bottomPadding;
    CGFloat slotHeight = availableHeight / (CGFloat)count;
    
    for (NSUInteger i = 0; i < icons.count; i++) {
        SBIconView *iconView = icons[i];
        if (i < count) {
            iconView.hidden = NO;
            CGFloat centerY = topPadding + (i * slotHeight) + (slotHeight / 2.0);
            CGPoint targetCenter = CGPointMake(dockW / 2.0, centerY);
            
            iconView.center = targetCenter;
            iconView.transform = CGAffineTransformMakeScale(kDockIconScale, kDockIconScale);
            
            if ([iconView respondsToSelector:@selector(setLabelHidden:)]) {
                [iconView setLabelHidden:kHideDockLabels];
            }
        } else {
            iconView.hidden = YES;
        }
    }
}

// MARK: - Dedicated Capsule Setup
static void setupCapsuleBackground(UIView *dockView) {
    if (!dockView) return;
    
    UIVisualEffectView *pill = [dockView viewWithTag:887766];
    
    if (kDockBlurStyle == 3 || !kDockBlurEnabled) {
        if (pill) pill.hidden = YES;
        dockView.layer.shadowOpacity = 0.0;
        return;
    }
    
    UIBlurEffectStyle style = UIBlurEffectStyleSystemMaterialDark;
    if (kDockBlurStyle == 1) {
        style = UIBlurEffectStyleSystemMaterialLight;
    } else if (kDockBlurStyle == 2) {
        style = UIBlurEffectStyleSystemUltraThinMaterial;
    }
    
    if (!pill) {
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:style];
        pill = [[UIVisualEffectView alloc] initWithEffect:blur];
        pill.tag = 887766;
        pill.userInteractionEnabled = NO;
        [dockView insertSubview:pill atIndex:0];
    } else {
        pill.effect = [UIBlurEffect effectWithStyle:style];
    }
    
    pill.hidden = NO;
    pill.frame = dockView.bounds;
    CGFloat radius = (kCornerRadius > 0) ? kCornerRadius : (dockView.bounds.size.width / 2.0);
    pill.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) {
        pill.layer.cornerCurve = kCACornerCurveContinuous;
    }
    pill.layer.masksToBounds = YES;
    pill.alpha = kDockBlurAlpha;
    
    if (p_dragModeEnabled) {
        pill.layer.borderWidth = 2.0;
        pill.layer.borderColor = [UIColor systemGreenColor].CGColor;
    } else if (kDockBorderEnabled) {
        pill.layer.borderWidth = kDockBorderWidth;
        pill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    } else {
        pill.layer.borderWidth = 0.0;
    }
    
    if (kDockShadowEnabled && !p_dragModeEnabled) {
        dockView.layer.shadowColor = [UIColor blackColor].CGColor;
        dockView.layer.shadowOpacity = 0.35;
        dockView.layer.shadowOffset = CGSizeMake((kDockSide == 0 ? 3.0 : -3.0), 4.0);
        dockView.layer.shadowRadius = 12.0;
        dockView.layer.masksToBounds = NO;
    } else {
        dockView.layer.shadowOpacity = 0.0;
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
        CGFloat midX = dockView.center.x;
        NSInteger newSide = (midX < screenBounds.size.width / 2.0) ? 0 : 1;
        CGFloat newMargin;
        if (newSide == 0) {
            newMargin = CGRectGetMinX(dockView.frame);
            if (newMargin < 0) newMargin = 0;
        } else {
            newMargin = screenBounds.size.width - CGRectGetMaxX(dockView.frame);
            if (newMargin < 0) newMargin = 0;
        }
        CGFloat newVerticalOffset = dockView.center.y - (screenBounds.size.height / 2.0);
        
        savePositionAndScale(newMargin, newVerticalOffset, kDockIconScale, newSide);
        triggerHapticFeedback();
    }
}

static void handleDockPinchGesture(UIView *dockView, UIPinchGestureRecognizer *pinch) {
    if (pinch.state == UIGestureRecognizerStateBegan || pinch.state == UIGestureRecognizerStateChanged) {
        CGFloat newScale = kDockIconScale * pinch.scale;
        if (newScale >= 0.55 && newScale <= 1.25) {
            kDockIconScale = newScale;
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
        savePositionAndScale(kRightMargin, kVerticalOffset, kDockIconScale, kDockSide);
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
        // Cho dock độc lập: Đặt frame dock ảo ở mép dưới để SBRootFolderView giải phóng 90pt diện tích đáy
        // và không ép pageControl lên giữa màn hình. SBDockView sẽ tự định vị sang cạnh trái hoặc phải.
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

// MARK: - Hook SBIconListView (Anti-Overlap & Expand Bottom & Custom Grid)
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
        
        // 1. Thu hẹp lề để nhường chỗ cho DuoDock, không bao giờ để Dock đè lên icon
        if (kHomeCompressGrid) {
            CGFloat dockOccupied = (kHomeRightInset > 0) ? kHomeRightInset : (kDockWidth + kRightMargin + 10.0);
            CGFloat maxInset = screenWidth - 240.0 - 14.0;
            if (maxInset > 20.0 && dockOccupied > maxInset) {
                dockOccupied = maxInset;
            }
            if (kDockSide == 0) {
                insets.left = dockOccupied;
                if (insets.right > 14.0) insets.right = 12.0;
            } else {
                insets.right = dockOccupied;
                if (insets.left > 14.0) insets.left = 12.0;
            }
        }
        
        // 2. Tràn xuống đáy màn hình (chiếm chỗ của Dock cũ)
        if (kExpandBottomRows || kCustomGridEnabled) {
            insets.bottom = 12.0;
        }
    }
    return insets;
}

- (NSUInteger)maximumIconCount {
    if (kEnabled && kCustomGridEnabled) {
        if (!self.isDock && (!self.iconLocation || [self.iconLocation isEqualToString:@"SBIconLocationRoot"])) {
            return (NSUInteger)(kHomeRows * kHomeColumns);
        }
    }
    return %orig;
}

- (NSUInteger)iconRowsForCurrentOrientation {
    if (kEnabled && kCustomGridEnabled) {
        if (!self.isDock && (!self.iconLocation || [self.iconLocation isEqualToString:@"SBIconLocationRoot"])) {
            return (NSUInteger)kHomeRows;
        }
    }
    return %orig;
}

- (NSUInteger)iconColumnsForCurrentOrientation {
    if (kEnabled && kCustomGridEnabled) {
        if (!self.isDock && (!self.iconLocation || [self.iconLocation isEqualToString:@"SBIconLocationRoot"])) {
            return (NSUInteger)kHomeColumns;
        }
    }
    return %orig;
}

%end

// MARK: - Hook SBIconListGridLayoutConfiguration (Rows, Columns, Insets, Icon Sizing)
%hook SBIconListGridLayoutConfiguration

- (NSUInteger)numberOfPortraitRows {
    NSUInteger orig = %orig;
    if (kEnabled) {
        if (orig >= 5) {
            if (kCustomGridEnabled && kHomeRows >= 4 && kHomeRows <= 9) {
                return (NSUInteger)kHomeRows;
            }
            if (kExpandBottomRows) {
                return orig + 1;
            }
        }
    }
    return orig;
}

- (NSUInteger)numberOfPortraitColumns {
    NSUInteger orig = %orig;
    if (kEnabled && kCustomGridEnabled) {
        if (orig == 4 && kHomeColumns >= 3 && kHomeColumns <= 6) {
            return (NSUInteger)kHomeColumns;
        }
    }
    return orig;
}

- (SBIconImageInfo)iconImageInfo {
    SBIconImageInfo info = %orig;
    if (kEnabled && kCustomGridEnabled && kHomeIconScale >= 0.65 && kHomeIconScale <= 1.25) {
        info.size.width = round(info.size.width * kHomeIconScale);
        info.size.height = round(info.size.height * kHomeIconScale);
        info.continuousCornerRadius = round(info.continuousCornerRadius * kHomeIconScale);
    }
    return info;
}

- (UIEdgeInsets)portraitLayoutInsets {
    UIEdgeInsets insets = %orig;
    if (!kEnabled) return insets;
    
    if ((kExpandBottomRows || kCustomGridEnabled) && insets.bottom > 40.0) {
        insets.bottom = 14.0;
    }
    
    if (kHomeCompressGrid && insets.bottom > 0) {
        CGFloat dockOccupied = (kHomeRightInset > 0) ? kHomeRightInset : (kDockWidth + kRightMargin + 10.0);
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        CGFloat maxInset = screenWidth - 240.0 - 14.0;
        if (maxInset > 20.0 && dockOccupied > maxInset) {
            dockOccupied = maxInset;
        }
        if (kDockSide == 0) {
            insets.left = dockOccupied;
            if (insets.right > 14.0) insets.right = 12.0;
        } else {
            insets.right = dockOccupied;
            if (insets.left > 14.0) insets.left = 12.0;
        }
    }
    return insets;
}

%end

// MARK: - Hook SBDockView (Tối ưu 100% Native 120Hz mượt mà)
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
        isLayingOutDock = YES;
        self.hidden = NO;
        self.alpha = 1.0;
        
        CGRect dockFrame = calculateDuoDockFrame();
        if (!p_dragModeEnabled && !CGRectEqualToRect(self.frame, dockFrame)) {
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

// MARK: - Suppress FloatingDock (Vô hiệu hóa triệt để FloatingDockXVI để loại bỏ 100% giật lag)
%hook SBFloatingDockController

+ (BOOL)isFloatingDockSupported {
    if (kEnabled) return NO;
    return %orig;
}

- (BOOL)isFloatingDockSupported {
    if (kEnabled) return NO;
    return %orig;
}

%end

// MARK: - Suppress SBFloatingDockView
%hook SBFloatingDockView

- (void)layoutSubviews {
    if (kEnabled) {
        self.hidden = YES;
        self.alpha = 0.0;
        return;
    }
    %orig;
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
