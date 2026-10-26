#import <UIKit/UIKit.h>

#if __has_include(<Preferences/PSListController.h>)
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#else
@interface PSSpecifier : NSObject
+ (instancetype)preferenceSpecifierNamed:(NSString *)title
                                  target:(id)target
                                     set:(SEL)set
                                     get:(SEL)get
                                  detail:(Class)detail
                                    cell:(NSInteger)cell
                                    edit:(Class)edit;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
@end

@interface PSListController : UIViewController
- (NSMutableArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reloadSpecifiers;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (id)readPreferenceValue:(PSSpecifier *)specifier;
@end
#endif

@interface DuoDockRootListController : PSListController
- (void)respring;
- (void)respring:(id)sender;
- (void)resetToDefaults;
- (void)resetToDefaults:(id)sender;
@end
