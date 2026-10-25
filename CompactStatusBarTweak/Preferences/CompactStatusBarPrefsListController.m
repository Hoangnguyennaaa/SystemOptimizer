#import <UIKit/UIKit.h>
#import <spawn.h>

@interface PSListController : UIViewController
- (id)loadSpecifiersFromPlistName:(id)name target:(id)target;
@end

@interface CompactStatusBarPrefsListController : PSListController
@property (nonatomic, retain) NSArray *specifiers;
@end

@implementation CompactStatusBarPrefsListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)respring:(id)sender {
    pid_t pid;
    const char *args[] = {"killall", "-9", "SpringBoard", NULL};
    posix_spawn(&pid, "/var/jb/usr/bin/killall", NULL, NULL, (char *const *)args, NULL);
    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)args, NULL);
}

@end
