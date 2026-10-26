#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <spawn.h>

#define PREF_PATH_ROOTLESS @"/var/jb/var/mobile/Library/Preferences/com.hoangnguyen.duodock.plist"
#define PREF_PATH_ROOTFUL  @"/var/mobile/Library/Preferences/com.hoangnguyen.duodock.plist"
#define PREF_CHANGED_NOTIFICATION "com.hoangnguyen.duodock/preferences.changed"

// Forward declarations
@class SBDockView, SBRootFolderView, SBFloatingDockView, SBFloatingDockViewController;
@class SBIconListView, SBIconView, SBIconController, SBHIconManager, MTMaterialView;

@interface SBIconView : UIView
@property (nonatomic, assign) BOOL labelHidden;
- (void)setLabelHidden:(BOOL)hidden;
@end

@interface SBIconListView : UIView
@property (nonatomic, copy) NSString *iconLocation;
@property (nonatomic, readonly) BOOL isDock;
- (NSArray<SBIconView *> *)displayedIconViews;
- (NSUInteger)maximumIconCount;
- (UIEdgeInsets)layoutInsetsForOrientation:(NSInteger)orientation;
- (CGPoint)originForIconAtIndex:(NSUInteger)arg1;
- (CGPoint)centerForIconAtIndex:(NSUInteger)arg1;
- (void)layoutIconsNow;
@end

@interface SBDockIconListView : SBIconListView
@end

@interface SBDockView : UIView
@property (nonatomic, retain) UIView *backgroundView;
@property (nonatomic, readonly) SBDockIconListView *dockIconListView;
- (SBDockIconListView *)_iconListView;
- (double)dockHeight;
@end

@interface SBRootFolderView : UIView
@property (nonatomic, retain) SBDockView *dockView;
- (CGRect)_frameForDockView;
- (CGRect)_frameForIconListViewAtIndex:(NSUInteger)arg1;
- (CGRect)_frameForDockIconListView;
- (void)layoutSubviews;
@end

@interface SBFloatingDockPlatterView : UIView
@end

@interface SBFloatingDockView : UIView
@property (nonatomic, retain) UIView *mainPlatterView;
@property (nonatomic, retain) SBIconListView *userIconListView;
@property (nonatomic, retain) SBIconListView *recentIconListView;
@property (nonatomic, retain) UIView *dividerView;
- (void)layoutSubviews;
@end

@interface SBFloatingDockViewController : UIViewController
- (SBFloatingDockView *)floatingDockView;
- (CGRect)floatingDockView:(id)arg1 frameForIconAtIndex:(NSUInteger)arg2;
- (double)maximumDockContinuousCornerRadius;
@end

@interface SBIconController : NSObject
+ (id)sharedInstance;
- (void)relayout;
- (SBRootFolderView *)_rootFolderView;
@end

@interface SBHIconManager : NSObject
- (void)relayout;
@end

@interface MTMaterialView : UIView
+ (instancetype)materialViewWithRecipe:(NSInteger)recipe options:(NSUInteger)options;
@property (nonatomic, assign) CGFloat weighting;
@end
