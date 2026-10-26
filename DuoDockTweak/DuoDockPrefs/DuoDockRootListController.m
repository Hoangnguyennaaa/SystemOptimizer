#import "DuoDockRootListController.h"
#import <spawn.h>
#import <notify.h>
#import <objc/runtime.h>

#define PREF_PATH_ROOTLESS @"/var/jb/var/mobile/Library/Preferences/com.hoangnguyen.duodock.plist"
#define PREF_PATH_ROOTFUL  @"/var/mobile/Library/Preferences/com.hoangnguyen.duodock.plist"
#define PREF_CHANGED_NOTIFICATION "com.hoangnguyen.duodock/preferences.changed"

@interface DuoDockRootListController () {
    NSMutableArray *_specifiers;
}
@end

@implementation DuoDockRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Tạo nút Respring ở góc trên bên phải (Navigation Item) giống thiết kế GhostBoard / iOS Settings
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
    
    // Gửi thông báo Darwin để Tweak cập nhật ngay lập tức mà không nhất thiết phải respring
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(PREF_CHANGED_NOTIFICATION),
        NULL,
        NULL,
        YES
    );
}

- (void)respringPrompt {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"DuoDock"
                                                                   message:@"Bạn có muốn khởi động lại SpringBoard (Respring) để áp dụng toàn bộ thay đổi không?"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *respringAction = [UIAlertAction actionWithTitle:@"Respring ngay"
                                                             style:UIAlertActionStyleDestructive
                                                           handler:^(UIAlertAction * _Nonnull action) {
        [self respring];
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

- (void)respring {
    // 1. Thử sbreload (Rootless Dopamine)
    pid_t pid;
    const char *args_sbreload_rootless[] = {"/var/jb/usr/bin/sbreload", NULL};
    if (access("/var/jb/usr/bin/sbreload", X_OK) == 0) {
        posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, (char *const *)args_sbreload_rootless, NULL);
        return;
    }
    
    // 2. Thử sbreload chuẩn
    const char *args_sbreload[] = {"/usr/bin/sbreload", NULL};
    if (access("/usr/bin/sbreload", X_OK) == 0) {
        posix_spawn(&pid, "/usr/bin/sbreload", NULL, NULL, (char *const *)args_sbreload, NULL);
        return;
    }
    
    // 3. Fallback dùng killall SpringBoard
    const char *args_killall[] = {"/var/jb/usr/bin/killall", "-9", "SpringBoard", NULL};
    if (access("/var/jb/usr/bin/killall", X_OK) == 0) {
        posix_spawn(&pid, "/var/jb/usr/bin/killall", NULL, NULL, (char *const *)args_killall, NULL);
        return;
    }
    
    const char *args_killall_sys[] = {"/usr/bin/killall", "-9", "SpringBoard", NULL};
    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)args_killall_sys, NULL);
}

- (void)resetToDefaults {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Khôi phục mặc định"
                                                                   message:@"Đặt lại tất cả thiết lập DuoDock về ban đầu?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"Đồng ý"
                                                       style:UIAlertActionStyleDestructive
                                                     handler:^(UIAlertAction * _Nonnull action) {
        NSString *path = PREF_PATH_ROOTLESS;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        }
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR(PREF_CHANGED_NOTIFICATION),
            NULL,
            NULL,
            YES
        );
        [self reloadSpecifiers];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Huỷ"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    
    [alert addAction:okAction];
    [alert addAction:cancelAction];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
