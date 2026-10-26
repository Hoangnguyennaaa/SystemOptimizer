#import "Tweak.h"

// MARK: - Global Configuration Variables
static BOOL kEnabled = YES;
static NSInteger kDockIconCount = 4;
static CGFloat kDockIconScale = 0.85;
static CGFloat kDockWidth = 74.0;
static CGFloat kDockHeight = 320.0;
static CGFloat kRightMargin = 10.0;
static CGFloat kVerticalOffset = 0.0;
static CGFloat kCornerRadius = 37.0;
static CGFloat kDockBlurAlpha = 0.82;
static BOOL kDockBlurEnabled = YES;
static BOOL kExpandBottomRows = YES;
static CGFloat kHomeRightInset = 80.0;

// MARK: - Preference Loader
static void loadPreferences() {
    NSString *prefPath = PREF_PATH_ROOTLESS;
    if (![[NSFileManager defaultManager] fileExistsAtPath:prefPath]) {
        prefPath = PREF_PATH_ROOTFUL;
    }
    
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefPath];
    if (prefs) {
        kEnabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        kDockIconCount = prefs[@"dockIconCount"] ? [prefs[@"dockIconCount"] integerValue] : 4;
        kDockIconScale = prefs[@"dockIconScale"] ? [prefs[@"dockIconScale"] doubleValue] : 0.85;
        kDockWidth = prefs[@"dockWidth"] ? [prefs[@"dockWidth"] doubleValue] : 74.0;
        kDockHeight = prefs[@"dockHeight"] ? [prefs[@"dockHeight"] doubleValue] : 320.0;
        kRightMargin = prefs[@"rightMargin"] ? [prefs[@"rightMargin"] doubleValue] : 10.0;
        kVerticalOffset = prefs[@"verticalOffset"] ? [prefs[@"verticalOffset"] doubleValue] : 0.0;
        kCornerRadius = prefs[@"cornerRadius"] ? [prefs[@"cornerRadius"] doubleValue] : (kDockWidth / 2.0);
        kDockBlurAlpha = prefs[@"dockBlurAlpha"] ? [prefs[@"dockBlurAlpha"] doubleValue] : 0.82;
        kDockBlurEnabled = prefs[@"dockBlurEnabled"] ? [prefs[@"dockBlurEnabled"] boolValue] : YES;
        kExpandBottomRows = prefs[@"expandBottomRows"] ? [prefs[@"expandBottomRows"] boolValue] : YES;
        kHomeRightInset = prefs[@"homeRightInset"] ? [prefs[@"homeRightInset"] doubleValue] : 80.0;
    }
}

static void preferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    loadPreferences();
    
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            SBIconController *iconController = [%c(SBIconController) sharedInstance];
            if ([iconController respondsToSelector:@selector(relayout)]) {
                [UIView animateWithDuration:0.35 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                    [iconController relayout];
                } completion:nil];
            }
        } @catch (NSException *e) {}
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
    
    CGFloat topPadding = 14.0;
    CGFloat bottomPadding = 14.0;
    CGFloat availableHeight = dockH - topPadding - bottomPadding;
    CGFloat slotHeight = availableHeight / (CGFloat)count;
    CGFloat iconSize = 60.0 * kDockIconScale;
    
    for (NSUInteger i = 0; i < count; i++) {
        SBIconView *iconView = icons[i];
        CGFloat iy = topPadding + (i * slotHeight) + (slotHeight - iconSize) / 2.0;
        CGFloat ix = (dockW - iconSize) / 2.0;
        
        iconView.frame = CGRectMake(ix, iy, iconSize, iconSize);
        iconView.transform = CGAffineTransformIdentity;
        
        if ([iconView respondsToSelector:@selector(setLabelHidden:)]) {
            [iconView setLabelHidden:YES];
        }
    }
}

// MARK: - Hook SBDockView (Standard iPhone Dock)
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
        self.layer.masksToBounds = YES;
        self.clipsToBounds = YES;
        
        // Handle Background Blur / Pill
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
            
            if (!kDockBlurEnabled) {
                bg.hidden = YES;
                bg.alpha = 0.0;
            } else {
                bg.hidden = NO;
                bg.alpha = kDockBlurAlpha;
            }
        }
        
        // Layout Dock Icons vertically
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
        if (!CGRectContainsPoint(self.bounds, point)) {
            return nil;
        }
    }
    return %orig(point, event);
}

%end

// MARK: - Hook SBRootFolderView (SpringBoard Grid & Dock Placement)
%hook SBRootFolderView

- (CGRect)_frameForDockView {
    if (kEnabled) {
        return calculateDuoDockFrame();
    }
    return %orig;
}

- (CGRect)_frameForIconListViewAtIndex:(NSUInteger)arg1 {
    CGRect origFrame = %orig;
    if (!kEnabled) return origFrame;
    
    @try {
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
        
        // 1. Inset right margin so icons do not collide with vertical dock
        CGFloat occupiedRight = kDockWidth + kRightMargin + 10.0;
        origFrame.size.width = screenWidth - occupiedRight;
        
        // 2. Expand bottom rows into former dock territory
        if (kExpandBottomRows) {
            CGFloat bottomPadding = 32.0; // Space for page dots and home indicator
            origFrame.size.height = screenHeight - origFrame.origin.y - bottomPadding;
        }
    } @catch (NSException *e) {}
    
    return origFrame;
}

%end

// MARK: - Hook SBIconListView (Layout insets and Max count)
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
            insets.right += (kDockWidth + kRightMargin);
            if (kExpandBottomRows) {
                insets.bottom = 8.0;
            }
        }
    } @catch (NSException *e) {}
    
    return insets;
}

%end

// MARK: - Hook SBFloatingDockView (iPad Dock & GhostBoard/FloatingDockXVI Support)
%hook SBFloatingDockView

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
        self.layer.masksToBounds = YES;
        self.clipsToBounds = YES;
        
        // Adjust Platter
        UIView *platter = [self valueForKey:@"_mainPlatterView"];
        if (platter) {
            platter.frame = self.bounds;
            platter.layer.cornerRadius = radius;
            if (@available(iOS 13.0, *)) {
                platter.layer.cornerCurve = kCACornerCurveContinuous;
            }
            platter.layer.masksToBounds = YES;
            
            if (!kDockBlurEnabled) {
                platter.hidden = YES;
                platter.alpha = 0.0;
            } else {
                platter.hidden = NO;
                platter.alpha = kDockBlurAlpha;
            }
        }
        
        // Hide horizontal divider if present
        UIView *divider = nil;
        @try { divider = [self valueForKey:@"_dividerView"]; } @catch (NSException *e) {}
        if (divider) {
            divider.hidden = YES;
            divider.alpha = 0.0;
        }
        
        // Layout userIconListView
        SBIconListView *userIcons = nil;
        @try { userIcons = [self valueForKey:@"_userIconListView"]; } @catch (NSException *e) {}
        if (userIcons) {
            userIcons.frame = self.bounds;
            applyVerticalIconLayout(userIcons, dockFrame.size.width, dockFrame.size.height);
        }
    } @catch (NSException *e) {}
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (kEnabled) {
        if (!CGRectContainsPoint(self.bounds, point)) {
            return nil;
        }
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
    }
}
