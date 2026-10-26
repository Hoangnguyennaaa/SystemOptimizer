#import "Tweak.h"

// MARK: - Global Configurations
static BOOL kEnabled = YES;
static BOOL p_dragModeEnabled = NO;
static NSInteger kDockMode = 0; // 0 = Tự động (Auto-detect), 1 = Dock gốc độc lập, 2 = FloatingDock
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

static BOOL isLayingOutDock = NO;

// MARK: - FloatingDock Active Detection & Mode Resolver (Hỗ trợ hoàn hảo iPhone 7 Plus & A10)
static BOOL isFloatingDockActive(void) {
    Class fdc = objc_getClass("SBFloatingDockController");
    if (fdc) {
        @try {
            // isFloatingDockSupported là CLASS method (+) trên SBFloatingDockController
            if ([fdc respondsToSelector:@selector(isFloatingDockSupported)]) {
                BOOL (*msgFunc)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
                if (msgFunc(fdc, @selector(isFloatingDockSupported))) {
                    return YES;
                }
            }
        } @catch (NSException *e) {}
    }
    return NO;
}

static BOOL isUsingFloatingDock(void) {
    if (kDockMode == 1) return NO; // Ép dùng Dock gốc độc lập
    if (kDockMode == 2) return YES; // Ép dùng FloatingDock
    return isFloatingDockActive();  // Tự động nhận diện
}

// MARK: - Preference Management
static void loadPreferences(void) {
    NSString *prefPath = PREF_PATH_ROOTLESS;
    if (![[NSFileManager defaultManager] fileExistsAtPath:prefPath]) {
        prefPath = PREF_PATH_ROOTFUL;
    }
    
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefPath];
    if (prefs) {
        kEnabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        p_dragModeEnabled = prefs[@"dragModeEnabled"] ? [prefs[@"dragModeEnabled"] boolValue] : NO;
        kDockMode = prefs[@"dockMode"] ? [prefs[@"dockMode"] integerValue] : 0;
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

static void triggerHapticFeedback(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen prepare];
        [gen impactOccurred];
    });
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
    // Đảm bảo không bao giờ vượt quá chiều cao màn hình iPhone 7 Plus (736)
    if (h > screenBounds.size.height - 100.0) {
        h = screenBounds.size.height - 100.0;
    }
    CGFloat x;
    if (kDockSide == 0) { // Bám cạnh Trái
        x = kRightMargin;
    } else { // Bám cạnh Phải
        x = screenBounds.size.width - w - kRightMargin;
    }
    CGFloat y = ((screenBounds.size.height - h) / 2.0) + kVerticalOffset;
    if (y < 40.0) y = 40.0;
    if (y + h > screenBounds.size.height - 40.0) y = screenBounds.size.height - h - 40.0;
    return CGRectMake(x, y, w, h);
}

static void applyVerticalIconLayout(UIView *containerView, CGFloat dockW, CGFloat dockH) {
    if (!containerView) return;
    
    CGRect targetContainerFrame = CGRectMake(0, 0, dockW, dockH);
    if (!CGRectEqualToRect(containerView.frame, targetContainerFrame)) {
        containerView.frame = targetContainerFrame;
    }
    containerView.clipsToBounds = NO;
    
    Class iconViewClass = objc_getClass("SBIconView");
    NSMutableArray<UIView *> *icons = [NSMutableArray array];
    for (UIView *sub in containerView.subviews) {
        if ([sub isKindOfClass:iconViewClass]) {
            [icons addObject:sub];
        }
    }
    
    NSUInteger count = icons.count;
    if (count == 0) return;
    
    // Giới hạn số icon hiển thị theo cài đặt nếu cần
    if (kDockIconCount > 0 && count > (NSUInteger)kDockIconCount) {
        count = (NSUInteger)kDockIconCount;
    }
    
    CGFloat topPadding = 24.0;
    CGFloat bottomPadding = 24.0;
    CGFloat availableHeight = dockH - topPadding - bottomPadding;
    CGFloat slotHeight = availableHeight / (CGFloat)count;
    
    for (NSUInteger i = 0; i < icons.count; i++) {
        UIView *iconView = icons[i];
        if (i < count) {
            if (iconView.hidden) iconView.hidden = NO;
            CGFloat centerY = topPadding + (i * slotHeight) + (slotHeight / 2.0);
            CGPoint targetCenter = CGPointMake(dockW / 2.0, centerY);
            
            if (!CGPointEqualToPoint(iconView.center, targetCenter)) {
                iconView.center = targetCenter;
            }
            
            CGFloat maxSlotScale = (slotHeight * 0.88) / 60.0;
            CGFloat effectiveScale = MIN(kDockIconScale, maxSlotScale);
            if (effectiveScale < 0.40) effectiveScale = 0.40;
            CGAffineTransform targetTransform = CGAffineTransformMakeScale(effectiveScale, effectiveScale);
            if (!CGAffineTransformEqualToTransform(iconView.transform, targetTransform)) {
                iconView.transform = targetTransform;
            }
            
            if ([iconView respondsToSelector:@selector(setLabelHidden:)]) {
                [((SBIconView *)iconView) setLabelHidden:kHideDockLabels];
            }
        } else {
            if (!iconView.hidden) iconView.hidden = YES;
        }
    }
}

// MARK: - Dedicated Capsule Setup (Tối ưu shadowPath triệt để loại bỏ giật lag)
static void setupCapsuleBackground(UIView *dockView) {
    if (!dockView) return;
    
    UIVisualEffectView *pill = [dockView viewWithTag:887766];
    
    // Chế độ trong suốt hoàn toàn hoặc tắt nền
    if (kDockBlurStyle == 3 || !kDockBlurEnabled) {
        if (pill) pill.hidden = YES;
        dockView.layer.shadowOpacity = 0.0;
        dockView.layer.shadowPath = nil;
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
    if (!CGRectEqualToRect(pill.frame, dockView.bounds)) {
        pill.frame = dockView.bounds;
    }
    CGFloat radius = (kCornerRadius > 0) ? kCornerRadius : (dockView.bounds.size.width / 2.0);
    pill.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) {
        pill.layer.cornerCurve = kCACornerCurveContinuous;
    }
    pill.layer.masksToBounds = YES;
    pill.alpha = kDockBlurAlpha;
    
    // Viền sáng
    if (p_dragModeEnabled) {
        pill.layer.borderWidth = 2.0;
        pill.layer.borderColor = [UIColor systemGreenColor].CGColor;
    } else if (kDockBorderEnabled) {
        pill.layer.borderWidth = kDockBorderWidth;
        pill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    } else {
        pill.layer.borderWidth = 0.0;
    }
    
    // Đổ bóng nổi khối (Tối ưu shadowPath để CoreAnimation không render off-screen gây tụt fps)
    if (kDockShadowEnabled && !p_dragModeEnabled) {
        dockView.layer.shadowColor = [UIColor blackColor].CGColor;
        dockView.layer.shadowOpacity = 0.35;
        dockView.layer.shadowOffset = CGSizeMake((kDockSide == 0 ? 3.0 : -3.0), 4.0);
        dockView.layer.shadowRadius = 12.0;
        dockView.layer.masksToBounds = NO;
        dockView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:dockView.bounds cornerRadius:radius].CGPath;
    } else {
        dockView.layer.shadowOpacity = 0.0;
        dockView.layer.shadowPath = nil;
    }
}

// MARK: - Interactive Pan & Pinch Handlers
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

static void dynamic_handleDuoDockPan(id self, SEL _cmd, UIPanGestureRecognizer *pan) {
    handleDockPanGesture(self, pan);
}

static void dynamic_handleDuoDockPinch(id self, SEL _cmd, UIPinchGestureRecognizer *pinch) {
    handleDockPinchGesture(self, pinch);
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

// MARK: - Safe Swizzle Helper (Tương thích 100% ARM64 trên iPhone 7 Plus)
static void SafeSwizzle(Class cls, SEL sel, IMP newIMP, IMP *origIMP) {
    if (!cls) return;
    Method origMethod = class_getInstanceMethod(cls, sel);
    if (!origMethod) return;
    
    *origIMP = method_getImplementation(origMethod);
    const char *types = method_getTypeEncoding(origMethod);
    
    if (class_addMethod(cls, sel, newIMP, types)) {
        // Method added to subclass
    } else {
        method_setImplementation(origMethod, newIMP);
    }
}

// MARK: - SBRootFolderView Hooks (Giữ nguyên frame tính toán an toàn cho iPhone 7 Plus)
static CGRect (*orig_SBRootFolderView_frameForDockView)(id, SEL);
static CGRect custom_SBRootFolderView_frameForDockView(id self, SEL _cmd) {
    if (orig_SBRootFolderView_frameForDockView) {
        return orig_SBRootFolderView_frameForDockView(self, _cmd);
    }
    return CGRectZero;
}

// MARK: - SBIconListView Hooks (Chống đè icon màn hình chính một cách an toàn)
static UIEdgeInsets (*orig_SBIconListView_layoutInsetsForOrientation)(id, SEL, NSInteger);
static UIEdgeInsets custom_SBIconListView_layoutInsetsForOrientation(UIView *self, SEL _cmd, NSInteger orientation) {
    UIEdgeInsets insets = UIEdgeInsetsZero;
    if (orig_SBIconListView_layoutInsetsForOrientation) {
        insets = orig_SBIconListView_layoutInsetsForOrientation(self, _cmd, orientation);
    }
    if (!kEnabled) return insets;
    
    @try {
        NSString *loc = nil;
        if ([self respondsToSelector:@selector(iconLocation)]) {
            loc = [self performSelector:@selector(iconLocation)];
        }
        BOOL isDock = NO;
        if ([self respondsToSelector:@selector(isDock)]) {
            isDock = ((BOOL (*)(id, SEL))objc_msgSend)(self, @selector(isDock));
        }
        
        // Chỉ can thiệp lưới icon của trang chính màn hình (Root), không can thiệp dock hay thư mục con
        if (!isDock && (!loc || [loc isEqualToString:@"SBIconLocationRoot"])) {
            CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
            
            if (kHomeCompressGrid) {
                CGFloat dockOccupied = (kHomeRightInset > 0) ? kHomeRightInset : (kDockWidth + kRightMargin + 10.0);
                CGFloat maxInset = screenWidth - 240.0 - 14.0;
                if (maxInset > 20.0 && dockOccupied > maxInset) {
                    dockOccupied = maxInset;
                }
                
                if (kDockSide == 0) { // Dock ở bên Trái -> Lùi lề Trái của lưới icon
                    insets.left = dockOccupied;
                    if (insets.right > 14.0) insets.right = 12.0;
                } else { // Dock ở bên Phải -> Lùi lề Phải của lưới icon
                    insets.right = dockOccupied;
                    if (insets.left > 14.0) insets.left = 12.0;
                }
            }
        }
    } @catch (NSException *e) {}
    
    return insets;
}

// MARK: - SBDockView Hooks (Xử lý khi chạy chế độ Dock gốc trên iPhone 7 Plus)
static void (*orig_SBDockView_layoutSubviews)(id, SEL);
static void custom_SBDockView_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_SBDockView_layoutSubviews) {
        orig_SBDockView_layoutSubviews(self, _cmd);
    }
    if (!kEnabled) return;
    if (isLayingOutDock) return;
    
    @try {
        if (isUsingFloatingDock()) {
            // Khi đang dùng FloatingDock, ẩn an toàn SBDockView để không đè lên nhau
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
        if (!p_dragModeEnabled) {
            if (fabs(self.frame.origin.x - dockFrame.origin.x) > 0.5 ||
                fabs(self.frame.origin.y - dockFrame.origin.y) > 0.5 ||
                fabs(self.frame.size.width - dockFrame.size.width) > 0.5 ||
                fabs(self.frame.size.height - dockFrame.size.height) > 0.5) {
                self.frame = dockFrame;
            }
        }
        
        // Ẩn nền mờ ngang mặc định của Dock Apple
        UIView *bg = nil;
        if ([self respondsToSelector:@selector(backgroundView)]) {
            bg = [self valueForKey:@"backgroundView"];
        }
        if (!bg) {
            @try { bg = [self valueForKey:@"_backgroundView"]; } @catch (NSException *e) {}
        }
        if (bg) {
            bg.hidden = YES;
            bg.alpha = 0.0;
        }
        
        setupCapsuleBackground(self);
        attachInteractiveGestures(self);
        
        UIView *iconListView = nil;
        if ([self respondsToSelector:@selector(dockIconListView)]) {
            iconListView = [self valueForKey:@"dockIconListView"];
        }
        if (!iconListView) {
            @try { iconListView = [self valueForKey:@"_iconListView"]; } @catch (NSException *e) {}
        }
        if (iconListView) {
            applyVerticalIconLayout(iconListView, self.bounds.size.width, self.bounds.size.height);
        }
        isLayingOutDock = NO;
    } @catch (NSException *e) {
        isLayingOutDock = NO;
    }
}

// MARK: - SBFloatingDockView Hooks (Xử lý khi chạy cùng FloatingDockXVI trên iPhone 7 Plus)
static void (*orig_SBFloatingDockView_layoutSubviews)(id, SEL);
static void custom_SBFloatingDockView_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_SBFloatingDockView_layoutSubviews) {
        orig_SBFloatingDockView_layoutSubviews(self, _cmd);
    }
    if (!kEnabled) return;
    if (isLayingOutDock) return;
    
    @try {
        if (!isUsingFloatingDock()) {
            // Khi người dùng chọn dùng Dock gốc độc lập:
            // Đưa SBFloatingDockView ra khỏi màn hình an toàn mà không setHidden:YES (tránh crash FloatingDockXVI)
            self.alpha = 0.0;
            self.userInteractionEnabled = NO;
            self.frame = CGRectMake(0, -9999, 0, 0);
            return;
        }
        
        isLayingOutDock = YES;
        self.hidden = NO;
        self.alpha = 1.0;
        
        CGRect dockFrame = calculateDuoDockFrame();
        if (!p_dragModeEnabled) {
            if (fabs(self.frame.origin.x - dockFrame.origin.x) > 0.5 ||
                fabs(self.frame.origin.y - dockFrame.origin.y) > 0.5 ||
                fabs(self.frame.size.width - dockFrame.size.width) > 0.5 ||
                fabs(self.frame.size.height - dockFrame.size.height) > 0.5) {
                self.frame = dockFrame;
            }
        }
        
        setupCapsuleBackground(self);
        attachInteractiveGestures(self);
        
        UIView *platter = nil;
        @try { platter = [self valueForKey:@"_mainPlatterView"]; } @catch (NSException *e) {}
        if (platter) {
            platter.hidden = YES;
            platter.alpha = 0.0;
        }
        
        UIView *divider = nil;
        @try { divider = [self valueForKey:@"_dividerView"]; } @catch (NSException *e) {}
        if (divider) {
            divider.hidden = YES;
            divider.alpha = 0.0;
        }
        
        UIView *userIcons = nil;
        if ([self respondsToSelector:@selector(userIconListView)]) {
            userIcons = [self valueForKey:@"userIconListView"];
        }
        if (!userIcons) {
            @try { userIcons = [self valueForKey:@"_userIconListView"]; } @catch (NSException *e) {}
        }
        if (userIcons) {
            applyVerticalIconLayout(userIcons, self.bounds.size.width, self.bounds.size.height);
        }
        isLayingOutDock = NO;
    } @catch (NSException *e) {
        isLayingOutDock = NO;
    }
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
        
        // Swizzle SBDockView (Dock gốc độc lập)
        Class dockViewClass = objc_getClass("SBDockView");
        if (dockViewClass) {
            class_addMethod(dockViewClass, @selector(handleDuoDockPan:), (IMP)dynamic_handleDuoDockPan, "v@:@");
            class_addMethod(dockViewClass, @selector(handleDuoDockPinch:), (IMP)dynamic_handleDuoDockPinch, "v@:@");
            SafeSwizzle(dockViewClass, @selector(layoutSubviews), (IMP)custom_SBDockView_layoutSubviews, (IMP *)&orig_SBDockView_layoutSubviews);
        }
        
        // Swizzle SBRootFolderView (Giữ an toàn tuyệt đối cho SpringBoard trên iPhone 7 Plus)
        Class rootFolderClass = objc_getClass("SBRootFolderView");
        if (rootFolderClass) {
            SafeSwizzle(rootFolderClass, @selector(_frameForDockView), (IMP)custom_SBRootFolderView_frameForDockView, (IMP *)&orig_SBRootFolderView_frameForDockView);
        }
        
        // Swizzle SBIconListView (Chống đè icon màn hình chính)
        Class iconListViewClass = objc_getClass("SBIconListView");
        if (iconListViewClass) {
            SafeSwizzle(iconListViewClass, @selector(layoutInsetsForOrientation:), (IMP)custom_SBIconListView_layoutInsetsForOrientation, (IMP *)&orig_SBIconListView_layoutInsetsForOrientation);
        }
        
        // Swizzle SBFloatingDockView (Hỗ trợ FloatingDockXVI không lag, không Safe Mode)
        Class floatDockClass = objc_getClass("SBFloatingDockView");
        if (floatDockClass) {
            class_addMethod(floatDockClass, @selector(handleDuoDockPan:), (IMP)dynamic_handleDuoDockPan, "v@:@");
            class_addMethod(floatDockClass, @selector(handleDuoDockPinch:), (IMP)dynamic_handleDuoDockPinch, "v@:@");
            SafeSwizzle(floatDockClass, @selector(layoutSubviews), (IMP)custom_SBFloatingDockView_layoutSubviews, (IMP *)&orig_SBFloatingDockView_layoutSubviews);
        }
    }
}
