#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <notify.h>
#import <spawn.h>
#import <unistd.h>
#import <sys/types.h>
#import <sys/socket.h>
#import <ifaddrs.h>
#import <net/if.h>

// MARK: - Protocols for Runtime SpringBoard Classes (No linker dependency)
@protocol SBWiFiManagerProtocol <NSObject>
- (NSString *)currentNetworkName;
- (BOOL)isPowered;
- (int)signalStrengthBars;
@end

@protocol SBTelephonyManagerProtocol <NSObject>
- (int)signalStrengthBars;
@end

@protocol SBLockScreenManagerProtocol <NSObject>
- (void)lockUIFromSource:(int)source withOptions:(id)options;
@end

@protocol SBControlCenterControllerProtocol <NSObject>
- (void)presentAnimated:(BOOL)animated;
@end

// Custom if_data layout on Darwin to avoid missing <net/if_var.h> in iOS SDK
struct if_data_compact {
    uint8_t   ifi_type;
    uint8_t   ifi_typelen;
    uint8_t   ifi_physical;
    uint8_t   ifi_addrlen;
    uint8_t   ifi_hdrlen;
    uint8_t   ifi_recvquota;
    uint8_t   ifi_xmitquota;
    uint8_t   ifi_unused1;
    uint32_t  ifi_mtu;
    uint32_t  ifi_metric;
    uint32_t  ifi_baudrate;
    uint32_t  ifi_ipackets;
    uint32_t  ifi_ierrors;
    uint32_t  ifi_opackets;
    uint32_t  ifi_oerrors;
    uint32_t  ifi_collisions;
    uint32_t  ifi_ibytes;
    uint32_t  ifi_obytes;
};

// MARK: - Global Preferences
static BOOL p_enabled = YES;
static BOOL p_dragModeEnabled = NO;

// Main Status Bar Position Preferences
static CGFloat p_iconScale = 1.0;
static CGFloat p_iconOpacity = 1.0;
static CGFloat p_offsetX = 0.0;
static CGFloat p_offsetY = 0.0;

// Control Center Separated Position Preferences
static BOOL p_ccEnabled = YES;
static BOOL p_ccHideStockBattery = YES;
static CGFloat p_ccOffsetX = 0.0;
static CGFloat p_ccOffsetY = 0.0;
static CGFloat p_ccIconScale = 1.0;
static int p_deviceModel = 0; // 0 = Auto, 1 = Island, 2 = Notch, 3 = Classic
static int p_batteryPercentMode = 2; // 0 = An, 1 = O tam, 2 = Ke ben, 3 = Mep trai, 4 = Dinh vom (Top Crown)

// Badge Style & Additional Information Preferences
static int p_badgeStyle = 0; // 0 = Capsule Kính Mờ, 1 = Minimalist Phẳng, 2 = Thu Gọn + Thẻ Chạm
static BOOL p_showNetworkSpeed = YES;
static BOOL p_showSSID = YES;
static BOOL p_showThermalState = YES;
static BOOL p_showRAMText = NO;
static int p_speedThreshold = 2; // 0 = Tắt, 1 = >50K, 2 = >100K, 3 = Luôn hiện
static int p_colorMode = 0; // 0 = Dynamic, 1 = Monochrome, 2 = Neon Cyan, 3 = Neon Purple, 4 = Pink, 5 = Lime, 6 = Orange, 7 = Gold, 8 = Ruby, 9 = Custom
static CGFloat p_customGaugeR = 0.0;
static CGFloat p_customGaugeG = 0.95;
static CGFloat p_customGaugeB = 1.0;
static CGFloat p_customAccentR = 0.25;
static CGFloat p_customAccentG = 0.95;
static CGFloat p_customAccentB = 0.55;
static CGFloat p_customBorderAlpha = 0.20;
static BOOL p_breathingGlow = YES;
static BOOL p_showRAM = NO;
static BOOL p_dotCount5 = NO;


// Stock Status Bar Item Hiding
static BOOL p_hideStockBattery = YES;
static BOOL p_hideStockBatteryPercent = YES;
static BOOL p_hideStockWifi = NO;
static BOOL p_hideStockCellular = NO;
static BOOL p_hideStockCarrier = NO;
static BOOL p_hideStockTime = NO;
static BOOL p_hideStockLocation = NO;
static BOOL p_hideStockVPN = NO;
static BOOL p_hideStockFocus = NO;
static BOOL p_hideStockAlarm = NO;
static BOOL p_hideStockBluetooth = NO;
static BOOL p_hideStockAirplane = NO;

// Gestures
static int p_actionSingleTap = 0;
static int p_actionDoubleTap = 4;
static int p_actionLongPress = 1;
static int p_hapticFeedback = 1;

static void loadPrefs(void) {
    CFPreferencesAppSynchronize(CFSTR("com.hoangnguyen.compactstatusbar"));

    NSString *prefPath = @"/var/mobile/Library/Preferences/com.hoangnguyen.compactstatusbar.plist";
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefPath];

    Boolean keyExists = false;
    CFIndex idx = 0;
    CFPropertyListRef ref = NULL;

    Boolean b = CFPreferencesGetAppBooleanValue(CFSTR("enabled"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_enabled = (BOOL)b;
    else if (prefs && prefs[@"enabled"]) p_enabled = [prefs[@"enabled"] boolValue];
    else p_enabled = YES;

    b = CFPreferencesGetAppBooleanValue(CFSTR("dragModeEnabled"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_dragModeEnabled = (BOOL)b;
    else if (prefs && prefs[@"dragModeEnabled"]) p_dragModeEnabled = [prefs[@"dragModeEnabled"] boolValue];
    else p_dragModeEnabled = NO;


    ref = CFPreferencesCopyAppValue(CFSTR("offsetX"), CFSTR("com.hoangnguyen.compactstatusbar"));
    if (ref) { p_offsetX = [(__bridge id)ref floatValue]; CFRelease(ref); }
    else if (prefs && prefs[@"offsetX"]) p_offsetX = [prefs[@"offsetX"] floatValue];
    else p_offsetX = 0.0;

    ref = CFPreferencesCopyAppValue(CFSTR("offsetY"), CFSTR("com.hoangnguyen.compactstatusbar"));
    if (ref) { p_offsetY = [(__bridge id)ref floatValue]; CFRelease(ref); }
    else if (prefs && prefs[@"offsetY"]) p_offsetY = [prefs[@"offsetY"] floatValue];
    else p_offsetY = 0.0;

    ref = CFPreferencesCopyAppValue(CFSTR("iconScale"), CFSTR("com.hoangnguyen.compactstatusbar"));
    if (ref) { p_iconScale = [(__bridge id)ref floatValue]; CFRelease(ref); }
    else if (prefs && prefs[@"iconScale"]) p_iconScale = [prefs[@"iconScale"] floatValue];
    else p_iconScale = 1.0;

    ref = CFPreferencesCopyAppValue(CFSTR("iconOpacity"), CFSTR("com.hoangnguyen.compactstatusbar"));
    if (ref) { p_iconOpacity = [(__bridge id)ref floatValue]; CFRelease(ref); }
    else if (prefs && prefs[@"iconOpacity"]) p_iconOpacity = [prefs[@"iconOpacity"] floatValue];
    else p_iconOpacity = 1.0;

    // Control Center separated preferences
    b = CFPreferencesGetAppBooleanValue(CFSTR("ccEnabled"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_ccEnabled = (BOOL)b;
    else if (prefs && prefs[@"ccEnabled"]) p_ccEnabled = [prefs[@"ccEnabled"] boolValue];
    else p_ccEnabled = YES;

    b = CFPreferencesGetAppBooleanValue(CFSTR("ccHideStockBattery"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_ccHideStockBattery = (BOOL)b;
    else if (prefs && prefs[@"ccHideStockBattery"]) p_ccHideStockBattery = [prefs[@"ccHideStockBattery"] boolValue];
    else p_ccHideStockBattery = YES;

    ref = CFPreferencesCopyAppValue(CFSTR("ccOffsetX"), CFSTR("com.hoangnguyen.compactstatusbar"));
    if (ref) { p_ccOffsetX = [(__bridge id)ref floatValue]; CFRelease(ref); }
    else if (prefs && prefs[@"ccOffsetX"]) p_ccOffsetX = [prefs[@"ccOffsetX"] floatValue];
    else p_ccOffsetX = 0.0;

    ref = CFPreferencesCopyAppValue(CFSTR("ccOffsetY"), CFSTR("com.hoangnguyen.compactstatusbar"));
    if (ref) { p_ccOffsetY = [(__bridge id)ref floatValue]; CFRelease(ref); }
    else if (prefs && prefs[@"ccOffsetY"]) p_ccOffsetY = [prefs[@"ccOffsetY"] floatValue];
    else p_ccOffsetY = 0.0;

    ref = CFPreferencesCopyAppValue(CFSTR("ccIconScale"), CFSTR("com.hoangnguyen.compactstatusbar"));
    if (ref) { p_ccIconScale = [(__bridge id)ref floatValue]; CFRelease(ref); }
    else if (prefs && prefs[@"ccIconScale"]) p_ccIconScale = [prefs[@"ccIconScale"] floatValue];
    else p_ccIconScale = 1.0;

    idx = CFPreferencesGetAppIntegerValue(CFSTR("deviceModel"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_deviceModel = (int)idx;
    else if (prefs && prefs[@"deviceModel"]) p_deviceModel = [prefs[@"deviceModel"] intValue];

    idx = CFPreferencesGetAppIntegerValue(CFSTR("badgeStyle"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_badgeStyle = (int)idx;
    else if (prefs && prefs[@"badgeStyle"]) p_badgeStyle = [prefs[@"badgeStyle"] intValue];
    else p_badgeStyle = 0;

    b = CFPreferencesGetAppBooleanValue(CFSTR("showNetworkSpeed"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_showNetworkSpeed = (BOOL)b;
    else if (prefs && prefs[@"showNetworkSpeed"]) p_showNetworkSpeed = [prefs[@"showNetworkSpeed"] boolValue];
    else p_showNetworkSpeed = YES;

    b = CFPreferencesGetAppBooleanValue(CFSTR("showSSID"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_showSSID = (BOOL)b;
    else if (prefs && prefs[@"showSSID"]) p_showSSID = [prefs[@"showSSID"] boolValue];
    else p_showSSID = YES;

    b = CFPreferencesGetAppBooleanValue(CFSTR("showThermalState"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_showThermalState = (BOOL)b;
    else if (prefs && prefs[@"showThermalState"]) p_showThermalState = [prefs[@"showThermalState"] boolValue];
    else p_showThermalState = YES;

    b = CFPreferencesGetAppBooleanValue(CFSTR("showRAMText"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_showRAMText = (BOOL)b;
    else if (prefs && prefs[@"showRAMText"]) p_showRAMText = [prefs[@"showRAMText"] boolValue];
    else p_showRAMText = NO;

    idx = CFPreferencesGetAppIntegerValue(CFSTR("batteryPercentMode"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_batteryPercentMode = (int)idx;
    else if (prefs && prefs[@"batteryPercentMode"]) p_batteryPercentMode = [prefs[@"batteryPercentMode"] intValue];

    idx = CFPreferencesGetAppIntegerValue(CFSTR("speedThreshold"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_speedThreshold = (int)idx;
    else if (prefs && prefs[@"speedThreshold"]) p_speedThreshold = [prefs[@"speedThreshold"] intValue];

    ref = CFPreferencesCopyAppValue(CFSTR("customGaugeR"), CFSTR("com.hoangnguyen.compactstatusbar"));
    if (ref) { p_customGaugeR = [(__bridge id)ref floatValue]; CFRelease(ref); }
    else if (prefs && prefs[@"customGaugeR"]) p_customGaugeR = [prefs[@"customGaugeR"] floatValue];
    else p_customGaugeR = 0.0;

    ref = CFPreferencesCopyAppValue(CFSTR("customGaugeG"), CFSTR("com.hoangnguyen.compactstatusbar"));
    if (ref) { p_customGaugeG = [(__bridge id)ref floatValue]; CFRelease(ref); }
    else if (prefs && prefs[@"customGaugeG"]) p_customGaugeG = [prefs[@"customGaugeG"] floatValue];
    else p_customGaugeG = 0.95;

    ref = CFPreferencesCopyAppValue(CFSTR("customGaugeB"), CFSTR("com.hoangnguyen.compactstatusbar"));
    if (ref) { p_customGaugeB = [(__bridge id)ref floatValue]; CFRelease(ref); }
    else if (prefs && prefs[@"customGaugeB"]) p_customGaugeB = [prefs[@"customGaugeB"] floatValue];
    else p_customGaugeB = 1.0;

    ref = CFPreferencesCopyAppValue(CFSTR("customAccentR"), CFSTR("com.hoangnguyen.compactstatusbar"));
    if (ref) { p_customAccentR = [(__bridge id)ref floatValue]; CFRelease(ref); }
    else if (prefs && prefs[@"customAccentR"]) p_customAccentR = [prefs[@"customAccentR"] floatValue];
    else p_customAccentR = 0.25;

    ref = CFPreferencesCopyAppValue(CFSTR("customAccentG"), CFSTR("com.hoangnguyen.compactstatusbar"));
    if (ref) { p_customAccentG = [(__bridge id)ref floatValue]; CFRelease(ref); }
    else if (prefs && prefs[@"customAccentG"]) p_customAccentG = [prefs[@"customAccentG"] floatValue];
    else p_customAccentG = 0.95;

    ref = CFPreferencesCopyAppValue(CFSTR("customAccentB"), CFSTR("com.hoangnguyen.compactstatusbar"));
    if (ref) { p_customAccentB = [(__bridge id)ref floatValue]; CFRelease(ref); }
    else if (prefs && prefs[@"customAccentB"]) p_customAccentB = [prefs[@"customAccentB"] floatValue];
    else p_customAccentB = 0.55;

    ref = CFPreferencesCopyAppValue(CFSTR("customBorderAlpha"), CFSTR("com.hoangnguyen.compactstatusbar"));
    if (ref) { p_customBorderAlpha = [(__bridge id)ref floatValue]; CFRelease(ref); }
    else if (prefs && prefs[@"customBorderAlpha"]) p_customBorderAlpha = [prefs[@"customBorderAlpha"] floatValue];
    else p_customBorderAlpha = 0.20;

    idx = CFPreferencesGetAppIntegerValue(CFSTR("colorMode"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_colorMode = (int)idx;
    else if (prefs && prefs[@"colorMode"]) p_colorMode = [prefs[@"colorMode"] intValue];

    b = CFPreferencesGetAppBooleanValue(CFSTR("breathingGlow"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_breathingGlow = (BOOL)b;
    else if (prefs && prefs[@"breathingGlow"]) p_breathingGlow = [prefs[@"breathingGlow"] boolValue];

    b = CFPreferencesGetAppBooleanValue(CFSTR("showRAM"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_showRAM = (BOOL)b;
    else if (prefs && prefs[@"showRAM"]) p_showRAM = [prefs[@"showRAM"] boolValue];

    b = CFPreferencesGetAppBooleanValue(CFSTR("dotCount5"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_dotCount5 = (BOOL)b;
    else if (prefs && prefs[@"dotCount5"]) p_dotCount5 = [prefs[@"dotCount5"] boolValue];

    // Stock item hiding
    b = CFPreferencesGetAppBooleanValue(CFSTR("hideStockBattery"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_hideStockBattery = (BOOL)b;
    else if (prefs && prefs[@"hideStockBattery"]) p_hideStockBattery = [prefs[@"hideStockBattery"] boolValue];

    b = CFPreferencesGetAppBooleanValue(CFSTR("hideStockBatteryPercent"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_hideStockBatteryPercent = (BOOL)b;
    else if (prefs && prefs[@"hideStockBatteryPercent"]) p_hideStockBatteryPercent = [prefs[@"hideStockBatteryPercent"] boolValue];

    b = CFPreferencesGetAppBooleanValue(CFSTR("hideStockWifi"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_hideStockWifi = (BOOL)b;
    else if (prefs && prefs[@"hideStockWifi"]) p_hideStockWifi = [prefs[@"hideStockWifi"] boolValue];

    b = CFPreferencesGetAppBooleanValue(CFSTR("hideStockCellular"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_hideStockCellular = (BOOL)b;
    else if (prefs && prefs[@"hideStockCellular"]) p_hideStockCellular = [prefs[@"hideStockCellular"] boolValue];

    b = CFPreferencesGetAppBooleanValue(CFSTR("hideStockCarrier"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_hideStockCarrier = (BOOL)b;
    else if (prefs && prefs[@"hideStockCarrier"]) p_hideStockCarrier = [prefs[@"hideStockCarrier"] boolValue];

    b = CFPreferencesGetAppBooleanValue(CFSTR("hideStockTime"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_hideStockTime = (BOOL)b;
    else if (prefs && prefs[@"hideStockTime"]) p_hideStockTime = [prefs[@"hideStockTime"] boolValue];

    b = CFPreferencesGetAppBooleanValue(CFSTR("hideStockLocation"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_hideStockLocation = (BOOL)b;
    else if (prefs && prefs[@"hideStockLocation"]) p_hideStockLocation = [prefs[@"hideStockLocation"] boolValue];

    b = CFPreferencesGetAppBooleanValue(CFSTR("hideStockVPN"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_hideStockVPN = (BOOL)b;
    else if (prefs && prefs[@"hideStockVPN"]) p_hideStockVPN = [prefs[@"hideStockVPN"] boolValue];

    b = CFPreferencesGetAppBooleanValue(CFSTR("hideStockFocus"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_hideStockFocus = (BOOL)b;
    else if (prefs && prefs[@"hideStockFocus"]) p_hideStockFocus = [prefs[@"hideStockFocus"] boolValue];

    b = CFPreferencesGetAppBooleanValue(CFSTR("hideStockAlarm"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_hideStockAlarm = (BOOL)b;
    else if (prefs && prefs[@"hideStockAlarm"]) p_hideStockAlarm = [prefs[@"hideStockAlarm"] boolValue];

    b = CFPreferencesGetAppBooleanValue(CFSTR("hideStockBluetooth"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_hideStockBluetooth = (BOOL)b;
    else if (prefs && prefs[@"hideStockBluetooth"]) p_hideStockBluetooth = [prefs[@"hideStockBluetooth"] boolValue];

    b = CFPreferencesGetAppBooleanValue(CFSTR("hideStockAirplane"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_hideStockAirplane = (BOOL)b;
    else if (prefs && prefs[@"hideStockAirplane"]) p_hideStockAirplane = [prefs[@"hideStockAirplane"] boolValue];

    idx = CFPreferencesGetAppIntegerValue(CFSTR("actionSingleTap"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_actionSingleTap = (int)idx;
    else if (prefs && prefs[@"actionSingleTap"]) p_actionSingleTap = [prefs[@"actionSingleTap"] intValue];

    idx = CFPreferencesGetAppIntegerValue(CFSTR("actionDoubleTap"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_actionDoubleTap = (int)idx;
    else if (prefs && prefs[@"actionDoubleTap"]) p_actionDoubleTap = [prefs[@"actionDoubleTap"] intValue];

    idx = CFPreferencesGetAppIntegerValue(CFSTR("actionLongPress"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_actionLongPress = (int)idx;
    else if (prefs && prefs[@"actionLongPress"]) p_actionLongPress = [prefs[@"actionLongPress"] intValue];

    idx = CFPreferencesGetAppIntegerValue(CFSTR("hapticFeedback"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_hapticFeedback = (int)idx;
    else if (prefs && prefs[@"hapticFeedback"]) p_hapticFeedback = [prefs[@"hapticFeedback"] intValue];
}

static void savePreferenceNumber(NSString *key, NSNumber *val) {
    CFPreferencesSetAppValue((CFStringRef)key, (__bridge CFPropertyListRef)val, CFSTR("com.hoangnguyen.compactstatusbar"));
    CFPreferencesAppSynchronize(CFSTR("com.hoangnguyen.compactstatusbar"));

    NSString *prefPath = @"/var/mobile/Library/Preferences/com.hoangnguyen.compactstatusbar.plist";
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:prefPath];
    if (!dict) dict = [NSMutableDictionary dictionary];
    dict[key] = val;
    [dict writeToFile:prefPath atomically:YES];

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.hoangnguyen.compactstatusbar/ReloadPrefs"),
        NULL,
        NULL,
        YES
    );
}

// MARK: - Helper Functions (Network, RAM, Cellular, Wi-Fi)
static int getCellularSignalBars(void);
static BOOL isWifiActive(void);
static BOOL isAirplaneModeActive(void);
static BOOL isNoSIMPresent(void);

static void getNetworkTrafficBytes(uint64_t *outDown, uint64_t *outUp) {
    struct ifaddrs *ifa_list = NULL;
    uint64_t downBytes = 0;
    uint64_t upBytes = 0;
    if (getifaddrs(&ifa_list) == 0) {
        for (struct ifaddrs *ifa = ifa_list; ifa != NULL; ifa = ifa->ifa_next) {
            if (ifa->ifa_addr && ifa->ifa_addr->sa_family == AF_LINK) {
                struct if_data_compact *ifd = (struct if_data_compact *)ifa->ifa_data;
                if (ifd) {
                    if (strncmp(ifa->ifa_name, "en", 2) == 0 || strncmp(ifa->ifa_name, "pdp_ip", 6) == 0) {
                        downBytes += ifd->ifi_ibytes;
                        upBytes += ifd->ifi_obytes;
                    }
                }
            }
        }
        freeifaddrs(ifa_list);
    }
    if (outDown) *outDown = downBytes;
    if (outUp) *outUp = upBytes;
}

static NSString *formatSpeedCompact(double bytesPerSec) {
    if (bytesPerSec >= 1048576.0) {
        return [NSString stringWithFormat:@"%.1fM", bytesPerSec / 1048576.0];
    } else if (bytesPerSec >= 1024.0) {
        return [NSString stringWithFormat:@"%dK", (int)(bytesPerSec / 1024.0)];
    } else {
        return @"0K";
    }
}

static NSString *getConnectedSSID(void) {
    Class wifiClass = objc_getClass("SBWiFiManager");
    if (wifiClass && [wifiClass respondsToSelector:@selector(sharedInstance)]) {
        id<SBWiFiManagerProtocol> wifiMgr = (id<SBWiFiManagerProtocol>)[wifiClass performSelector:@selector(sharedInstance)];
        if ([wifiMgr respondsToSelector:@selector(currentNetworkName)]) {
            NSString *name = [wifiMgr currentNetworkName];
            if (name && name.length > 0) return name;
        }
    }
    return nil;
}

static NSString *getNetworkTypeString(void) {
    if (isAirplaneModeActive()) {
        return @"Máy bay";
    }
    NSString *ssid = getConnectedSSID();
    if (ssid) {
        if (ssid.length > 7) {
            return [NSString stringWithFormat:@"%@..", [ssid substringToIndex:6]];
        }
        return ssid;
    }
    if (isNoSIMPresent()) {
        return @"No SIM";
    }
    int bars = getCellularSignalBars();
    if (bars > 0) return @"LTE";
    return @"Offline";
}

static int getThermalState(void) {
    if (@available(iOS 11.0, *)) {
        return (int)[NSProcessInfo processInfo].thermalState;
    }
    return 0;
}

static NSString *getThermalStateString(int state) {
    switch (state) {
        case 0: return @"Mát mẻ";
        case 1: return @"Ấm nhẹ";
        case 2: return @"Nóng";
        case 3: return @"Rất nóng";
        default: return @"Bình thường";
    }
}

static uint64_t getNetworkDownloadBytes(void) {
    struct ifaddrs *ifa_list = NULL;
    uint64_t totalBytes = 0;
    if (getifaddrs(&ifa_list) == 0) {
        for (struct ifaddrs *ifa = ifa_list; ifa != NULL; ifa = ifa->ifa_next) {
            if (ifa->ifa_addr && ifa->ifa_addr->sa_family == AF_LINK) {
                struct if_data_compact *ifd = (struct if_data_compact *)ifa->ifa_data;
                if (ifd) {
                    if (strncmp(ifa->ifa_name, "en", 2) == 0 || strncmp(ifa->ifa_name, "pdp_ip", 6) == 0) {
                        totalBytes += ifd->ifi_ibytes;
                    }
                }
            }
        }
        freeifaddrs(ifa_list);
    }
    return totalBytes;
}

static BOOL isWifiActive(void) {
    Class wifiClass = objc_getClass("SBWiFiManager");
    if (wifiClass && [wifiClass respondsToSelector:@selector(sharedInstance)]) {
        id<SBWiFiManagerProtocol> wifiMgr = (id<SBWiFiManagerProtocol>)[wifiClass performSelector:@selector(sharedInstance)];
        if ([wifiMgr respondsToSelector:@selector(currentNetworkName)]) {
            NSString *name = [wifiMgr currentNetworkName];
            if (name && name.length > 0) return YES;
        }
        if ([wifiMgr respondsToSelector:@selector(isPowered)]) {
            return [wifiMgr isPowered];
        }
    }
    return YES;
}

static BOOL isAirplaneModeActive(void) {
    Class teleClass = objc_getClass("SBTelephonyManager");
    if (teleClass && [teleClass respondsToSelector:@selector(sharedTelephonyManager)]) {
        id teleMgr = [teleClass performSelector:@selector(sharedTelephonyManager)];
        if (teleMgr && [teleMgr respondsToSelector:@selector(isInAirplaneMode)]) {
            BOOL inPlane = ((BOOL (*)(id, SEL))objc_msgSend)(teleMgr, @selector(isInAirplaneMode));
            if (inPlane) return YES;
        }
    }

    Class rpClass = objc_getClass("RadiosPreferences");
    if (rpClass) {
        id rp = [[rpClass alloc] init];
        if (rp && [rp respondsToSelector:@selector(airplaneMode)]) {
            BOOL inPlane = ((BOOL (*)(id, SEL))objc_msgSend)(rp, @selector(airplaneMode));
            if (inPlane) return YES;
        }
    }

    Class apClass = objc_getClass("SBAirplaneModeController");
    if (apClass && [apClass respondsToSelector:@selector(sharedInstance)]) {
        id ap = [apClass performSelector:@selector(sharedInstance)];
        if (ap && [ap respondsToSelector:@selector(isInAirplaneMode)]) {
            BOOL inPlane = ((BOOL (*)(id, SEL))objc_msgSend)(ap, @selector(isInAirplaneMode));
            if (inPlane) return YES;
        }
    }

    return NO;
}

static BOOL isNoSIMPresent(void) {
    if (isAirplaneModeActive()) return NO;

    Class teleClass = objc_getClass("SBTelephonyManager");
    if (teleClass && [teleClass respondsToSelector:@selector(sharedTelephonyManager)]) {
        id teleMgr = [teleClass performSelector:@selector(sharedTelephonyManager)];
        if (teleMgr) {
            if ([teleMgr respondsToSelector:@selector(SIMStatus)]) {
                id simStatus = [teleMgr performSelector:@selector(SIMStatus)];
                if (simStatus) {
                    NSString *statusStr = [NSString stringWithFormat:@"%@", simStatus];
                    if ([statusStr containsString:@"NotInserted"] || [statusStr containsString:@"Empty"] || [statusStr containsString:@"NoSIM"]) {
                        return YES;
                    }
                } else {
                    return YES;
                }
            }

            if ([teleMgr respondsToSelector:@selector(needsSIM)]) {
                BOOL needs = ((BOOL (*)(id, SEL))objc_msgSend)(teleMgr, @selector(needsSIM));
                if (needs) return YES;
            }
            if ([teleMgr respondsToSelector:@selector(hasSIMCard)]) {
                BOOL has = ((BOOL (*)(id, SEL))objc_msgSend)(teleMgr, @selector(hasSIMCard));
                if (!has) return YES;
            }
            if ([teleMgr respondsToSelector:@selector(containsSIM)]) {
                BOOL has = ((BOOL (*)(id, SEL))objc_msgSend)(teleMgr, @selector(containsSIM));
                if (!has) return YES;
            }
        }
    }

    Class ctClass = objc_getClass("CTTelephonyNetworkInfo");
    if (ctClass) {
        id ctInfo = [[ctClass alloc] init];
        if (ctInfo && [ctInfo respondsToSelector:@selector(serviceSubscriberCellularProviders)]) {
            NSDictionary *providers = [ctInfo performSelector:@selector(serviceSubscriberCellularProviders)];
            if (!providers || providers.count == 0) {
                return YES;
            }
            BOOL anyValid = NO;
            for (NSString *key in providers) {
                id carrier = providers[key];
                if ([carrier respondsToSelector:@selector(isoCountryCode)]) {
                    NSString *iso = [carrier performSelector:@selector(isoCountryCode)];
                    if (iso && iso.length > 0) {
                        anyValid = YES;
                        break;
                    }
                }
                if ([carrier respondsToSelector:@selector(mobileNetworkCode)]) {
                    NSString *mnc = [carrier performSelector:@selector(mobileNetworkCode)];
                    if (mnc && mnc.length > 0) {
                        anyValid = YES;
                        break;
                    }
                }
            }
            if (!anyValid) return YES;
        }
    }

    return NO;
}

static int getCellularSignalBars(void) {
    if (isAirplaneModeActive() || isNoSIMPresent()) return 0;

    Class teleClass = objc_getClass("SBTelephonyManager");
    if (teleClass && [teleClass respondsToSelector:@selector(sharedTelephonyManager)]) {
        id<SBTelephonyManagerProtocol> teleMgr = (id<SBTelephonyManagerProtocol>)[teleClass performSelector:@selector(sharedTelephonyManager)];
        if ([teleMgr respondsToSelector:@selector(signalStrengthBars)]) {
            return [teleMgr signalStrengthBars];
        }
    }
    return 4;
}

static CGFloat getRAMUsedRatio(uint64_t *outUsedBytes, uint64_t *outTotalBytes) {
    uint64_t totalBytes = [NSProcessInfo processInfo].physicalMemory;
    if (totalBytes == 0) totalBytes = 3ULL * 1024ULL * 1024ULL * 1024ULL;
    if (outTotalBytes) *outTotalBytes = totalBytes;

    mach_msg_type_number_t count = (mach_msg_type_number_t)(sizeof(vm_statistics64_data_t) / sizeof(integer_t));
    vm_statistics64_data_t vmstat;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (integer_t *)&vmstat, &count) == KERN_SUCCESS) {
        vm_size_t pageSize = 16384;
        host_page_size(mach_host_self(), &pageSize);
        uint64_t freeBytes = (uint64_t)(vmstat.free_count + vmstat.inactive_count) * pageSize;
        uint64_t usedBytes = (totalBytes > freeBytes) ? (totalBytes - freeBytes) : (totalBytes / 2);
        if (outUsedBytes) *outUsedBytes = usedBytes;
        return (CGFloat)usedBytes / (CGFloat)totalBytes;
    }
    if (outUsedBytes) *outUsedBytes = totalBytes / 2;
    return 0.5;
}

static void triggerHaptic(int level) {
    if (level == 0) return;
    UIImpactFeedbackStyle style = UIImpactFeedbackStyleLight;
    if (level == 2) style = UIImpactFeedbackStyleMedium;
    else if (level == 3) style = UIImpactFeedbackStyleHeavy;
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:style];
    [feedback impactOccurred];
}

// MARK: - Safe Method Swizzling
static void SafeSwizzle(Class cls, SEL origSel, IMP newImp, IMP *origImp) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, origSel);
    if (!m) return;

    IMP currentImp = method_getImplementation(m);
    if (currentImp == newImp) {
        return; // Already swizzled, avoid infinite recursion
    }

    BOOL added = class_addMethod(cls, origSel, newImp, method_getTypeEncoding(m));
    if (added) {
        if (origImp) *origImp = currentImp;
    } else {
        IMP prevImp = method_setImplementation(m, newImp);
        if (origImp) *origImp = prevImp;
    }
}

@class CompactStatusView;
static __weak CompactStatusView *g_activeStatusView = nil;
static __weak CompactStatusView *g_activeCCStatusView = nil;

// MARK: - CompactStatusView: Vector 3-in-1 Gauge View
@interface CompactStatusView : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIView *pillContainerView;
@property (nonatomic, strong) UIVisualEffectView *blurEffectView;
@property (nonatomic, strong) UIView *gaugeContainerView;

@property (nonatomic, strong) CAShapeLayer *trackLayer;
@property (nonatomic, strong) CAShapeLayer *progressLayer;
@property (nonatomic, strong) CAShapeLayer *wifiDotLayer;
@property (nonatomic, strong) CAShapeLayer *wifiWave1Layer;
@property (nonatomic, strong) CAShapeLayer *wifiWave2Layer;
@property (nonatomic, strong) NSMutableArray<CAShapeLayer *> *dotLayers;
@property (nonatomic, strong) UILabel *centerLabel;
@property (nonatomic, strong) UILabel *sidePercentLabel;

// Extra Information Views
@property (nonatomic, strong) UIView *extraInfoContainer;
@property (nonatomic, strong) UILabel *batteryPercentLabel;
@property (nonatomic, strong) UILabel *networkSpeedLabel;
@property (nonatomic, strong) UILabel *ssidLabel;
@property (nonatomic, strong) UIView *thermalDotView;
@property (nonatomic, strong) UILabel *ramLabel;

@property (nonatomic, assign) BOOL isControlCenter;
@property (nonatomic, assign) BOOL showRAM;
@property (nonatomic, assign) BOOL isBreathing;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) uint64_t lastDownloadBytes;
@property (nonatomic, assign) uint64_t lastUploadBytes;
@property (nonatomic, assign) NSTimeInterval lastSampleTime;
@property (nonatomic, assign) double currentDownSpeed;
@property (nonatomic, assign) double currentUpSpeed;

@property (nonatomic, assign) CGPoint anchorCenter;
@property (nonatomic, strong) UIPanGestureRecognizer *dragPanGesture;
@property (nonatomic, strong) UITapGestureRecognizer *singleTapGesture;
@property (nonatomic, strong) UITapGestureRecognizer *doubleTapGesture;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPressGesture;

@property (nonatomic, strong) UILabel *topPercentLabel;
@property (nonatomic, strong) UIImageView *airplaneView;
@property (nonatomic, strong) CAShapeLayer *airplaneVectorLayer;
@property (nonatomic, strong) CAShapeLayer *noSimCardLayer;
@property (nonatomic, strong) CAShapeLayer *noSimSlashLayer;

- (void)rebuildGaugePaths;
- (void)rebuildCellularDots;
- (void)applyPreferences;
- (void)updateStats;
- (void)showHUD;
- (void)toggleRAMDisplay;
- (void)handleDragPan:(UIPanGestureRecognizer *)pan;
- (void)updateDragHUDWithX:(CGFloat)x y:(CGFloat)y finished:(BOOL)finished;
- (void)hudActionButtonClicked:(UIButton *)sender;
- (void)dismissHUD:(UITapGestureRecognizer *)tap;
@end

@implementation CompactStatusView

- (CGSize)intrinsicContentSize {
    return self.bounds.size;
}

- (CGSize)sizeThatFits:(CGSize)size {
    return self.bounds.size;
}

- (instancetype)initWithFrame:(CGRect)frame {
    CGRect sqFrame = CGRectMake(frame.origin.x, frame.origin.y, 22.0, 22.0);
    if (self = [super initWithFrame:sqFrame]) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.clipsToBounds = NO;
        self.showRAM = p_showRAM;

        [self setupLayers];
        [self setupGestures];
        [self applyPreferences];

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        getNetworkTrafficBytes(&_lastDownloadBytes, &_lastUploadBytes);
        self.lastSampleTime = [NSDate timeIntervalSinceReferenceDate];

        [self updateStats];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateStats) name:UIDeviceBatteryLevelDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateStats) name:UIDeviceBatteryStateDidChangeNotification object:nil];

        _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateStats) userInfo:nil repeats:YES];
    }
    return self;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGFloat inset = p_dragModeEnabled ? -35.0 : -15.0;
    CGRect touchBounds = CGRectInset(self.bounds, inset, inset);
    return CGRectContainsPoint(touchBounds, point);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.userInteractionEnabled || self.hidden || self.alpha < 0.01) return nil;
    if ([self pointInside:point withEvent:event]) {
        return self;
    }
    return nil;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return YES;
}

- (void)rebuildGaugePaths {
    CGPoint center = CGPointMake(11.0, 11.0);
    CGFloat radius = 9.2;

    if (p_batteryPercentMode == 4) {
        // Top Crown arc: 101-degree symmetric left and right arcs with 68-degree top opening
        UIBezierPath *crownPath = [UIBezierPath bezierPath];
        [crownPath addArcWithCenter:center radius:radius startAngle:135.0 * M_PI / 180.0 endAngle:236.0 * M_PI / 180.0 clockwise:YES];
        UIBezierPath *sub2 = [UIBezierPath bezierPathWithArcCenter:center radius:radius startAngle:304.0 * M_PI / 180.0 endAngle:45.0 * M_PI / 180.0 clockwise:YES];
        [crownPath appendPath:sub2];

        _trackLayer.path = crownPath.CGPath;
        _progressLayer.path = crownPath.CGPath;
    } else {
        CGFloat startAngle = 135.0 * M_PI / 180.0;
        CGFloat endAngle = 45.0 * M_PI / 180.0;
        UIBezierPath *arcPath = [UIBezierPath bezierPathWithArcCenter:center
                                                               radius:radius
                                                           startAngle:startAngle
                                                             endAngle:endAngle
                                                            clockwise:YES];
        _trackLayer.path = arcPath.CGPath;
        _progressLayer.path = arcPath.CGPath;
    }
}

- (void)applyPreferences {
    [self rebuildGaugePaths];
    CGFloat scale = self.isControlCenter ? p_ccIconScale : p_iconScale;
    if (scale < 0.3) scale = 1.0;
    self.transform = CGAffineTransformMakeScale(scale, scale);
    self.alpha = p_iconOpacity;
    if (p_dragModeEnabled) {
        self.layer.borderColor = self.isControlCenter ? [UIColor colorWithRed:1.0 green:0.8 blue:0.2 alpha:1.0].CGColor : [UIColor colorWithRed:0.2 green:0.9 blue:0.4 alpha:1.0].CGColor;
        self.layer.borderWidth = 1.5;
        self.layer.cornerRadius = 6.0;
        if (!self.dragPanGesture) {
            self.dragPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDragPan:)];
            self.dragPanGesture.delegate = self;
            self.dragPanGesture.cancelsTouchesInView = YES;
            self.dragPanGesture.delaysTouchesBegan = NO;
            self.dragPanGesture.delaysTouchesEnded = NO;
            [self addGestureRecognizer:self.dragPanGesture];
        }
        self.dragPanGesture.enabled = YES;

        if (self.singleTapGesture) self.singleTapGesture.enabled = NO;
        if (self.doubleTapGesture) self.doubleTapGesture.enabled = NO;
        if (self.longPressGesture) self.longPressGesture.enabled = NO;

        UIView *p = self.superview;
        while (p) {
            p.userInteractionEnabled = YES;
            p.clipsToBounds = NO;
            if ([p isKindOfClass:[UIWindow class]]) {
                p.clipsToBounds = NO;
                break;
            }
            p = p.superview;
        }
    } else {
        self.layer.borderWidth = 0.0;
        if (self.dragPanGesture) {
            self.dragPanGesture.enabled = NO;
        }
        if (self.singleTapGesture) self.singleTapGesture.enabled = YES;
        if (self.doubleTapGesture) self.doubleTapGesture.enabled = YES;
        if (self.longPressGesture) self.longPressGesture.enabled = YES;
    }
}

- (void)handleDragPan:(UIPanGestureRecognizer *)pan {
    UIView *superview = self.superview;
    if (!superview) return;

    if (pan.state == UIGestureRecognizerStateBegan) {
        triggerHaptic(1);
    }

    CGPoint translation = [pan translationInView:superview];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:superview];

    if (self.anchorCenter.x <= 0 || self.anchorCenter.y <= 0) {
        for (UIView *sub in superview.subviews) {
            NSString *cn = NSStringFromClass([sub class]);
            if ([cn containsString:@"BatteryView"]) {
                CGRect r = [sub convertRect:sub.bounds toView:superview];
                self.anchorCenter = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
                break;
            }
        }
        if (self.anchorCenter.x <= 0) {
            CGFloat offX = self.isControlCenter ? p_ccOffsetX : p_offsetX;
            CGFloat offY = self.isControlCenter ? p_ccOffsetY : p_offsetY;
            CGFloat totalW = self.pillContainerView.frame.size.width;
            if (totalW < 22.0) totalW = 22.0;
            self.anchorCenter = CGPointMake(self.center.x + (totalW - 22.0) / 2.0 - offX, self.center.y - offY);
        }
    }

    CGFloat totalW = self.pillContainerView.frame.size.width;
    if (totalW < 22.0) totalW = 22.0;
    CGFloat curX = (self.center.x + (totalW - 22.0) / 2.0) - self.anchorCenter.x;
    CGFloat curY = self.center.y - self.anchorCenter.y;
    if (self.isControlCenter) {
        p_ccOffsetX = curX;
        p_ccOffsetY = curY;
    } else {
        p_offsetX = curX;
        p_offsetY = curY;
    }

    [self updateDragHUDWithX:curX y:curY finished:(pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled)];

    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        if (self.isControlCenter) {
            savePreferenceNumber(@"ccOffsetX", @(curX));
            savePreferenceNumber(@"ccOffsetY", @(curY));
        } else {
            savePreferenceNumber(@"offsetX", @(curX));
            savePreferenceNumber(@"offsetY", @(curY));
        }
        triggerHaptic(2);
    }
}

- (void)updateDragHUDWithX:(CGFloat)x y:(CGFloat)y finished:(BOOL)finished {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (!w.hidden && w.bounds.size.width > 200) {
                keyWindow = w;
                break;
            }
        }
    }
    if (!keyWindow) return;

    UILabel *hud = (UILabel *)[keyWindow viewWithTag:998833];
    if (!hud) {
        hud = [[UILabel alloc] initWithFrame:CGRectMake((keyWindow.bounds.size.width - 240) / 2.0, 52.0, 240.0, 32.0)];
        hud.tag = 998833;
        hud.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.92];
        hud.textColor = [UIColor colorWithRed:0.2 green:0.9 blue:0.5 alpha:1.0];
        hud.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightBold];
        hud.textAlignment = NSTextAlignmentCenter;
        hud.layer.cornerRadius = 16.0;
        hud.layer.masksToBounds = YES;
        hud.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:1.0].CGColor;
        hud.layer.borderWidth = 1.0;
        hud.userInteractionEnabled = NO;
        [keyWindow addSubview:hud];
    }
    [keyWindow bringSubviewToFront:hud];

    NSString *area = self.isControlCenter ? @"🎛️ Control Center" : @"📱 Thanh trạng thái";
    if (!finished) {
        hud.text = [NSString stringWithFormat:@"%@: X: %+.0f | Y: %+.0f", area, x, y];
        hud.alpha = 1.0;
    } else {
        hud.text = [NSString stringWithFormat:@"✅ %@ (X: %+.0f, Y: %+.0f)", area, x, y];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{
                hud.alpha = 0.0;
            } completion:^(BOOL done) {
                [hud removeFromSuperview];
            }];
        });
    }
}

- (void)setupLayers {
    // 0. Container & Capsule
    _pillContainerView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 22.0, 22.0)];
    _pillContainerView.clipsToBounds = YES;
    _pillContainerView.backgroundColor = [UIColor clearColor];
    _pillContainerView.userInteractionEnabled = NO;
    [self addSubview:_pillContainerView];

    _blurEffectView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    _blurEffectView.frame = _pillContainerView.bounds;
    _blurEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _blurEffectView.hidden = YES;
    _blurEffectView.userInteractionEnabled = NO;
    [_pillContainerView addSubview:_blurEffectView];

    // 1. Gauge subview (22x22)
    _gaugeContainerView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 22.0, 22.0)];
    _gaugeContainerView.backgroundColor = [UIColor clearColor];
    _gaugeContainerView.userInteractionEnabled = NO;
    [_pillContainerView addSubview:_gaugeContainerView];

    CGPoint center = CGPointMake(11.0, 11.0);
    CGFloat radius = 9.2;
    CGFloat strokeWidth = 1.8;

    CGFloat startAngle = 135.0 * M_PI / 180.0;
    CGFloat endAngle = 45.0 * M_PI / 180.0;
    UIBezierPath *arcPath = [UIBezierPath bezierPathWithArcCenter:center
                                                           radius:radius
                                                       startAngle:startAngle
                                                         endAngle:endAngle
                                                        clockwise:YES];

    _trackLayer = [CAShapeLayer layer];
    _trackLayer.fillColor = [UIColor clearColor].CGColor;
    _trackLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
    _trackLayer.lineWidth = strokeWidth;
    _trackLayer.lineCap = kCALineCapRound;
    _trackLayer.path = arcPath.CGPath;
    [_gaugeContainerView.layer addSublayer:_trackLayer];

    _progressLayer = [CAShapeLayer layer];
    _progressLayer.fillColor = [UIColor clearColor].CGColor;
    _progressLayer.lineWidth = strokeWidth;
    _progressLayer.lineCap = kCALineCapRound;
    _progressLayer.path = arcPath.CGPath;
    _progressLayer.strokeEnd = 1.0;
    [_gaugeContainerView.layer addSublayer:_progressLayer];

    CGPoint wifiOrigin = CGPointMake(11.0, 13.5);

    UIBezierPath *baseDotPath = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(11.0 - 0.9, 13.0 - 0.9, 1.8, 1.8)];
    _wifiDotLayer = [CAShapeLayer layer];
    _wifiDotLayer.fillColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
    _wifiDotLayer.path = baseDotPath.CGPath;
    [_gaugeContainerView.layer addSublayer:_wifiDotLayer];

    CGFloat startWifi = 225.0 * M_PI / 180.0;
    CGFloat endWifi = 315.0 * M_PI / 180.0;

    UIBezierPath *w1 = [UIBezierPath bezierPathWithArcCenter:wifiOrigin radius:3.2 startAngle:startWifi endAngle:endWifi clockwise:YES];
    _wifiWave1Layer = [CAShapeLayer layer];
    _wifiWave1Layer.fillColor = [UIColor clearColor].CGColor;
    _wifiWave1Layer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
    _wifiWave1Layer.lineWidth = 1.1;
    _wifiWave1Layer.lineCap = kCALineCapRound;
    _wifiWave1Layer.path = w1.CGPath;
    [_gaugeContainerView.layer addSublayer:_wifiWave1Layer];

    UIBezierPath *w2 = [UIBezierPath bezierPathWithArcCenter:wifiOrigin radius:5.6 startAngle:startWifi endAngle:endWifi clockwise:YES];
    _wifiWave2Layer = [CAShapeLayer layer];
    _wifiWave2Layer.fillColor = [UIColor clearColor].CGColor;
    _wifiWave2Layer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
    _wifiWave2Layer.lineWidth = 1.1;
    _wifiWave2Layer.lineCap = kCALineCapRound;
    _wifiWave2Layer.path = w2.CGPath;
    [_gaugeContainerView.layer addSublayer:_wifiWave2Layer];

    _centerLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 6.0, 22.0, 10.0)];
    _centerLabel.font = [UIFont systemFontOfSize:6.5 weight:UIFontWeightBold];
    _centerLabel.textColor = [UIColor whiteColor];
    _centerLabel.textAlignment = NSTextAlignmentCenter;
    _centerLabel.hidden = YES;
    _centerLabel.userInteractionEnabled = NO;
    [_gaugeContainerView addSubview:_centerLabel];



    // Side percent label added directly to self so it is never clipped
    _sidePercentLabel = [[UILabel alloc] initWithFrame:CGRectMake(-34.0, 3.0, 32.0, 16.0)];
    _sidePercentLabel.font = [UIFont systemFontOfSize:9.0 weight:UIFontWeightBold];
    _sidePercentLabel.textColor = [UIColor whiteColor];
    _sidePercentLabel.textAlignment = NSTextAlignmentRight;
    _sidePercentLabel.hidden = YES;
    _sidePercentLabel.userInteractionEnabled = NO;
    [self addSubview:_sidePercentLabel];

    // Top percent label (Mode 4: Top Crown)
    _topPercentLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0, -1.5, 22.0, 9.0)];
    _topPercentLabel.font = [UIFont systemFontOfSize:7.2 weight:UIFontWeightBold];
    _topPercentLabel.textColor = [UIColor whiteColor];
    _topPercentLabel.textAlignment = NSTextAlignmentCenter;
    _topPercentLabel.hidden = YES;
    _topPercentLabel.userInteractionEnabled = NO;
    [_gaugeContainerView addSubview:_topPercentLabel];

    // Airplane Symbol for Cellular Slot
    _airplaneView = [[UIImageView alloc] initWithFrame:CGRectMake(6.0, 15.4, 10.0, 5.8)];
    _airplaneView.contentMode = UIViewContentModeScaleAspectFit;
    if (@available(iOS 13.0, *)) {
        _airplaneView.image = [UIImage systemImageNamed:@"airplane"];
    }
    _airplaneView.tintColor = [UIColor whiteColor];
    _airplaneView.hidden = YES;
    _airplaneView.userInteractionEnabled = NO;
    [_gaugeContainerView addSubview:_airplaneView];

    // Fallback Vector Airplane
    UIBezierPath *apPath = [UIBezierPath bezierPath];
    [apPath moveToPoint:CGPointMake(11.0, 15.6)];
    [apPath addLineToPoint:CGPointMake(11.0, 21.0)];
    [apPath moveToPoint:CGPointMake(6.8, 18.2)];
    [apPath addLineToPoint:CGPointMake(15.2, 18.2)];
    [apPath moveToPoint:CGPointMake(8.8, 20.4)];
    [apPath addLineToPoint:CGPointMake(13.2, 20.4)];

    _airplaneVectorLayer = [CAShapeLayer layer];
    _airplaneVectorLayer.path = apPath.CGPath;
    _airplaneVectorLayer.strokeColor = [UIColor whiteColor].CGColor;
    _airplaneVectorLayer.lineWidth = 1.0;
    _airplaneVectorLayer.lineCap = kCALineCapRound;
    _airplaneVectorLayer.hidden = YES;
    [_gaugeContainerView.layer addSublayer:_airplaneVectorLayer];

    // No-SIM card outline
    UIBezierPath *simPath = [UIBezierPath bezierPath];
    [simPath moveToPoint:CGPointMake(7.5, 16.0)];
    [simPath addLineToPoint:CGPointMake(13.0, 16.0)];
    [simPath addLineToPoint:CGPointMake(14.5, 17.5)];
    [simPath addLineToPoint:CGPointMake(14.5, 21.0)];
    [simPath addLineToPoint:CGPointMake(7.5, 21.0)];
    [simPath closePath];

    _noSimCardLayer = [CAShapeLayer layer];
    _noSimCardLayer.path = simPath.CGPath;
    _noSimCardLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.9].CGColor;
    _noSimCardLayer.fillColor = [UIColor clearColor].CGColor;
    _noSimCardLayer.lineWidth = 0.9;
    _noSimCardLayer.lineJoin = kCALineJoinRound;
    _noSimCardLayer.hidden = YES;
    [_gaugeContainerView.layer addSublayer:_noSimCardLayer];

    // Diagonal red slash across SIM
    UIBezierPath *slashPath = [UIBezierPath bezierPath];
    [slashPath moveToPoint:CGPointMake(6.5, 21.6)];
    [slashPath addLineToPoint:CGPointMake(15.5, 15.4)];

    _noSimSlashLayer = [CAShapeLayer layer];
    _noSimSlashLayer.path = slashPath.CGPath;
    _noSimSlashLayer.strokeColor = [UIColor colorWithRed:1.0 green:0.25 blue:0.25 alpha:1.0].CGColor;
    _noSimSlashLayer.lineWidth = 1.1;
    _noSimSlashLayer.lineCap = kCALineCapRound;
    _noSimSlashLayer.hidden = YES;
    [_gaugeContainerView.layer addSublayer:_noSimSlashLayer];

    // 2. Extra Information Container
    _extraInfoContainer = [[UIView alloc] initWithFrame:CGRectMake(22.0, 0.0, 0.0, 22.0)];
    _extraInfoContainer.backgroundColor = [UIColor clearColor];
    _extraInfoContainer.clipsToBounds = YES;
    _extraInfoContainer.hidden = YES;
    _extraInfoContainer.userInteractionEnabled = NO;
    [_pillContainerView addSubview:_extraInfoContainer];

    _batteryPercentLabel = [[UILabel alloc] init];
    _batteryPercentLabel.font = [UIFont systemFontOfSize:8.0 weight:UIFontWeightBold];
    _batteryPercentLabel.textColor = [UIColor whiteColor];
    _batteryPercentLabel.textAlignment = NSTextAlignmentCenter;
    _batteryPercentLabel.userInteractionEnabled = NO;
    [_extraInfoContainer addSubview:_batteryPercentLabel];

    _networkSpeedLabel = [[UILabel alloc] init];
    _networkSpeedLabel.font = [UIFont systemFontOfSize:7.5 weight:UIFontWeightBold];
    UIColor *accentCol = (p_colorMode == 9) ?
        [UIColor colorWithRed:p_customAccentR green:p_customAccentG blue:p_customAccentB alpha:1.0] :
        [UIColor colorWithRed:0.25 green:0.95 blue:0.55 alpha:1.0];
    _networkSpeedLabel.textColor = accentCol;
    _networkSpeedLabel.textAlignment = NSTextAlignmentCenter;
    _networkSpeedLabel.userInteractionEnabled = NO;
    [_extraInfoContainer addSubview:_networkSpeedLabel];

    _ssidLabel = [[UILabel alloc] init];
    _ssidLabel.font = [UIFont systemFontOfSize:7.5 weight:UIFontWeightMedium];
    _ssidLabel.textColor = [UIColor colorWithWhite:0.92 alpha:1.0];
    _ssidLabel.textAlignment = NSTextAlignmentCenter;
    _ssidLabel.userInteractionEnabled = NO;
    [_extraInfoContainer addSubview:_ssidLabel];

    _thermalDotView = [[UIView alloc] init];
    _thermalDotView.layer.cornerRadius = 2.5;
    _thermalDotView.layer.masksToBounds = YES;
    _thermalDotView.backgroundColor = [UIColor colorWithRed:0.25 green:0.9 blue:0.4 alpha:1.0];
    _thermalDotView.userInteractionEnabled = NO;
    [_extraInfoContainer addSubview:_thermalDotView];

    _ramLabel = [[UILabel alloc] init];
    _ramLabel.font = [UIFont systemFontOfSize:7.5 weight:UIFontWeightBold];
    _ramLabel.textColor = [UIColor colorWithRed:0.3 green:0.8 blue:1.0 alpha:1.0];
    _ramLabel.textAlignment = NSTextAlignmentCenter;
    _ramLabel.userInteractionEnabled = NO;
    [_extraInfoContainer addSubview:_ramLabel];

    [self rebuildCellularDots];
}

- (void)rebuildCellularDots {
    if (_dotLayers) {
        for (CAShapeLayer *l in _dotLayers) [l removeFromSuperlayer];
    }
    _dotLayers = [NSMutableArray array];

    CGPoint center = CGPointMake(11.0, 11.0);
    CGFloat radius = 9.2;
    BOOL is5 = p_dotCount5;
    NSArray *angles = is5 ? @[@(122.0), @(106.0), @(90.0), @(74.0), @(58.0)]
                          : @[@(122.0), @(101.0), @(79.0), @(58.0)];
    CGFloat dr = is5 ? 0.75 : 0.85;

    for (NSNumber *degNum in angles) {
        CGFloat deg = [degNum doubleValue];
        CGFloat rad = deg * M_PI / 180.0;
        CGFloat dx = center.x + radius * cos(rad);
        CGFloat dy = center.y + radius * sin(rad);
        UIBezierPath *dp = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(dx - dr, dy - dr, dr * 2.0, dr * 2.0)];
        CAShapeLayer *dl = [CAShapeLayer layer];
        dl.path = dp.CGPath;
        dl.fillColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
        [_gaugeContainerView.layer addSublayer:dl];
        [_dotLayers addObject:dl];
    }
}

- (void)setupGestures {
    self.doubleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap)];
    self.doubleTapGesture.numberOfTapsRequired = 2;
    self.doubleTapGesture.delegate = self;
    [self addGestureRecognizer:self.doubleTapGesture];

    self.singleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap)];
    self.singleTapGesture.numberOfTapsRequired = 1;
    [self.singleTapGesture requireGestureRecognizerToFail:self.doubleTapGesture];
    self.singleTapGesture.delegate = self;
    [self addGestureRecognizer:self.singleTapGesture];

    self.longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    self.longPressGesture.minimumPressDuration = 0.55;
    self.longPressGesture.delegate = self;
    [self addGestureRecognizer:self.longPressGesture];
}

static void executeAction(int actionCode, CompactStatusView *view) {
    switch (actionCode) {
        case 0: // Hiện Popup HUD
            [view showHUD];
            break;
        case 1: { // Khóa màn hình
            Class lmClass = objc_getClass("SBLockScreenManager");
            if (lmClass && [lmClass respondsToSelector:@selector(sharedInstance)]) {
                id<SBLockScreenManagerProtocol> mgr = (id<SBLockScreenManagerProtocol>)[lmClass performSelector:@selector(sharedInstance)];
                if ([mgr respondsToSelector:@selector(lockUIFromSource:withOptions:)]) {
                    [mgr lockUIFromSource:1 withOptions:nil];
                }
            }
            break;
        }
        case 2: { // Mở Control Center
            Class ccClass = objc_getClass("SBControlCenterController");
            if (ccClass && [ccClass respondsToSelector:@selector(sharedInstance)]) {
                id<SBControlCenterControllerProtocol> cc = (id<SBControlCenterControllerProtocol>)[ccClass performSelector:@selector(sharedInstance)];
                if ([cc respondsToSelector:@selector(presentAnimated:)]) {
                    [cc presentAnimated:YES];
                }
            }
            break;
        }
        case 3: { // Chụp ảnh màn hình
            Class scClass = objc_getClass("SBScreenShotter");
            if (scClass && [scClass respondsToSelector:@selector(sharedInstance)]) {
                id sc = [scClass performSelector:@selector(sharedInstance)];
                if ([sc respondsToSelector:@selector(saveScreenshot)]) {
                    [sc performSelector:@selector(saveScreenshot)];
                }
            } else {
                Class sccClass = objc_getClass("SBScreenCaptureController");
                if (sccClass && [sccClass respondsToSelector:@selector(sharedInstance)]) {
                    id scc = [sccClass performSelector:@selector(sharedInstance)];
                    if ([scc respondsToSelector:@selector(takeScreenshot)]) {
                        [scc performSelector:@selector(takeScreenshot)];
                    }
                }
            }
            break;
        }
        case 4: // Đổi Pin / RAM
            [view toggleRAMDisplay];
            break;
        case 5: { // Respring
            dispatch_async(dispatch_get_main_queue(), ^{
                _exit(0);
            });
            break;
        }
        default:
            break;
    }
}

- (void)handleSingleTap {
    if (p_dragModeEnabled) return;
    triggerHaptic(p_hapticFeedback);
    executeAction(p_actionSingleTap, self);
}

- (void)handleDoubleTap {
    if (p_dragModeEnabled) return;
    triggerHaptic(p_hapticFeedback);
    executeAction(p_actionDoubleTap, self);
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (p_dragModeEnabled) return;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        triggerHaptic(p_hapticFeedback);
        executeAction(p_actionLongPress, self);
    }
}

- (void)toggleRAMDisplay {
    self.showRAM = !self.showRAM;
    [self updateStats];
}

// MARK: - HUD Popup: Interactive Frosted Card
- (void)showHUD {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (!w.hidden && w.bounds.size.width > 200) {
                keyWindow = w;
                break;
            }
        }
    }
    if (!keyWindow) return;

    UIView *existingHUD = [keyWindow viewWithTag:998822];
    if (existingHUD) {
        [UIView animateWithDuration:0.2 animations:^{
            existingHUD.alpha = 0.0;
            existingHUD.transform = CGAffineTransformMakeScale(0.92, 0.92);
        } completion:^(BOOL finished) {
            [existingHUD removeFromSuperview];
        }];
        return;
    }

    float rawBat = [UIDevice currentDevice].batteryLevel;
    int batPercent = (rawBat < 0) ? 100 : (int)(rawBat * 100);
    BOOL charging = ([UIDevice currentDevice].batteryState == UIDeviceBatteryStateCharging || [UIDevice currentDevice].batteryState == UIDeviceBatteryStateFull);
    BOOL lowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;

    uint64_t ramUsed = 0, ramTotal = 0;
    getRAMUsedRatio(&ramUsed, &ramTotal);
    double ramUsedGB = (double)ramUsed / 1073741824.0;
    double ramTotalGB = (double)ramTotal / 1073741824.0;
    int ramPercent = (int)((double)ramUsed / (double)ramTotal * 100);

    NSString *ssid = getConnectedSSID();
    NSString *netName = ssid ? [NSString stringWithFormat:@"Wi-Fi: %@", ssid] : @"Mạng di động (LTE/5G)";

    double downSpeed = self.currentDownSpeed;
    double upSpeed = self.currentUpSpeed;
    NSString *speedStr = [NSString stringWithFormat:@"↓ %@  ↑ %@", formatSpeedCompact(downSpeed), formatSpeedCompact(upSpeed)];

    int thermal = getThermalState();
    NSString *thermalStr = getThermalStateString(thermal);
    UIColor *thermalCol = (thermal == 0) ? [UIColor colorWithRed:0.25 green:0.9 blue:0.4 alpha:1.0] :
                          (thermal == 1) ? [UIColor colorWithRed:1.0 green:0.85 blue:0.2 alpha:1.0] :
                          (thermal == 2) ? [UIColor colorWithRed:1.0 green:0.55 blue:0.1 alpha:1.0] :
                                           [UIColor colorWithRed:1.0 green:0.25 blue:0.25 alpha:1.0];

    CGFloat hudW = 280.0;
    CGFloat hudH = 132.0;
    CGFloat hudX = (keyWindow.bounds.size.width - hudW) / 2.0;
    CGFloat hudY = 50.0;

    UIVisualEffectView *hud = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    hud.frame = CGRectMake(hudX, hudY, hudW, hudH);
    hud.layer.cornerRadius = 22.0;
    hud.layer.masksToBounds = YES;
    hud.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
    hud.layer.borderWidth = 0.5;
    hud.tag = 998822;
    hud.alpha = 0.0;
    hud.transform = CGAffineTransformMakeScale(0.92, 0.92);

    UIView *cv = hud.contentView;

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, hudW - 32, 16)];
    header.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightBold];
    header.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    header.text = @"⚡ THÔNG TIN HỆ THỐNG & KẾT NỐI";
    [cv addSubview:header];

    UILabel *batVal = [[UILabel alloc] initWithFrame:CGRectMake(16, 26, 120, 20)];
    batVal.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightBold];
    batVal.textColor = charging ? [UIColor colorWithRed:0.25 green:0.9 blue:0.4 alpha:1.0] : (lowPower ? [UIColor colorWithRed:1.0 green:0.85 blue:0.2 alpha:1.0] : [UIColor whiteColor]);
    batVal.text = [NSString stringWithFormat:@"🔋 %d%% %@", batPercent, charging ? @"⚡" : @""];
    [cv addSubview:batVal];

    UILabel *batSub = [[UILabel alloc] initWithFrame:CGRectMake(16, 44, 120, 14)];
    batSub.font = [UIFont systemFontOfSize:8.5 weight:UIFontWeightMedium];
    batSub.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    batSub.text = charging ? @"Đang sạc pin" : (lowPower ? @"Chế độ tiết kiệm" : @"Đang dùng pin");
    [cv addSubview:batSub];

    UILabel *ramVal = [[UILabel alloc] initWithFrame:CGRectMake(146, 26, 120, 20)];
    ramVal.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightBold];
    ramVal.textColor = [UIColor colorWithRed:0.3 green:0.8 blue:1.0 alpha:1.0];
    ramVal.text = [NSString stringWithFormat:@"🧠 %.1f/%.0f GB", ramUsedGB, ramTotalGB];
    [cv addSubview:ramVal];

    UILabel *ramSub = [[UILabel alloc] initWithFrame:CGRectMake(146, 44, 120, 14)];
    ramSub.font = [UIFont systemFontOfSize:8.5 weight:UIFontWeightMedium];
    ramSub.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    ramSub.text = [NSString stringWithFormat:@"Đã dùng: %d%%", ramPercent];
    [cv addSubview:ramSub];

    UILabel *netVal = [[UILabel alloc] initWithFrame:CGRectMake(16, 60, 124, 18)];
    netVal.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightBold];
    netVal.textColor = [UIColor whiteColor];
    netVal.text = [NSString stringWithFormat:@"📶 %@", netName];
    [cv addSubview:netVal];

    UILabel *netSub = [[UILabel alloc] initWithFrame:CGRectMake(16, 76, 124, 14)];
    netSub.font = [UIFont systemFontOfSize:8.0 weight:UIFontWeightMedium];
    netSub.textColor = [UIColor colorWithRed:0.25 green:0.95 blue:0.5 alpha:1.0];
    netSub.text = speedStr;
    [cv addSubview:netSub];

    UILabel *thermVal = [[UILabel alloc] initWithFrame:CGRectMake(146, 60, 120, 18)];
    thermVal.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightBold];
    thermVal.textColor = thermalCol;
    thermVal.text = [NSString stringWithFormat:@"🌡️ Nhiệt độ: %@", thermalStr];
    [cv addSubview:thermVal];

    UILabel *thermSub = [[UILabel alloc] initWithFrame:CGRectMake(146, 76, 120, 14)];
    thermSub.font = [UIFont systemFontOfSize:8.5 weight:UIFontWeightMedium];
    thermSub.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    thermSub.text = (thermal == 0) ? @"Hoạt động tối ưu" : @"Máy đang ấm/nóng";
    [cv addSubview:thermSub];

    CGFloat btnW = (hudW - 32 - 16) / 3.0;
    NSArray *btnTitles = @[@"🔒 Khóa", @"📸 Chụp", @"⚡ Respring"];
    for (int i = 0; i < 3; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(16 + i * (btnW + 8), 98, btnW, 24);
        btn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
        btn.layer.cornerRadius = 12.0;
        btn.layer.borderWidth = 0.5;
        btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
        [btn setTitle:btnTitles[i] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightBold];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.tag = 100 + i;
        [btn addTarget:self action:@selector(hudActionButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
        [cv addSubview:btn];
    }

    [keyWindow addSubview:hud];

    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0.6 options:UIViewAnimationOptionCurveEaseOut animations:^{
        hud.alpha = 1.0;
        hud.transform = CGAffineTransformIdentity;
    } completion:nil];

    UITapGestureRecognizer *tapDismiss = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissHUD:)];
    [hud addGestureRecognizer:tapDismiss];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (hud && hud.superview) {
            [UIView animateWithDuration:0.25 animations:^{
                hud.alpha = 0.0;
                hud.transform = CGAffineTransformMakeScale(0.92, 0.92);
            } completion:^(BOOL finished) {
                [hud removeFromSuperview];
            }];
        }
    });
}

- (void)hudActionButtonClicked:(UIButton *)sender {
    triggerHaptic(2);
    int tag = (int)sender.tag;
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    UIView *hud = [keyWindow viewWithTag:998822];
    if (hud) {
        [UIView animateWithDuration:0.2 animations:^{
            hud.alpha = 0.0;
        } completion:^(BOOL fin) {
            [hud removeFromSuperview];
        }];
    }
    if (tag == 100) {
        executeAction(1, self);
    } else if (tag == 101) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            executeAction(3, self);
        });
    } else if (tag == 102) {
        executeAction(5, self);
    }
}

- (void)dismissHUD:(UITapGestureRecognizer *)tap {
    UIView *hud = tap.view;
    if (hud) {
        [UIView animateWithDuration:0.2 animations:^{
            hud.alpha = 0.0;
            hud.transform = CGAffineTransformMakeScale(0.92, 0.92);
        } completion:^(BOOL finished) {
            [hud removeFromSuperview];
        }];
    }
}

// MARK: - Update Statistics (1-second cycle)
- (void)updateStats {
    float rawLevel = [UIDevice currentDevice].batteryLevel;
    CGFloat bat = rawLevel < 0 ? 1.0 : (CGFloat)rawLevel;
    UIDeviceBatteryState bState = [UIDevice currentDevice].batteryState;
    BOOL charging = (bState == UIDeviceBatteryStateCharging || bState == UIDeviceBatteryStateFull);
    BOOL lowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;

    CGFloat ramRatio = getRAMUsedRatio(NULL, NULL);
    int pct = self.showRAM ? (int)(ramRatio * 100) : (int)(bat * 100);

    // 1. Tiến trình vòng cung ngoài
    CGFloat progressVal = self.showRAM ? MIN(MAX(ramRatio, 0.0), 1.0) : bat;
    _progressLayer.strokeEnd = progressVal;

    // 2. Màu sắc vòng cung
    UIColor *col = [UIColor colorWithWhite:1.0 alpha:0.95];
    if (p_colorMode == 1) { // Đơn sắc trắng
        col = [UIColor colorWithWhite:1.0 alpha:0.95];
    } else if (p_colorMode == 2) { // Neon Cyan
        col = [UIColor colorWithRed:0.0 green:0.96 blue:1.0 alpha:1.0];
    } else if (p_colorMode == 3) { // Neon Tím
        col = [UIColor colorWithRed:0.75 green:0.33 blue:0.93 alpha:1.0];
    } else if (p_colorMode == 4) { // Neon Hồng
        col = [UIColor colorWithRed:1.0 green:0.08 blue:0.58 alpha:1.0];
    } else if (p_colorMode == 5) { // Neon Xanh Lá
        col = [UIColor colorWithRed:0.22 green:1.0 blue:0.08 alpha:1.0];
    } else if (p_colorMode == 6) { // Neon Cam
        col = [UIColor colorWithRed:1.0 green:0.42 blue:0.21 alpha:1.0];
    } else if (p_colorMode == 7) { // Vàng Gold
        col = [UIColor colorWithRed:1.0 green:0.84 blue:0.0 alpha:1.0];
    } else if (p_colorMode == 8) { // Đỏ Ruby
        col = [UIColor colorWithRed:1.0 green:0.20 blue:0.40 alpha:1.0];
    } else if (p_colorMode == 9) { // 🎨 Tự chọn màu tùy thích (Custom RGB)
        col = [UIColor colorWithRed:p_customGaugeR green:p_customGaugeG blue:p_customGaugeB alpha:1.0];
    } else { // Dynamic (0)
        if (self.showRAM) {
            if (ramRatio > 0.85) col = [UIColor colorWithRed:1.0 green:0.25 blue:0.25 alpha:1.0];
            else if (ramRatio > 0.65) col = [UIColor colorWithRed:1.0 green:0.60 blue:0.10 alpha:1.0];
            else col = [UIColor colorWithRed:0.20 green:0.80 blue:1.0 alpha:1.0];
        } else {
            if (charging) {
                col = [UIColor colorWithRed:0.20 green:0.85 blue:0.35 alpha:1.0];
            } else if (lowPower) {
                col = [UIColor colorWithRed:1.0 green:0.82 blue:0.0 alpha:1.0];
            } else if (bat <= 0.20) {
                col = [UIColor colorWithRed:1.0 green:0.25 blue:0.25 alpha:1.0];
            }
        }
    }
    _progressLayer.strokeColor = col.CGColor;

    // 3. Hiệu ứng Breathing Glow
    if (charging && p_breathingGlow) {
        if (!self.isBreathing) {
            _progressLayer.shadowColor = col.CGColor;
            _progressLayer.shadowRadius = 4.0;
            _progressLayer.shadowOffset = CGSizeZero;
            CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
            pulse.duration = 1.2;
            pulse.fromValue = @(0.2);
            pulse.toValue = @(0.95);
            pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            pulse.autoreverses = YES;
            pulse.repeatCount = HUGE_VALF;
            [_progressLayer addAnimation:pulse forKey:@"breathingGlow"];
            self.isBreathing = YES;
        }
    } else {
        if (self.isBreathing) {
            [_progressLayer removeAnimationForKey:@"breathingGlow"];
            _progressLayer.shadowOpacity = 0.0;
            self.isBreathing = NO;
        }
    }

    // 4. Đo lưu lượng mạng (Download & Upload)
    uint64_t curDown = 0, curUp = 0;
    getNetworkTrafficBytes(&curDown, &curUp);
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    double downSpeed = 0.0, upSpeed = 0.0;
    if (self.lastSampleTime > 0 && now > self.lastSampleTime) {
        double dt = now - self.lastSampleTime;
        if (curDown >= self.lastDownloadBytes) downSpeed = (double)(curDown - self.lastDownloadBytes) / dt;
        if (curUp >= self.lastUploadBytes) upSpeed = (double)(curUp - self.lastUploadBytes) / dt;
    }
    self.lastDownloadBytes = curDown;
    self.lastUploadBytes = curUp;
    self.lastSampleTime = now;
    self.currentDownSpeed = downSpeed;
    self.currentUpSpeed = upSpeed;

    BOOL wifiOn = isWifiActive();

    // 5. Kiểm tra ngưỡng tốc độ mạng
    BOOL hasSpeed = NO;
    if (p_speedThreshold == 1 && (downSpeed > 51200.0 || upSpeed > 51200.0)) hasSpeed = YES;
    else if (p_speedThreshold == 2 && (downSpeed > 102400.0 || upSpeed > 102400.0)) hasSpeed = YES;
    else if (p_speedThreshold == 3) hasSpeed = YES;

    // 6. Hiển thị ở tâm Gauge 22x22 hoặc trên Đỉnh vòm (Mode 4)
    BOOL isAirplane = isAirplaneModeActive();
    BOOL isNoSim = isNoSIMPresent();

    if (p_batteryPercentMode == 4) {
        _topPercentLabel.hidden = NO;
        _topPercentLabel.text = [NSString stringWithFormat:@"%d", pct];
        _topPercentLabel.textColor = (pct <= 20 && !charging) ? [UIColor colorWithRed:1.0 green:0.35 blue:0.35 alpha:1.0] : [UIColor whiteColor];
    } else {
        _topPercentLabel.hidden = YES;
    }

    if (p_batteryPercentMode == 1) {
        _wifiDotLayer.hidden = YES;
        _wifiWave1Layer.hidden = YES;
        _wifiWave2Layer.hidden = YES;
        _centerLabel.hidden = NO;
        _centerLabel.text = [NSString stringWithFormat:@"%d", pct];
        _centerLabel.textColor = col;
    } else if (p_badgeStyle == 2 && hasSpeed) {
        _wifiDotLayer.hidden = YES;
        _wifiWave1Layer.hidden = YES;
        _wifiWave2Layer.hidden = YES;
        _centerLabel.hidden = NO;
        _centerLabel.text = formatSpeedCompact(downSpeed > 0 ? downSpeed : upSpeed);
        _centerLabel.textColor = [UIColor colorWithRed:0.25 green:0.90 blue:0.40 alpha:1.0];
    } else if (wifiOn) {
        _centerLabel.hidden = YES;
        _wifiDotLayer.hidden = NO;
        _wifiWave1Layer.hidden = NO;
        _wifiWave2Layer.hidden = NO;
        _wifiDotLayer.opacity = 1.0;
        _wifiWave1Layer.opacity = 1.0;
        _wifiWave2Layer.opacity = 1.0;
    } else {
        _wifiDotLayer.hidden = YES;
        _wifiWave1Layer.hidden = YES;
        _wifiWave2Layer.hidden = YES;
        _centerLabel.hidden = NO;
        if (isAirplane) {
            _centerLabel.text = @"✈️";
            _centerLabel.textColor = [UIColor colorWithRed:1.0 green:0.85 blue:0.2 alpha:0.95];
        } else if (isNoSim) {
            _centerLabel.text = @"SOS";
            _centerLabel.textColor = [UIColor colorWithRed:1.0 green:0.4 blue:0.4 alpha:0.95];
        } else {
            _centerLabel.text = @"4G";
            _centerLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.90];
        }
    }

    // 7. Chế độ hiện % pin mép ngoài (Mode 3)
    if (p_batteryPercentMode == 3) {
        _sidePercentLabel.hidden = NO;
        _sidePercentLabel.text = [NSString stringWithFormat:@"%d%%", pct];
        _sidePercentLabel.textColor = col;
    } else {
        _sidePercentLabel.hidden = YES;
    }

    // 8. Chấm sóng di động, Chế độ máy bay & Không có SIM
    if (isAirplane) {
        if (_airplaneView.image) {
            _airplaneView.hidden = NO;
            if (_airplaneVectorLayer) _airplaneVectorLayer.hidden = YES;
        } else if (_airplaneVectorLayer) {
            _airplaneVectorLayer.hidden = NO;
            _airplaneView.hidden = YES;
        }
        _noSimCardLayer.hidden = YES;
        _noSimSlashLayer.hidden = YES;
        for (CAShapeLayer *dl in _dotLayers) dl.hidden = YES;
    } else if (isNoSim) {
        _airplaneView.hidden = YES;
        if (_airplaneVectorLayer) _airplaneVectorLayer.hidden = YES;
        _noSimCardLayer.hidden = NO;
        _noSimSlashLayer.hidden = NO;
        for (CAShapeLayer *dl in _dotLayers) dl.hidden = YES;
    } else {
        _airplaneView.hidden = YES;
        if (_airplaneVectorLayer) _airplaneVectorLayer.hidden = YES;
        _noSimCardLayer.hidden = YES;
        _noSimSlashLayer.hidden = YES;

        int cellBars = getCellularSignalBars();
        int totalDots = (int)_dotLayers.count;
        int litCount = 0;
        if (totalDots == 4) {
            litCount = MIN(MAX(cellBars, 0), 4);
        } else {
            if (cellBars >= 4) litCount = 5;
            else if (cellBars == 3) litCount = 4;
            else if (cellBars == 2) litCount = 2;
            else if (cellBars == 1) litCount = 1;
            else litCount = 0;
        }
        for (int i = 0; i < totalDots; i++) {
            CAShapeLayer *dot = _dotLayers[i];
            dot.hidden = NO;
            BOOL isLit = (i < litCount);
            dot.fillColor = isLit ? [UIColor colorWithWhite:1.0 alpha:0.95].CGColor
                                  : [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
        }
    }

    // 9. Bố cục Pill đa thông tin (Mode 0 & Mode 1)
    if (p_badgeStyle == 2) {
        _extraInfoContainer.hidden = YES;
        _blurEffectView.hidden = YES;
        _pillContainerView.layer.borderWidth = 0.0;
        _pillContainerView.backgroundColor = [UIColor clearColor];
        _pillContainerView.frame = CGRectMake(0, 0, 22.0, 22.0);
        self.bounds = CGRectMake(0, 0, 22.0, 22.0);
    } else {
        _extraInfoContainer.hidden = NO;
        CGFloat curX = 3.0;

        // A. Nhãn phần trăm Pin trên Capsule / Kế bên vòng đo
        if (p_batteryPercentMode == 2) {
            _batteryPercentLabel.hidden = NO;
            NSString *pctStr = charging ? [NSString stringWithFormat:@"%d%%⚡", pct] : [NSString stringWithFormat:@"%d%%", pct];
            _batteryPercentLabel.text = pctStr;
            _batteryPercentLabel.textColor = col;
            CGSize sz = [_batteryPercentLabel sizeThatFits:CGSizeMake(60, 16)];
            CGFloat w = MAX(sz.width, 22.0);
            _batteryPercentLabel.frame = CGRectMake(curX, 3.0, w, 16.0);
            curX += w + 4.0;
        } else {
            _batteryPercentLabel.hidden = YES;
        }

        // B. Nhãn tốc độ mạng
        if (p_showNetworkSpeed && hasSpeed) {
            _networkSpeedLabel.hidden = NO;
            double targetSpeed = (downSpeed >= upSpeed) ? downSpeed : upSpeed;
            NSString *prefix = (downSpeed >= upSpeed) ? @"↓" : @"↑";
            _networkSpeedLabel.text = [NSString stringWithFormat:@"%@%@", prefix, formatSpeedCompact(targetSpeed)];
            CGSize sz = [_networkSpeedLabel sizeThatFits:CGSizeMake(100, 16)];
            CGFloat w = MAX(sz.width, 24.0);
            _networkSpeedLabel.frame = CGRectMake(curX, 3.0, w, 16.0);
            curX += w + 5.0;
        } else {
            _networkSpeedLabel.hidden = YES;
        }

        if (p_showSSID) {
            _ssidLabel.hidden = NO;
            _ssidLabel.text = getNetworkTypeString();
            CGSize sz = [_ssidLabel sizeThatFits:CGSizeMake(100, 16)];
            CGFloat w = MAX(sz.width, 20.0);
            _ssidLabel.frame = CGRectMake(curX, 3.0, w, 16.0);
            curX += w + 5.0;
        } else {
            _ssidLabel.hidden = YES;
        }

        if (p_showThermalState) {
            _thermalDotView.hidden = NO;
            int thermal = getThermalState();
            UIColor *thCol = (thermal == 0) ? [UIColor colorWithRed:0.25 green:0.9 blue:0.4 alpha:1.0] :
                             (thermal == 1) ? [UIColor colorWithRed:1.0 green:0.85 blue:0.2 alpha:1.0] :
                             (thermal == 2) ? [UIColor colorWithRed:1.0 green:0.55 blue:0.1 alpha:1.0] :
                                              [UIColor colorWithRed:1.0 green:0.25 blue:0.25 alpha:1.0];
            _thermalDotView.backgroundColor = thCol;
            _thermalDotView.frame = CGRectMake(curX, 8.5, 5.0, 5.0);
            curX += 5.0 + 5.0;
        } else {
            _thermalDotView.hidden = YES;
        }

        if (p_showRAMText) {
            _ramLabel.hidden = NO;
            uint64_t ramUsed = 0;
            getRAMUsedRatio(&ramUsed, NULL);
            _ramLabel.text = [NSString stringWithFormat:@"%.1fG", (double)ramUsed / 1073741824.0];
            CGSize sz = [_ramLabel sizeThatFits:CGSizeMake(100, 16)];
            CGFloat w = MAX(sz.width, 22.0);
            _ramLabel.frame = CGRectMake(curX, 3.0, w, 16.0);
            curX += w + 4.0;
        } else {
            _ramLabel.hidden = YES;
        }

        CGFloat extraW = (curX > 3.0) ? (curX - 1.0) : 0.0;
        CGFloat totalW = 22.0 + extraW;

        _extraInfoContainer.frame = CGRectMake(22.0, 0.0, extraW, 22.0);
        _pillContainerView.frame = CGRectMake(0.0, 0.0, totalW, 22.0);
        self.bounds = CGRectMake(0.0, 0.0, totalW, 22.0);

        if (p_badgeStyle == 0) { // Capsule Kính Mờ
            _blurEffectView.hidden = NO;
            _pillContainerView.layer.cornerRadius = 11.0;
            _pillContainerView.layer.borderWidth = 0.5;
            UIColor *bCol = (p_colorMode == 9) ?
                [UIColor colorWithRed:p_customGaugeR green:p_customGaugeG blue:p_customGaugeB alpha:p_customBorderAlpha] :
                [UIColor colorWithWhite:1.0 alpha:0.20];
            _pillContainerView.layer.borderColor = bCol.CGColor;
            _pillContainerView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.38];
        } else { // Minimalist Phẳng
            _blurEffectView.hidden = YES;
            _pillContainerView.layer.borderWidth = 0.0;
            _pillContainerView.layer.cornerRadius = 0.0;
            _pillContainerView.backgroundColor = [UIColor clearColor];
        }
    }

    // 10. Căn toạ độ neo (Anchor Position) với bộ lọc vi dao động (Micro-jitter filter)
    if (!p_dragModeEnabled && self.superview && self.anchorCenter.x > 0 && self.anchorCenter.y > 0) {
        if (!self.dragPanGesture || (self.dragPanGesture.state != UIGestureRecognizerStateBegan && self.dragPanGesture.state != UIGestureRecognizerStateChanged)) {
            CGFloat offX = self.isControlCenter ? p_ccOffsetX : p_offsetX;
            CGFloat offY = self.isControlCenter ? p_ccOffsetY : p_offsetY;
            CGFloat totalW = _pillContainerView.frame.size.width;
            if (totalW < 22.0) totalW = 22.0;
            CGPoint targetCenter = CGPointMake(self.anchorCenter.x + offX - (totalW - 22.0) / 2.0, self.anchorCenter.y + offY);
            if (fabs(self.center.x - targetCenter.x) > 0.5 || fabs(self.center.y - targetCenter.y) > 0.5) {
                self.center = targetCenter;
            }
        }
    }
}

- (void)dealloc {
    [_timer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

// MARK: - Native iOS Color Picker Support
@interface CSBColorPickerDelegate : NSObject <UIColorPickerViewControllerDelegate>
@property (nonatomic, assign) int kind; // 0 = Gauge, 1 = Accent
@property (nonatomic, weak) UIViewController *parent;
- (instancetype)initWithKind:(int)kind parentController:(UIViewController *)parent;
@end

@implementation CSBColorPickerDelegate
- (instancetype)initWithKind:(int)kind parentController:(UIViewController *)parent {
    if (self = [super init]) {
        _kind = kind;
        _parent = parent;
    }
    return self;
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    UIColor *c = viewController.selectedColor;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [c getRed:&r green:&g blue:&b alpha:&a];
    if (_kind == 0) {
        savePreferenceNumber(@"colorMode", @(9)); // Switch to custom mode
        savePreferenceNumber(@"customGaugeR", @(r));
        savePreferenceNumber(@"customGaugeG", @(g));
        savePreferenceNumber(@"customGaugeB", @(b));
    } else {
        savePreferenceNumber(@"customAccentR", @(r));
        savePreferenceNumber(@"customAccentG", @(g));
        savePreferenceNumber(@"customAccentB", @(b));
    }
}
@end

static void openGaugeColorPicker(id self, SEL _cmd, id sender) {
    if (@available(iOS 14.0, *)) {
        UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
        picker.title = @"Chọn Màu Vòng Đo";
        picker.supportsAlpha = NO;
        picker.selectedColor = [UIColor colorWithRed:p_customGaugeR green:p_customGaugeG blue:p_customGaugeB alpha:1.0];
        CSBColorPickerDelegate *del = [[CSBColorPickerDelegate alloc] initWithKind:0 parentController:self];
        picker.delegate = del;
        objc_setAssociatedObject(picker, "csb_del", del, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [(UIViewController *)self presentViewController:picker animated:YES completion:nil];
    }
}

static void openAccentColorPicker(id self, SEL _cmd, id sender) {
    if (@available(iOS 14.0, *)) {
        UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
        picker.title = @"Chọn Màu Tốc Độ / Điểm Nhấn";
        picker.supportsAlpha = NO;
        picker.selectedColor = [UIColor colorWithRed:p_customAccentR green:p_customAccentG blue:p_customAccentB alpha:1.0];
        CSBColorPickerDelegate *del = [[CSBColorPickerDelegate alloc] initWithKind:1 parentController:self];
        picker.delegate = del;
        objc_setAssociatedObject(picker, "csb_del", del, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [(UIViewController *)self presentViewController:picker animated:YES completion:nil];
    }
}

// MARK: - Respring Handler
static void doRespringFromPrefs(id self, SEL _cmd, id sender) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.hoangnguyen.compactstatusbar/Respring"),
        NULL,
        NULL,
        YES
    );

    pid_t pid;
    const char *sbrArgs[] = {"sbreload", NULL};
    posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, (char *const *)sbrArgs, NULL);
    posix_spawn(&pid, "/usr/bin/sbreload", NULL, NULL, (char *const *)sbrArgs, NULL);

    const char *kArgs[] = {"killall", "-9", "SpringBoard", NULL};
    posix_spawn(&pid, "/var/jb/usr/bin/killall", NULL, NULL, (char *const *)kArgs, NULL);
    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)kArgs, NULL);
}

// MARK: - CSBPreviewCell: Interactive Canvas & Preset Picker for PreferenceLoader
@interface CSBPreviewCell : UITableViewCell
@property (nonatomic, strong) UISegmentedControl *modelSegment;
@property (nonatomic, strong) UIView *bezelView;
@property (nonatomic, strong) UIView *islandNotchView;
@property (nonatomic, strong) UIView *speakerHole;
@property (nonatomic, strong) UILabel *clockLabel;
@property (nonatomic, strong) UIView *stockAnchorView;
@property (nonatomic, strong) CompactStatusView *gaugePreview;
@property (nonatomic, strong) UILabel *coordLabel;
@property (nonatomic, strong) UIButton *btn1;
@property (nonatomic, strong) UIButton *btn2;
@property (nonatomic, strong) UIButton *btn3;
@property (nonatomic, strong) UIButton *btn4;
@property (nonatomic, strong) UIButton *btnRespring;
@property (nonatomic, strong) id specifier;
- (void)setupUI;
- (void)updateModelDisplay;
- (void)syncFromPrefs;
@end

static void handlePreviewReloadNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    CSBPreviewCell *cell = (__bridge CSBPreviewCell *)observer;
    if (cell && [cell isKindOfClass:[CSBPreviewCell class]]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [cell syncFromPrefs];
        });
    }
}

@implementation CSBPreviewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(id)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _specifier = specifier;
        [self setupUI];
    }
    return self;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (instancetype)initWithSpecifier:(id)specifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    if (self) {
        _specifier = specifier;
        [self setupUI];
    }
    return self;
}

- (UITableView *)findParentTableView {
    UIView *v = self.superview;
    while (v && ![v isKindOfClass:[UITableView class]]) {
        v = v.superview;
    }
    return (UITableView *)v;
}

- (void)setupUI {
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    loadPrefs();

    // 1. Model Segmented Control
    NSArray *items = @[@"🏝️ Dynamic Island", @"📱 Tai thỏ", @"🔲 Cổ điển"];
    _modelSegment = [[UISegmentedControl alloc] initWithItems:items];
    int selIdx = (p_deviceModel >= 1 && p_deviceModel <= 3) ? (p_deviceModel - 1) : 0;
    _modelSegment.selectedSegmentIndex = selIdx;
    [_modelSegment addTarget:self action:@selector(modelChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:_modelSegment];

    // 2. Bezel Mockup
    _bezelView = [[UIView alloc] initWithFrame:CGRectZero];
    _bezelView.backgroundColor = [UIColor colorWithRed:0.07 green:0.08 blue:0.10 alpha:1.0];
    _bezelView.layer.cornerRadius = 18.0;
    _bezelView.layer.borderWidth = 1.2;
    _bezelView.layer.borderColor = [UIColor colorWithWhite:0.28 alpha:1.0].CGColor;
    _bezelView.clipsToBounds = YES;
    _bezelView.userInteractionEnabled = YES;
    [self.contentView addSubview:_bezelView];

    // Clock
    _clockLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, 45, 18)];
    _clockLabel.text = @"9:41";
    _clockLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightBold];
    _clockLabel.textColor = [UIColor whiteColor];
    [_bezelView addSubview:_clockLabel];

    // Notch / Island view
    _islandNotchView = [[UIView alloc] initWithFrame:CGRectZero];
    _islandNotchView.backgroundColor = [UIColor blackColor];
    _speakerHole = [[UIView alloc] initWithFrame:CGRectZero];
    _speakerHole.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    [_islandNotchView addSubview:_speakerHole];
    [_bezelView addSubview:_islandNotchView];

    // Stock Battery Anchor (0, 0 watermark)
    _stockAnchorView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
    _stockAnchorView.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.7].CGColor;
    _stockAnchorView.layer.borderWidth = 1.0;
    _stockAnchorView.layer.cornerRadius = 4.0;
    _stockAnchorView.userInteractionEnabled = NO;
    [_bezelView addSubview:_stockAnchorView];

    // Interactive Gauge Preview
    _gaugePreview = [[CompactStatusView alloc] initWithFrame:CGRectMake(0, 0, 22, 22)];
    _gaugePreview.userInteractionEnabled = YES;
    [_bezelView addSubview:_gaugePreview];

    // Pan gesture on bezel
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleCanvasPan:)];
    [_bezelView addGestureRecognizer:pan];

    // Coordinates Label
    _coordLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _coordLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
    _coordLabel.textColor = [UIColor colorWithRed:0.20 green:0.85 blue:0.50 alpha:1.0];
    _coordLabel.textAlignment = NSTextAlignmentCenter;
    _coordLabel.text = [NSString stringWithFormat:@"📍 Toạ độ: X: %+.0f | Y: %+.0f (Kéo để chỉnh)", p_offsetX, p_offsetY];
    [_bezelView addSubview:_coordLabel];

    // 3. Preset Buttons
    _btn1 = [self makeButtonWithTitle:@"🎯 Gốc phải" tag:101];
    _btn2 = [self makeButtonWithTitle:@"📍 Cạnh Đảo" tag:102];
    _btn3 = [self makeButtonWithTitle:@"◀️ Góc trái" tag:103];
    _btn4 = [self makeButtonWithTitle:@"⏬ Hạ thấp" tag:104];
    [self.contentView addSubview:_btn1];
    [self.contentView addSubview:_btn2];
    [self.contentView addSubview:_btn3];
    [self.contentView addSubview:_btn4];

    // 4. Respring Button
    _btnRespring = [UIButton buttonWithType:UIButtonTypeSystem];
    [_btnRespring setTitle:@"⚡ Khởi động lại SpringBoard (Respring)" forState:UIControlStateNormal];
    _btnRespring.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];
    [_btnRespring setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _btnRespring.backgroundColor = [UIColor colorWithRed:0.12 green:0.42 blue:0.88 alpha:1.0];
    _btnRespring.layer.cornerRadius = 9.0;
    _btnRespring.layer.masksToBounds = YES;
    [_btnRespring addTarget:self action:@selector(respringTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_btnRespring];

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)(self),
        (CFNotificationCallback)handlePreviewReloadNotification,
        CFSTR("com.hoangnguyen.compactstatusbar/ReloadPrefs"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );
}

- (UIButton *)makeButtonWithTitle:(NSString *)title tag:(NSInteger)tag {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor colorWithWhite:0.20 alpha:1.0];
    btn.layer.cornerRadius = 7.0;
    btn.layer.masksToBounds = YES;
    btn.tag = tag;
    [btn addTarget:self action:@selector(presetTapped:) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    if (w <= 0) w = 360.0;

    _modelSegment.frame = CGRectMake(16, 6, w - 32, 28);
    _bezelView.frame = CGRectMake(16, 40, w - 32, 88);

    CGFloat bW = _bezelView.bounds.size.width;
    _stockAnchorView.frame = CGRectMake(bW - 40, 10, 24, 24);
    _gaugePreview.center = CGPointMake(_stockAnchorView.center.x + p_offsetX, _stockAnchorView.center.y + p_offsetY);
    _coordLabel.frame = CGRectMake(10, 66, bW - 20, 16);

    [self updateModelDisplay];

    CGFloat sp = 5.0;
    CGFloat totalW = w - 32;
    CGFloat btnW = (totalW - (sp * 3.0)) / 4.0;
    _btn1.frame = CGRectMake(16, 134, btnW, 28);
    _btn2.frame = CGRectMake(16 + (btnW + sp), 134, btnW, 28);
    _btn3.frame = CGRectMake(16 + (btnW + sp) * 2, 134, btnW, 28);
    _btn4.frame = CGRectMake(16 + (btnW + sp) * 3, 134, btnW, 28);

    _btnRespring.frame = CGRectMake(16, 168, w - 32, 34);
}

- (void)updateModelDisplay {
    CGFloat bW = _bezelView.bounds.size.width;
    NSInteger seg = _modelSegment.selectedSegmentIndex;
    if (seg == 0) { // Dynamic Island
        _islandNotchView.hidden = NO;
        _islandNotchView.frame = CGRectMake((bW - 84) / 2.0, 10, 84, 20);
        _islandNotchView.layer.cornerRadius = 10;
        _speakerHole.hidden = NO;
        _speakerHole.frame = CGRectMake(64, 5, 10, 10);
        _speakerHole.layer.cornerRadius = 5;
    } else if (seg == 1) { // Notch
        _islandNotchView.hidden = NO;
        _islandNotchView.frame = CGRectMake((bW - 120) / 2.0, 0, 120, 22);
        _islandNotchView.layer.cornerRadius = 7;
        _speakerHole.hidden = NO;
        _speakerHole.frame = CGRectMake((120 - 34) / 2.0, 4, 34, 4);
        _speakerHole.layer.cornerRadius = 2;
    } else { // Classic
        _islandNotchView.hidden = YES;
    }
}

- (void)modelChanged:(UISegmentedControl *)seg {
    p_deviceModel = (int)seg.selectedSegmentIndex + 1;
    savePreferenceNumber(@"deviceModel", @(p_deviceModel));
    [self updateModelDisplay];
    triggerHaptic(1);
}

- (void)handleCanvasPan:(UIPanGestureRecognizer *)pan {
    UITableView *tv = [self findParentTableView];
    if (pan.state == UIGestureRecognizerStateBegan) {
        if (tv) tv.scrollEnabled = NO;
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        if (tv) tv.scrollEnabled = YES;
    }

    CGPoint loc = [pan locationInView:_bezelView];
    CGFloat newX = MAX(16, MIN(_bezelView.bounds.size.width - 16, loc.x));
    CGFloat newY = MAX(12, MIN(_bezelView.bounds.size.height - 12, loc.y));

    _gaugePreview.center = CGPointMake(newX, newY);

    CGFloat curX = _gaugePreview.center.x - _stockAnchorView.center.x;
    CGFloat curY = _gaugePreview.center.y - _stockAnchorView.center.y;

    _coordLabel.text = [NSString stringWithFormat:@"📍 Toạ độ: X: %+.0f | Y: %+.0f (Kéo để chỉnh)", curX, curY];

    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        p_offsetX = curX;
        p_offsetY = curY;
        savePreferenceNumber(@"offsetX", @(curX));
        savePreferenceNumber(@"offsetY", @(curY));
        triggerHaptic(1);
    }
}

- (void)presetTapped:(UIButton *)btn {
    CGFloat newX = 0, newY = 0;
    if (btn.tag == 101) { newX = 0; newY = 0; }
    else if (btn.tag == 102) { newX = -55; newY = 0; }
    else if (btn.tag == 103) { newX = -240; newY = 0; }
    else if (btn.tag == 104) { newX = 0; newY = 16; }

    [UIView animateWithDuration:0.25 animations:^{
        self.gaugePreview.center = CGPointMake(self.stockAnchorView.center.x + newX, self.stockAnchorView.center.y + newY);
    }];
    _coordLabel.text = [NSString stringWithFormat:@"📍 Toạ độ: X: %+.0f | Y: %+.0f (Kéo để chỉnh)", newX, newY];

    p_offsetX = newX;
    p_offsetY = newY;
    savePreferenceNumber(@"offsetX", @(newX));
    savePreferenceNumber(@"offsetY", @(newY));
    triggerHaptic(2);
}

- (void)respringTapped:(UIButton *)btn {
    triggerHaptic(2);
    doRespringFromPrefs(self, @selector(respring:), nil);
}

- (void)syncFromPrefs {
    loadPrefs();
    _gaugePreview.center = CGPointMake(_stockAnchorView.center.x + p_offsetX, _stockAnchorView.center.y + p_offsetY);
    _coordLabel.text = [NSString stringWithFormat:@"📍 Toạ độ: X: %+.0f | Y: %+.0f (Kéo để chỉnh)", p_offsetX, p_offsetY];
    [_gaugePreview applyPreferences];
    [_gaugePreview updateStats];
}

- (void)refreshCellContentsWithSpecifier:(id)specifier {
    _specifier = specifier;
    [self syncFromPrefs];
}

- (BOOL)canReload {
    return YES;
}

- (id)value {
    return nil;
}

- (void)setValue:(id)value {
}

- (id)target {
    return self;
}

- (id)cellTarget {
    return self;
}

- (id)cellAction {
    return nil;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    NSMethodSignature *sig = [super methodSignatureForSelector:aSelector];
    if (!sig) {
        sig = [NSMethodSignature signatureWithObjCTypes:"v@:"];
    }
    return sig;
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)(self),
        CFSTR("com.hoangnguyen.compactstatusbar/ReloadPrefs"),
        NULL
    );
}

@end

// MARK: - Stock Status Bar Item Hiding Helpers
static inline BOOL shouldHideStatusBarImageView(UIImageView *self) {
    if (!p_enabled) return NO;

    NSString *desc = [self description];
    NSString *parentDesc = self.superview ? [self.superview description] : @"";
    NSString *imgDesc = self.image ? [self.image description] : @"";
    NSString *allInfo = [NSString stringWithFormat:@"%@ %@ %@", desc, parentDesc, imgDesc].lowercaseString;

    if (p_hideStockLocation && ([allInfo containsString:@"location"] || [allInfo containsString:@"compass"])) return YES;
    if (p_hideStockVPN && [allInfo containsString:@"vpn"]) return YES;
    if (p_hideStockFocus && ([allInfo containsString:@"moon"] || [allInfo containsString:@"focus"] || [allInfo containsString:@"quietmode"] || [allInfo containsString:@"dnd"])) return YES;
    if (p_hideStockAlarm && [allInfo containsString:@"alarm"]) return YES;
    if (p_hideStockBluetooth && ([allInfo containsString:@"bluetooth"] || [allInfo containsString:@"headphone"] || [allInfo containsString:@"airpod"])) return YES;
    if (p_hideStockAirplane && [allInfo containsString:@"airplane"]) return YES;
    if (p_hideStockWifi && ([allInfo containsString:@"wifi"] || [allInfo containsString:@"airport"])) return YES;
    if (p_hideStockCellular && ([allInfo containsString:@"cellular"] || [allInfo containsString:@"signal"])) return YES;
    return NO;
}

static inline void checkAndApplyImageVisibility(UIImageView *self) {
    if (!p_enabled) return;
    if (shouldHideStatusBarImageView(self)) {
        self.hidden = YES;
        self.alpha = 0.0;
    }
}

static inline BOOL shouldHideStatusBarStringView(UIView *self, NSString *text) {
    if (!p_enabled || !text || text.length == 0) return NO;

    if (p_hideStockBatteryPercent && [text containsString:@"%"]) {
        return YES;
    }
    if (p_hideStockTime && [text containsString:@":"]) {
        return YES;
    }
    if (p_hideStockCarrier) {
        if (![text containsString:@"%"] && ![text containsString:@":"]) {
            NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            static NSSet *netTypes = nil;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                netTypes = [NSSet setWithObjects:@"LTE", @"4G", @"5G", @"3G", @"E", @"GPRS", @"1X", @"SOS", @"5G+", @"5G UW", @"5G UC", nil];
            });
            if (![netTypes containsObject:trimmed.uppercaseString]) {
                NSString *allInfo = [NSString stringWithFormat:@"%@ %@", [self description], self.superview ? [self.superview description] : @""].lowercaseString;
                if ([allInfo containsString:@"service"] || [allInfo containsString:@"carrier"] || [allInfo containsString:@"cellular"] || [allInfo containsString:@"telephony"] || trimmed.length > 2) {
                    return YES;
                }
            }
        }
    }
    return NO;
}

// MARK: - Hooks for SpringBoard Status Bar Items

static inline BOOL isControlCenterView(UIView *view) {
    UIView *v = view;
    while (v) {
        NSString *cn = NSStringFromClass([v class]);
        if ([cn containsString:@"CCUI"] || [cn containsString:@"ControlCenter"]) {
            return YES;
        }
        if ([v isKindOfClass:[UIWindow class]]) {
            if ([cn containsString:@"ControlCenter"]) return YES;
            break;
        }
        v = v.superview;
    }
    return NO;
}

static void updateCustomViewPosition(CompactStatusView *custom, UIView *stockBattery, UIView *container, BOOL isCC) {
    if (!custom || !stockBattery || !container) return;

    CGRect rectInContainer = [stockBattery convertRect:stockBattery.bounds toView:container];
    CGPoint centerInContainer = CGPointMake(CGRectGetMidX(rectInContainer), CGRectGetMidY(rectInContainer));
    if (centerInContainer.x > 0 && centerInContainer.y > 0) {
        custom.anchorCenter = centerInContainer;
    }

    if (p_dragModeEnabled) {
        if (custom.center.x <= 11.0 && custom.center.y <= 11.0 && custom.anchorCenter.x > 0) {
            CGFloat offX = isCC ? p_ccOffsetX : p_offsetX;
            CGFloat offY = isCC ? p_ccOffsetY : p_offsetY;
            CGFloat totalW = custom.pillContainerView.frame.size.width;
            if (totalW < 22.0) totalW = 22.0;
            custom.center = CGPointMake(custom.anchorCenter.x + offX - (totalW - 22.0) / 2.0, custom.anchorCenter.y + offY);
        }
        return;
    }

    if (custom.dragPanGesture && (custom.dragPanGesture.state == UIGestureRecognizerStateBegan || custom.dragPanGesture.state == UIGestureRecognizerStateChanged)) {
        return;
    }

    CGFloat offX = isCC ? p_ccOffsetX : p_offsetX;
    CGFloat offY = isCC ? p_ccOffsetY : p_offsetY;
    CGFloat totalW = custom.pillContainerView.frame.size.width;
    if (totalW < 22.0) totalW = 22.0;

    CGPoint targetCenter = CGPointMake(custom.anchorCenter.x + offX - (totalW - 22.0) / 2.0, custom.anchorCenter.y + offY);
    if (fabs(custom.center.x - targetCenter.x) > 0.5 || fabs(custom.center.y - targetCenter.y) > 0.5) {
        custom.center = targetCenter;
    }
}

static void (*orig_battery_didMoveToWindow)(UIView *, SEL) = NULL;
static void hooked_battery_didMoveToWindow(UIView *self, SEL _cmd) {
    if (orig_battery_didMoveToWindow) {
        orig_battery_didMoveToWindow(self, _cmd);
    }
    if (!self.window || !p_enabled) return;

    BOOL isCC = isControlCenterView(self);
    BOOL hideStock = isCC ? p_ccHideStockBattery : p_hideStockBattery;
    if (hideStock) {
        self.hidden = YES;
        self.alpha = 0.0;
    } else {
        self.hidden = NO;
        self.alpha = 1.0;
    }

    if (isCC && !p_ccEnabled) return;

    UIView *parent = self.superview;
    if (parent) {
        UIView *container = parent;
        UIView *v = parent;
        while (v && ![v isKindOfClass:[UIWindow class]]) {
            NSString *cn = NSStringFromClass([v class]);
            if ([cn isEqualToString:@"_UIStatusBar"] || [cn isEqualToString:@"UIStatusBar"]) {
                container = v;
                break;
            }
            v = v.superview;
        }

        CompactStatusView *custom = (CompactStatusView *)[container viewWithTag:998811];
        if (!custom) {
            custom = (CompactStatusView *)[parent viewWithTag:998811];
        }
        if (!custom) {
            custom = [[CompactStatusView alloc] initWithFrame:CGRectMake(0, 0, 22.0, 22.0)];
            custom.tag = 998811;
            [container addSubview:custom];
        } else if (custom.superview != container) {
            [custom removeFromSuperview];
            [container addSubview:custom];
        }

        custom.isControlCenter = isCC;
        if (isCC) {
            g_activeCCStatusView = custom;
        } else {
            g_activeStatusView = custom;
        }

        updateCustomViewPosition(custom, self, container, isCC);
        [container bringSubviewToFront:custom];
        [custom applyPreferences];

        container.userInteractionEnabled = YES;
        container.clipsToBounds = NO;
        UIView *p = container.superview;
        while (p) {
            p.userInteractionEnabled = YES;
            p.clipsToBounds = NO;
            if ([p isKindOfClass:[UIWindow class]]) {
                p.clipsToBounds = NO;
                break;
            }
            p = p.superview;
        }
    }
}

static void (*orig_battery_layoutSubviews)(UIView *, SEL) = NULL;
static void hooked_battery_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_battery_layoutSubviews) {
        orig_battery_layoutSubviews(self, _cmd);
    }
    if (p_enabled) {
        BOOL isCC = isControlCenterView(self);
        BOOL hideStock = isCC ? p_ccHideStockBattery : p_hideStockBattery;
        if (hideStock) {
            self.hidden = YES;
            self.alpha = 0.0;
        } else {
            self.hidden = NO;
            self.alpha = 1.0;
        }

        if (isCC && !p_ccEnabled) {
            UIView *parent = self.superview;
            if (parent) {
                CompactStatusView *custom = (CompactStatusView *)[parent viewWithTag:998811];
                if (custom) {
                    custom.hidden = YES;
                    custom.alpha = 0.0;
                }
            }
            return;
        }

        UIView *parent = self.superview;
        if (parent) {
            UIView *container = parent;
            UIView *v = parent;
            while (v && ![v isKindOfClass:[UIWindow class]]) {
                NSString *cn = NSStringFromClass([v class]);
                if ([cn isEqualToString:@"_UIStatusBar"] || [cn isEqualToString:@"UIStatusBar"]) {
                    container = v;
                    break;
                }
                v = v.superview;
            }

            CompactStatusView *custom = (CompactStatusView *)[container viewWithTag:998811];
            if (!custom) {
                custom = (CompactStatusView *)[parent viewWithTag:998811];
            }
            if (custom) {
                custom.isControlCenter = isCC;
                if (isCC) {
                    g_activeCCStatusView = custom;
                } else {
                    g_activeStatusView = custom;
                }

                updateCustomViewPosition(custom, self, container, isCC);
            }
        }
    }
}

static void (*orig_wifi_didMoveToWindow)(UIView *, SEL) = NULL;
static void hooked_wifi_didMoveToWindow(UIView *self, SEL _cmd) {
    if (orig_wifi_didMoveToWindow) orig_wifi_didMoveToWindow(self, _cmd);
    if (p_enabled && p_hideStockWifi) {
        self.hidden = YES;
        self.alpha = 0.0;
    }
}

static void (*orig_wifi_layoutSubviews)(UIView *, SEL) = NULL;
static void hooked_wifi_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_wifi_layoutSubviews) orig_wifi_layoutSubviews(self, _cmd);
    if (p_enabled && p_hideStockWifi) {
        self.hidden = YES;
        self.alpha = 0.0;
    }
}

static void (*orig_cell_didMoveToWindow)(UIView *, SEL) = NULL;
static void hooked_cell_didMoveToWindow(UIView *self, SEL _cmd) {
    if (orig_cell_didMoveToWindow) orig_cell_didMoveToWindow(self, _cmd);
    if (p_enabled && p_hideStockCellular) {
        self.hidden = YES;
        self.alpha = 0.0;
    }
}

static void (*orig_cell_layoutSubviews)(UIView *, SEL) = NULL;
static void hooked_cell_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_cell_layoutSubviews) orig_cell_layoutSubviews(self, _cmd);
    if (p_enabled && p_hideStockCellular) {
        self.hidden = YES;
        self.alpha = 0.0;
    }
}

static void (*orig_setText)(id, SEL, NSString *) = NULL;
static void hooked_setText(id self, SEL _cmd, NSString *text) {
    if (shouldHideStatusBarStringView((UIView *)self, text)) {
        ((UIView *)self).hidden = YES;
        ((UIView *)self).alpha = 0.0;
        return;
    }
    if (orig_setText) {
        orig_setText(self, _cmd, text);
    }
}

static void (*orig_string_layoutSubviews)(UIView *, SEL) = NULL;
static void hooked_string_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_string_layoutSubviews) orig_string_layoutSubviews(self, _cmd);
    NSString *text = [self respondsToSelector:@selector(text)] ? [self performSelector:@selector(text)] : nil;
    if (shouldHideStatusBarStringView(self, text)) {
        self.hidden = YES;
        self.alpha = 0.0;
    }
}

static void (*orig_img_didMoveToWindow)(UIView *, SEL) = NULL;
static void hooked_img_didMoveToWindow(UIView *self, SEL _cmd) {
    if (orig_img_didMoveToWindow) orig_img_didMoveToWindow(self, _cmd);
    checkAndApplyImageVisibility((UIImageView *)self);
}

static void (*orig_img_layoutSubviews)(UIView *, SEL) = NULL;
static void hooked_img_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_img_layoutSubviews) orig_img_layoutSubviews(self, _cmd);
    checkAndApplyImageVisibility((UIImageView *)self);
}

static void (*orig_img_setImage)(id, SEL, UIImage *) = NULL;
static void hooked_img_setImage(UIImageView *self, SEL _cmd, UIImage *image) {
    if (orig_img_setImage) orig_img_setImage(self, _cmd, image);
    checkAndApplyImageVisibility(self);
}

// MARK: - Notifications
static void handleRespringNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        _exit(0);
    });
}

static void handleReloadNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    loadPrefs();
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_activeStatusView) {
            [g_activeStatusView rebuildCellularDots];
            [g_activeStatusView applyPreferences];
            [g_activeStatusView updateStats];
            if (!p_dragModeEnabled && g_activeStatusView.anchorCenter.x > 0) {
                CGFloat totalW = g_activeStatusView.pillContainerView.frame.size.width;
                if (totalW < 22.0) totalW = 22.0;
                g_activeStatusView.center = CGPointMake(g_activeStatusView.anchorCenter.x + p_offsetX - (totalW - 22.0) / 2.0, g_activeStatusView.anchorCenter.y + p_offsetY);
            }
        }
        if (g_activeCCStatusView) {
            [g_activeCCStatusView rebuildCellularDots];
            [g_activeCCStatusView applyPreferences];
            [g_activeCCStatusView updateStats];
            if (!p_dragModeEnabled && g_activeCCStatusView.anchorCenter.x > 0) {
                CGFloat totalW = g_activeCCStatusView.pillContainerView.frame.size.width;
                if (totalW < 22.0) totalW = 22.0;
                g_activeCCStatusView.center = CGPointMake(g_activeCCStatusView.anchorCenter.x + p_ccOffsetX - (totalW - 22.0) / 2.0, g_activeCCStatusView.anchorCenter.y + p_ccOffsetY);
            }
        }
    });
}

// MARK: - Hit-Testing Hooks for Status Bar and Window (Drag-and-Drop)
static UIView *(*orig_uistatusbar_hitTest)(UIView *, SEL, CGPoint, UIEvent *) = NULL;
static UIView *hooked_uistatusbar_hitTest(UIView *self, SEL _cmd, CGPoint point, UIEvent *event) {
    UIView *custom = [self viewWithTag:998811];
    if (custom && !custom.hidden && custom.alpha > 0.05 && custom.userInteractionEnabled) {
        CGPoint ptInCustom = [self convertPoint:point toView:custom];
        if ([custom pointInside:ptInCustom withEvent:event]) {
            return custom;
        }
    }
    return orig_uistatusbar_hitTest ? orig_uistatusbar_hitTest(self, _cmd, point, event) : [self hitTest:point withEvent:event];
}

static UIView *(*orig_statusbarwindow_hitTest)(UIWindow *, SEL, CGPoint, UIEvent *) = NULL;
static UIView *hooked_statusbarwindow_hitTest(UIWindow *self, SEL _cmd, CGPoint point, UIEvent *event) {
    UIView *custom = [self viewWithTag:998811];
    if (!custom) {
        for (UIView *sub in self.subviews) {
            custom = [sub viewWithTag:998811];
            if (custom) break;
        }
    }
    if (custom && !custom.hidden && custom.alpha > 0.05 && custom.userInteractionEnabled) {
        CGPoint ptInCustom = [self convertPoint:point toView:custom];
        if ([custom pointInside:ptInCustom withEvent:event]) {
            return custom;
        }
    }
    return orig_statusbarwindow_hitTest ? orig_statusbarwindow_hitTest(self, _cmd, point, event) : [self hitTest:point withEvent:event];
}

static BOOL (*orig_statusbarwindow_pointInside)(UIWindow *, SEL, CGPoint, UIEvent *) = NULL;
static BOOL hooked_statusbarwindow_pointInside(UIWindow *self, SEL _cmd, CGPoint point, UIEvent *event) {
    if (p_dragModeEnabled) {
        UIView *custom = [self viewWithTag:998811];
        if (!custom) {
            for (UIView *sub in self.subviews) {
                custom = [sub viewWithTag:998811];
                if (custom) break;
            }
        }
        if (custom && !custom.hidden && custom.alpha > 0.05 && custom.userInteractionEnabled) {
            CGPoint ptInCustom = [self convertPoint:point toView:custom];
            if ([custom pointInside:ptInCustom withEvent:event]) {
                return YES;
            }
        }
    }
    return orig_statusbarwindow_pointInside ? orig_statusbarwindow_pointInside(self, _cmd, point, event) : [self pointInside:point withEvent:event];
}

// MARK: - Constructor
__attribute__((constructor)) static void initCompactStatusBarTweak(void) {
    Class psListClass = objc_getClass("PSListController");
    if (psListClass) {
        class_replaceMethod(psListClass, sel_registerName("respring"), (IMP)doRespringFromPrefs, "v@:");
        class_replaceMethod(psListClass, sel_registerName("respring:"), (IMP)doRespringFromPrefs, "v@:@");
        class_replaceMethod(psListClass, sel_registerName("openGaugeColorPicker:"), (IMP)openGaugeColorPicker, "v@:@");
        class_replaceMethod(psListClass, sel_registerName("openAccentColorPicker:"), (IMP)openAccentColorPicker, "v@:@");
    }
    class_replaceMethod([UIViewController class], sel_registerName("openGaugeColorPicker:"), (IMP)openGaugeColorPicker, "v@:@");
    class_replaceMethod([UIViewController class], sel_registerName("openAccentColorPicker:"), (IMP)openAccentColorPicker, "v@:@");
    class_replaceMethod([UIViewController class], sel_registerName("respring"), (IMP)doRespringFromPrefs, "v@:");
    class_replaceMethod([UIViewController class], sel_registerName("respring:"), (IMP)doRespringFromPrefs, "v@:@");
    class_replaceMethod([NSObject class], sel_registerName("respring"), (IMP)doRespringFromPrefs, "v@:");
    class_replaceMethod([NSObject class], sel_registerName("respring:"), (IMP)doRespringFromPrefs, "v@:@");

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if ([bundleID isEqualToString:@"com.apple.Preferences"]) {
        return;
    }

    loadPrefs();

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)handleReloadNotification,
        CFSTR("com.hoangnguyen.compactstatusbar/ReloadPrefs"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)handleRespringNotification,
        CFSTR("com.hoangnguyen.compactstatusbar/Respring"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)handleReloadNotification,
        CFSTR("com.apple.radios.airplaneModeChanged"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)handleReloadNotification,
        CFSTR("kCTAirplaneModeDidChangeNotification"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)handleReloadNotification,
        CFSTR("kCTSIMSupportSIMStatusChangeNotification"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)handleReloadNotification,
        CFSTR("com.apple.telephony.simstatus"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );

    // 1. Hook Battery View
    Class bClass = objc_getClass("_UIBatteryView");
    if (bClass) {
        SafeSwizzle(bClass, @selector(didMoveToWindow), (IMP)hooked_battery_didMoveToWindow, (IMP *)&orig_battery_didMoveToWindow);
        SafeSwizzle(bClass, @selector(layoutSubviews), (IMP)hooked_battery_layoutSubviews, (IMP *)&orig_battery_layoutSubviews);
    }

    // 2. Hook Stock Wi-Fi View
    Class wifiClass = objc_getClass("_UIStatusBarWifiSignalView");
    if (wifiClass) {
        SafeSwizzle(wifiClass, @selector(didMoveToWindow), (IMP)hooked_wifi_didMoveToWindow, (IMP *)&orig_wifi_didMoveToWindow);
        SafeSwizzle(wifiClass, @selector(layoutSubviews), (IMP)hooked_wifi_layoutSubviews, (IMP *)&orig_wifi_layoutSubviews);
    }

    // 3. Hook Stock Cellular View
    Class cellClass = objc_getClass("_UIStatusBarCellularSignalView");
    if (cellClass) {
        SafeSwizzle(cellClass, @selector(didMoveToWindow), (IMP)hooked_cell_didMoveToWindow, (IMP *)&orig_cell_didMoveToWindow);
        SafeSwizzle(cellClass, @selector(layoutSubviews), (IMP)hooked_cell_layoutSubviews, (IMP *)&orig_cell_layoutSubviews);
    }

    // 4. Hook String View (% text, Time/Clock, Carrier)
    Class stringViewClass = objc_getClass("_UIStatusBarStringView");
    if (stringViewClass) {
        SafeSwizzle(stringViewClass, @selector(setText:), (IMP)hooked_setText, (IMP *)&orig_setText);
        SafeSwizzle(stringViewClass, @selector(layoutSubviews), (IMP)hooked_string_layoutSubviews, (IMP *)&orig_string_layoutSubviews);
    }

    // 5. Hook Image View (Indicators: Location, VPN, Focus/DND, Alarm, Bluetooth, Airplane)
    Class imgViewClass = objc_getClass("_UIStatusBarImageView");
    if (imgViewClass) {
        SafeSwizzle(imgViewClass, @selector(didMoveToWindow), (IMP)hooked_img_didMoveToWindow, (IMP *)&orig_img_didMoveToWindow);
        SafeSwizzle(imgViewClass, @selector(layoutSubviews), (IMP)hooked_img_layoutSubviews, (IMP *)&orig_img_layoutSubviews);
        SafeSwizzle(imgViewClass, @selector(setImage:), (IMP)hooked_img_setImage, (IMP *)&orig_img_setImage);
    }

    // 6. Hook Status Bar & Status Bar Window for touch hit-testing (drag-and-drop support)
    Class sbViewClass = objc_getClass("_UIStatusBar");
    if (sbViewClass) {
        SafeSwizzle(sbViewClass, @selector(hitTest:withEvent:), (IMP)hooked_uistatusbar_hitTest, (IMP *)&orig_uistatusbar_hitTest);
    }

    Class winClass = objc_getClass("UIStatusBarWindow");
    if (winClass) {
        SafeSwizzle(winClass, @selector(hitTest:withEvent:), (IMP)hooked_statusbarwindow_hitTest, (IMP *)&orig_statusbarwindow_hitTest);
        SafeSwizzle(winClass, @selector(pointInside:withEvent:), (IMP)hooked_statusbarwindow_pointInside, (IMP *)&orig_statusbarwindow_pointInside);
    }
    Class subWinClass = objc_getClass("_UIStatusBarWindow");
    if (subWinClass && !winClass) {
        SafeSwizzle(subWinClass, @selector(hitTest:withEvent:), (IMP)hooked_statusbarwindow_hitTest, (IMP *)&orig_statusbarwindow_hitTest);
        SafeSwizzle(subWinClass, @selector(pointInside:withEvent:), (IMP)hooked_statusbarwindow_pointInside, (IMP *)&orig_statusbarwindow_pointInside);
    }

}

