#import "DuoDockRootListController.h"
#import <spawn.h>
#import <notify.h>
#import <objc/runtime.h>

#define PREF_PATH_ROOTLESS @"/var/jb/var/mobile/Library/Preferences/com.hoangnguyen.duodock.plist"
#define PREF_PATH_ROOTFUL  @"/var/mobile/Library/Preferences/com.hoangnguyen.duodock.plist"
#define PREF_CHANGED_NOTIFICATION "com.hoangnguyen.duodock/preferences.changed"
#define PREF_RESPRING_NOTIFICATION "com.hoangnguyen.duodock/respring"

@interface PSSpecifier (DuoDock)
- (id)propertyForKey:(NSString *)key;
- (void)setProperty:(id)value forKey:(NSString *)key;
@end

@interface DuoDockRootListController () {
    NSMutableArray *_specifiers;
}
@end

@implementation DuoDockRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        // 1. Thử load từ bundle
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        
        // 2. Fallback nếu bundle trả về rỗng (do sandbox Preferences.app)
        if (!_specifiers || _specifiers.count == 0) {
            NSString *directPath = @"/var/jb/Library/PreferenceLoader/Preferences/DuoDock.plist";
            if (![[NSFileManager defaultManager] fileExistsAtPath:directPath]) {
                directPath = @"/Library/PreferenceLoader/Preferences/DuoDock.plist";
            }
            if ([[NSFileManager defaultManager] fileExistsAtPath:directPath]) {
                NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:directPath];
                if (dict[@"items"]) {
                    _specifiers = [self loadSpecifiersFromPlistName:@"DuoDock" target:self];
                }
            }
        }
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Nút Respring góc trên bên phải
    UIBarButtonItem *respringBtn = [[UIBarButtonItem alloc] initWithTitle:@"Respring"
                                                                    style:UIBarButtonItemStyleDone
                                                                   target:self
                                                                   action:@selector(respringPrompt)];
    respringBtn.tintColor = [UIColor systemBlueColor];
    self.navigationItem.rightBarButtonItem = respringBtn;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *path = PREF_PATH_ROOTLESS;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        path = PREF_PATH_ROOTFUL;
    }
    
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:path];
    id val = settings[[specifier propertyForKey:@"key"]];
    if (!val) {
        val = [specifier propertyForKey:@"default"];
    }
    return val;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *path = PREF_PATH_ROOTLESS;
    NSString *dir = [path stringByDeletingLastPathComponent];
    
    NSError *error = nil;
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error];
    }
    
    NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
    [settings setObject:value forKey:[specifier propertyForKey:@"key"]];
    [settings writeToFile:path atomically:YES];
    
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(PREF_CHANGED_NOTIFICATION),
        NULL,
        NULL,
        YES
    );
}

- (void)respring:(id)sender {
    [self respringPrompt];
}

- (void)respringPrompt {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"DuoDock"
                                                                   message:@"Khởi động lại SpringBoard (Respring) để áp dụng ngay các thay đổi?"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *respringAction = [UIAlertAction actionWithTitle:@"Respring ngay"
                                                             style:UIAlertActionStyleDestructive
                                                           handler:^(UIAlertAction * _Nonnull action) {
        [self performRespring];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Huỷ"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    
    [alert addAction:respringAction];
    [alert addAction:cancelAction];
    
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performRespring {
    // Gửi thông báo Darwin để SpringBoard tự respring an toàn
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(PREF_RESPRING_NOTIFICATION),
        NULL,
        NULL,
        YES
    );
    
    // Gọi sbreload/killall trực tiếp
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

@end
