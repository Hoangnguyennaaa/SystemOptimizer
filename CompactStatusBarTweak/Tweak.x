#import <UIKit/UIKit.h>

@interface _UIBatteryView : UIView
@end

@interface _UIStatusBarItem : NSObject
@end

@interface _UIStatusBarBatteryItem : _UIStatusBarItem
@property (nonatomic, retain) _UIBatteryView *batteryView;
@end

// Hook vào SpringBoard để ẩn hoàn toàn biểu tượng pin gốc
%hook _UIStatusBarBatteryItem

- (id)applyUpdate:(id)arg1 toDisplayItem:(id)arg2 {
    id result = %orig;
    
    // Ẩn view pin gốc của hệ thống trên iPhone 7 Plus (iOS 15.8.x)
    @try {
        UIView *bView = [self valueForKey:@"_batteryView"];
        if (bView) {
            bView.hidden = YES;
            bView.alpha = 0.0;
        }
    } @catch (NSException *e) {}
    
    return result;
}

%end

// Ẩn cả phần trăm pin dạng chữ số mặc định nếu người dùng bật trong Cài đặt
%hook _UIStatusBarStringView

- (void)setText:(NSString *)text {
    if ([text containsString:@"%"]) {
        self.hidden = YES;
        self.alpha = 0.0;
        return;
    }
    %orig;
}

%end
