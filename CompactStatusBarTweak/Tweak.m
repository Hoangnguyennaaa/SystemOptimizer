#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <notify.h>
#import <spawn.h>
#import <unistd.h>
#import <sys/types.h>
#import <sys/stat.h>
#import <sys/socket.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <dlfcn.h>

// MARK: - IOKit Dynamic Power Sources (Zero-recursion Hardware Battery Monitoring)
typedef void (*IOPowerSourceCallbackType)(void *context);
typedef CFTypeRef (*fn_IOPSCopyPowerSourcesInfo_t)(void);
typedef CFArrayRef (*fn_IOPSCopyPowerSourcesList_t)(CFTypeRef);
typedef CFDictionaryRef (*fn_IOPSGetPowerSourceDescription_t)(CFTypeRef, CFTypeRef);
typedef CFRunLoopSourceRef (*fn_IOPSNotificationCreateRunLoopSource_t)(IOPowerSourceCallbackType, void *);

static fn_IOPSCopyPowerSourcesInfo_t g_IOPSCopyPowerSourcesInfo = NULL;
static fn_IOPSCopyPowerSourcesList_t g_IOPSCopyPowerSourcesList = NULL;
static fn_IOPSGetPowerSourceDescription_t g_IOPSGetPowerSourceDescription = NULL;
static fn_IOPSNotificationCreateRunLoopSource_t g_IOPSNotificationCreateRunLoopSource = NULL;

static void initIOKitSymbols(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_GLOBAL);
        if (!h) h = dlopen(NULL, RTLD_LAZY);
        if (h) {
            g_IOPSCopyPowerSourcesInfo = (fn_IOPSCopyPowerSourcesInfo_t)dlsym(h, "IOPSCopyPowerSourcesInfo");
            g_IOPSCopyPowerSourcesList = (fn_IOPSCopyPowerSourcesList_t)dlsym(h, "IOPSCopyPowerSourcesList");
            g_IOPSGetPowerSourceDescription = (fn_IOPSGetPowerSourceDescription_t)dlsym(h, "IOPSGetPowerSourceDescription");
            g_IOPSNotificationCreateRunLoopSource = (fn_IOPSNotificationCreateRunLoopSource_t)dlsym(h, "IOPSNotificationCreateRunLoopSource");
        }
    });
}

static BOOL getIOKitBattery(CGFloat *outLevel, BOOL *outCharging) {
    initIOKitSymbols();
    if (!g_IOPSCopyPowerSourcesInfo || !g_IOPSCopyPowerSourcesList || !g_IOPSGetPowerSourceDescription) {
        return NO;
    }
    CFTypeRef blob = g_IOPSCopyPowerSourcesInfo();
    if (!blob) return NO;
    CFArrayRef list = g_IOPSCopyPowerSourcesList(blob);
    if (!list) {
        CFRelease(blob);
        return NO;
    }
    BOOL found = NO;
    CFIndex cnt = CFArrayGetCount(list);
    for (CFIndex i = 0; i < cnt; i++) {
        CFDictionaryRef d = g_IOPSGetPowerSourceDescription(blob, CFArrayGetValueAtIndex(list, i));
        if (!d) continue;
        int cur = 100, mx = 100;
        CFNumberRef c = (CFNumberRef)CFDictionaryGetValue(d, CFSTR("Current Capacity"));
        CFNumberRef m = (CFNumberRef)CFDictionaryGetValue(d, CFSTR("Max Capacity"));
        if (c) CFNumberGetValue(c, kCFNumberIntType, &cur);
        if (m) CFNumberGetValue(m, kCFNumberIntType, &mx);
        if (mx > 0 && outLevel) {
            *outLevel = (CGFloat)cur / (CGFloat)mx;
        }
        CFBooleanRef chg = (CFBooleanRef)CFDictionaryGetValue(d, CFSTR("Is Charging"));
        CFStringRef pss = (CFStringRef)CFDictionaryGetValue(d, CFSTR("Power Source State"));
        BOOL onAC = (pss && CFEqual(pss, CFSTR("AC Power")));
        if (outCharging) {
            *outCharging = onAC || (chg && CFBooleanGetValue(chg));
        }
        found = YES;
        break;
    }
    CFRelease(list);
    CFRelease(blob);
    return found;
}

// MARK: - Status Bar Live Data Cache (Authoritative real-time system state)
static BOOL g_sbDataValid = NO;
static BOOL g_sbWifiEnabled = NO;
static int  g_sbWifiBars = 0;
static BOOL g_sbCellularEnabled = NO;
static int  g_sbCellularBars = 0;
static NSString *g_sbCellularType = nil;
static BOOL g_sbAirplaneEnabled = NO;
static CGFloat g_sbBatteryCapacity = -1.0;
static BOOL g_sbBatteryCharging = NO;
static BOOL g_sbBatterySaverMode = NO;

static void updateLiveDataFromStatusBar(UIView *container, id optData);

static BOOL isVPNActive(void) {
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) == 0) {
        for (struct ifaddrs *ifa = interfaces; ifa != NULL; ifa = ifa->ifa_next) {
            if (ifa->ifa_flags & IFF_UP) {
                if (strncmp(ifa->ifa_name, "utun", 4) == 0 ||
                    strncmp(ifa->ifa_name, "ppp", 3) == 0 ||
                    strncmp(ifa->ifa_name, "ipsec", 5) == 0) {
                    freeifaddrs(interfaces);
                    return YES;
                }
            }
        }
        freeifaddrs(interfaces);
    }
    return NO;
}

static BOOL isHeadphonesConnected(void) {
    Class avClass = objc_getClass("AVAudioSession");
    if (avClass && [avClass respondsToSelector:@selector(sharedInstance)]) {
        id session = [avClass performSelector:@selector(sharedInstance)];
        if (session && [session respondsToSelector:@selector(currentRoute)]) {
            id route = [session performSelector:@selector(currentRoute)];
            if (route && [route respondsToSelector:@selector(outputs)]) {
                NSArray *outputs = [route performSelector:@selector(outputs)];
                for (id output in outputs) {
                    if ([output respondsToSelector:@selector(portType)]) {
                        NSString *port = [output performSelector:@selector(portType)];
                        if ([port containsString:@"Bluetooth"] || [port containsString:@"Headphone"] || [port containsString:@"AirPlay"]) {
                            return YES;
                        }
                    }
                }
            }
        }
    }
    return NO;
}


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

// In-App Separated Position Preferences
static BOOL p_separateAppPosition = YES;
static CGFloat p_appOffsetX = 0.0;
static CGFloat p_appOffsetY = 0.0;
static CGFloat p_appIconScale = 1.0;
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

// Advanced Features (v1.3.9)
static BOOL p_swipeGesturesEnabled = YES;
static BOOL p_chargingBoltEnabled = YES;
static BOOL p_oledBlackMode = YES;
static BOOL p_springAnimations = YES;


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

    b = CFPreferencesGetAppBooleanValue(CFSTR("separateAppPosition"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_separateAppPosition = (BOOL)b;
    else if (prefs && prefs[@"separateAppPosition"]) p_separateAppPosition = [prefs[@"separateAppPosition"] boolValue];
    else p_separateAppPosition = YES;

    ref = CFPreferencesCopyAppValue(CFSTR("appOffsetX"), CFSTR("com.hoangnguyen.compactstatusbar"));
    if (ref) { p_appOffsetX = [(__bridge id)ref floatValue]; CFRelease(ref); }
    else if (prefs && prefs[@"appOffsetX"]) p_appOffsetX = [prefs[@"appOffsetX"] floatValue];
    else p_appOffsetX = 0.0;

    ref = CFPreferencesCopyAppValue(CFSTR("appOffsetY"), CFSTR("com.hoangnguyen.compactstatusbar"));
    if (ref) { p_appOffsetY = [(__bridge id)ref floatValue]; CFRelease(ref); }
    else if (prefs && prefs[@"appOffsetY"]) p_appOffsetY = [prefs[@"appOffsetY"] floatValue];
    else p_appOffsetY = 0.0;

    ref = CFPreferencesCopyAppValue(CFSTR("appIconScale"), CFSTR("com.hoangnguyen.compactstatusbar"));
    if (ref) { p_appIconScale = [(__bridge id)ref floatValue]; CFRelease(ref); }
    else if (prefs && prefs[@"appIconScale"]) p_appIconScale = [prefs[@"appIconScale"] floatValue];
    else p_appIconScale = 1.0;

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

    b = CFPreferencesGetAppBooleanValue(CFSTR("swipeGesturesEnabled"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_swipeGesturesEnabled = (BOOL)b;
    else if (prefs && prefs[@"swipeGesturesEnabled"]) p_swipeGesturesEnabled = [prefs[@"swipeGesturesEnabled"] boolValue];
    else p_swipeGesturesEnabled = YES;

    b = CFPreferencesGetAppBooleanValue(CFSTR("chargingBoltEnabled"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_chargingBoltEnabled = (BOOL)b;
    else if (prefs && prefs[@"chargingBoltEnabled"]) p_chargingBoltEnabled = [prefs[@"chargingBoltEnabled"] boolValue];
    else p_chargingBoltEnabled = YES;

    b = CFPreferencesGetAppBooleanValue(CFSTR("oledBlackMode"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_oledBlackMode = (BOOL)b;
    else if (prefs && prefs[@"oledBlackMode"]) p_oledBlackMode = [prefs[@"oledBlackMode"] boolValue];
    else p_oledBlackMode = YES;

    b = CFPreferencesGetAppBooleanValue(CFSTR("springAnimations"), CFSTR("com.hoangnguyen.compactstatusbar"), &keyExists);
    if (keyExists) p_springAnimations = (BOOL)b;
    else if (prefs && prefs[@"springAnimations"]) p_springAnimations = [prefs[@"springAnimations"] boolValue];
    else p_springAnimations = YES;
}

static void savePreferenceNumber(NSString *key, NSNumber *val) {
    CFPreferencesSetAppValue((CFStringRef)key, (__bridge CFPropertyListRef)val, CFSTR("com.hoangnguyen.compactstatusbar"));
    CFPreferencesAppSynchronize(CFSTR("com.hoangnguyen.compactstatusbar"));

    NSString *prefPath = @"/var/mobile/Library/Preferences/com.hoangnguyen.compactstatusbar.plist";
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:prefPath];
    if (!dict) dict = [NSMutableDictionary dictionary];
    dict[key] = val;
    [dict writeToFile:prefPath atomically:YES];
    chmod([prefPath UTF8String], 0666);

    NSString *jbPrefPath = @"/var/jb/var/mobile/Library/Preferences/com.hoangnguyen.compactstatusbar.plist";
    if ([[NSFileManager defaultManager] fileExistsAtPath:jbPrefPath]) {
        NSMutableDictionary *jbDict = [NSMutableDictionary dictionaryWithContentsOfFile:jbPrefPath];
        if (!jbDict) jbDict = [NSMutableDictionary dictionary];
        jbDict[key] = val;
        [jbDict writeToFile:jbPrefPath atomically:YES];
        chmod([jbPrefPath UTF8String], 0666);
    }

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
static BOOL isCellularDataActive(void);
static NSString *getRealCellularDataTech(void);
static int getWiFiSignalBars(void);
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

static void updateLiveDataFromStatusBar(UIView *container, id optData) {
    if (!container && !optData) return;
    UIView *hostBar = container;
    while (hostBar) {
        NSString *cn = NSStringFromClass([hostBar class]);
        if ([cn isEqualToString:@"_UIStatusBar"] || [cn isEqualToString:@"UIStatusBar"]) {
            break;
        }
        hostBar = hostBar.superview;
    }
    id cData = optData;
    if (!cData && hostBar) {
        if ([hostBar respondsToSelector:@selector(currentData)]) {
            cData = [hostBar performSelector:@selector(currentData)];
        }
        if (!cData && [hostBar respondsToSelector:@selector(currentAggregatedData)]) {
            cData = [hostBar performSelector:@selector(currentAggregatedData)];
        }
    }
    if (cData) {
        @try {
            id bEntry = [cData valueForKey:@"batteryEntry"];
            if (bEntry) {
                if ([bEntry respondsToSelector:@selector(capacity)]) {
                    g_sbBatteryCapacity = ((CGFloat (*)(id, SEL))objc_msgSend)(bEntry, @selector(capacity));
                }
                if ([bEntry respondsToSelector:@selector(state)]) {
                    NSInteger bState = ((NSInteger (*)(id, SEL))objc_msgSend)(bEntry, @selector(state));
                    g_sbBatteryCharging = (bState == 2 || bState == 3);
                }
                if ([bEntry respondsToSelector:@selector(saverModeActive)]) {
                    g_sbBatterySaverMode = ((BOOL (*)(id, SEL))objc_msgSend)(bEntry, @selector(saverModeActive));
                }
            }
            id wEntry = [cData valueForKey:@"wifiEntry"];
            if (wEntry && [wEntry respondsToSelector:@selector(isEnabled)]) {
                g_sbWifiEnabled = ((BOOL (*)(id, SEL))objc_msgSend)(wEntry, @selector(isEnabled));
                if ([wEntry respondsToSelector:@selector(displayValue)]) {
                    g_sbWifiBars = (int)((NSInteger (*)(id, SEL))objc_msgSend)(wEntry, @selector(displayValue));
                }
            } else {
                g_sbWifiEnabled = NO;
                g_sbWifiBars = 0;
            }
            id ceEntry = [cData valueForKey:@"cellularEntry"];
            if (ceEntry && [ceEntry respondsToSelector:@selector(isEnabled)]) {
                g_sbCellularEnabled = ((BOOL (*)(id, SEL))objc_msgSend)(ceEntry, @selector(isEnabled));
                if ([ceEntry respondsToSelector:@selector(displayValue)]) {
                    g_sbCellularBars = (int)((NSInteger (*)(id, SEL))objc_msgSend)(ceEntry, @selector(displayValue));
                }
                if ([ceEntry respondsToSelector:@selector(string)]) {
                    g_sbCellularType = [ceEntry performSelector:@selector(string)];
                }
            } else {
                g_sbCellularEnabled = NO;
                g_sbCellularBars = 0;
                g_sbCellularType = nil;
            }
            id apEntry = [cData valueForKey:@"airplaneModeEntry"];
            if (apEntry && [apEntry respondsToSelector:@selector(isEnabled)]) {
                g_sbAirplaneEnabled = ((BOOL (*)(id, SEL))objc_msgSend)(apEntry, @selector(isEnabled));
            } else {
                g_sbAirplaneEnabled = NO;
            }
            g_sbDataValid = YES;
        } @catch (__unused id e) {}
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

static NSString *getRealCellularDataTech(void) {
    Class teleClass = objc_getClass("SBTelephonyManager");
    if (teleClass && [teleClass respondsToSelector:@selector(sharedTelephonyManager)]) {
        id teleMgr = [teleClass performSelector:@selector(sharedTelephonyManager)];
        if (teleMgr && [teleMgr respondsToSelector:@selector(cellularDataTechnology)]) {
            id t = [teleMgr performSelector:@selector(cellularDataTechnology)];
            if (t) {
                NSString *s = [NSString stringWithFormat:@"%@", t];
                if ([s containsString:@"5G"]) return @"5G";
                if ([s containsString:@"LTE"]) return @"LTE";
                if ([s containsString:@"4G"]) return @"4G";
                if ([s containsString:@"3G"]) return @"3G";
                if ([s containsString:@"Edge"] || [s containsString:@"E"]) return @"E";
            }
        }
    }

    if (g_sbDataValid && g_sbCellularType && g_sbCellularType.length > 0) {
        return g_sbCellularType;
    }

    Class ctClass = objc_getClass("CTTelephonyNetworkInfo");
    if (ctClass) {
        id ctInfo = [[ctClass alloc] init];
        if (ctInfo) {
            NSString *tech = nil;
            if ([ctInfo respondsToSelector:@selector(serviceCurrentRadioAccessTechnology)]) {
                NSDictionary *dict = [ctInfo performSelector:@selector(serviceCurrentRadioAccessTechnology)];
                if (dict && dict.count > 0) {
                    tech = [dict.allValues firstObject];
                }
            } else if ([ctInfo respondsToSelector:@selector(currentRadioAccessTechnology)]) {
                tech = [ctInfo performSelector:@selector(currentRadioAccessTechnology)];
            }
            if (tech) {
                if ([tech containsString:@"NR"]) return @"5G";
                if ([tech containsString:@"LTE"]) return @"LTE";
                if ([tech containsString:@"HSDPA"] || [tech containsString:@"WCDMA"] || [tech containsString:@"HSUPA"]) return @"3G";
                if ([tech containsString:@"Edge"]) return @"E";
                if ([tech containsString:@"GPRS"]) return @"GPRS";
            }
        }
    }

    return @"4G";
}

static BOOL isCellularDataActive(void) {
    if (isAirplaneModeActive() || isNoSIMPresent()) return NO;

    Class teleClass = objc_getClass("SBTelephonyManager");
    if (teleClass && [teleClass respondsToSelector:@selector(sharedTelephonyManager)]) {
        id teleMgr = [teleClass performSelector:@selector(sharedTelephonyManager)];
        if (teleMgr) {
            if ([teleMgr respondsToSelector:@selector(isCellularDataActive)]) {
                return ((BOOL (*)(id, SEL))objc_msgSend)(teleMgr, @selector(isCellularDataActive));
            }
            if ([teleMgr respondsToSelector:@selector(isCellularDataEnabled)]) {
                BOOL enabled = ((BOOL (*)(id, SEL))objc_msgSend)(teleMgr, @selector(isCellularDataEnabled));
                if (!enabled) return NO;
            }
            if ([teleMgr respondsToSelector:@selector(isDataConnected)]) {
                BOOL connected = ((BOOL (*)(id, SEL))objc_msgSend)(teleMgr, @selector(isDataConnected));
                if (!connected) return NO;
            }
        }
    }

    if (g_sbDataValid) {
        return g_sbCellularEnabled;
    }

    Class ctClass = objc_getClass("CTTelephonyNetworkInfo");
    if (ctClass) {
        id ctInfo = [[ctClass alloc] init];
        if (ctInfo && [ctInfo respondsToSelector:@selector(serviceCurrentRadioAccessTechnology)]) {
            NSDictionary *dict = [ctInfo performSelector:@selector(serviceCurrentRadioAccessTechnology)];
            if (dict && dict.count > 0) return YES;
        }
    }
    return (getCellularSignalBars() > 0);
}

static NSString *getNetworkTypeString(void) {
    if (isAirplaneModeActive()) {
        return @"Máy bay";
    }
    if (isWifiActive()) {
        NSString *ssid = getConnectedSSID();
        if (ssid && ssid.length > 0) {
            if (isVPNActive()) {
                return [NSString stringWithFormat:@"%@ [VPN]", (ssid.length > 5 ? [ssid substringToIndex:5] : ssid)];
            }
            if (ssid.length > 7) {
                return [NSString stringWithFormat:@"%@..", [ssid substringToIndex:6]];
            }
            return ssid;
        }
        return isVPNActive() ? @"Wi-Fi [VPN]" : @"Wi-Fi";
    }
    if (isNoSIMPresent()) {
        return isVPNActive() ? @"No SIM [VPN]" : @"No SIM";
    }

    // Kiểm tra dữ liệu di động thực tế (Data connected)
    if (isCellularDataActive()) {
        NSString *tech = getRealCellularDataTech();
        return isVPNActive() ? [NSString stringWithFormat:@"%@ [VPN]", tech] : tech;
    }

    int bars = getCellularSignalBars();
    if (bars > 0) {
        // Có sóng nghe gọi nhưng tắt dữ liệu di động
        return isVPNActive() ? @"Chỉ thoại [VPN]" : @"Chỉ thoại";
    }

    return isVPNActive() ? @"SOS [VPN]" : @"SOS";
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
    // 1. Kiểm tra trực tiếp SBWiFiManager trong SpringBoard
    Class wifiClass = objc_getClass("SBWiFiManager");
    if (wifiClass && [wifiClass respondsToSelector:@selector(sharedInstance)]) {
        id wifiMgr = [wifiClass performSelector:@selector(sharedInstance)];
        if (wifiMgr) {
            if ([wifiMgr respondsToSelector:@selector(isPowered)]) {
                BOOL powered = ((BOOL (*)(id, SEL))objc_msgSend)(wifiMgr, @selector(isPowered));
                if (!powered) return NO; // Wi-Fi đã bị tắt nguồn hoàn toàn
            }
            if ([wifiMgr respondsToSelector:@selector(isAssociated)]) {
                BOOL assoc = ((BOOL (*)(id, SEL))objc_msgSend)(wifiMgr, @selector(isAssociated));
                if (assoc) return YES;
            }
            if ([wifiMgr respondsToSelector:@selector(isAssociatedToCurrentNetwork)]) {
                BOOL assoc = ((BOOL (*)(id, SEL))objc_msgSend)(wifiMgr, @selector(isAssociatedToCurrentNetwork));
                if (assoc) return YES;
            }
            if ([wifiMgr respondsToSelector:@selector(currentNetworkName)]) {
                NSString *name = [wifiMgr currentNetworkName];
                if (name && name.length > 0) return YES;
            }
        }
    }

    // 2. Kiểm tra tên SSID thực tế
    NSString *ssid = getConnectedSSID();
    if (ssid && ssid.length > 0) {
        return YES;
    }

    // 3. Fallback vào data model status bar
    if (g_sbDataValid) {
        return g_sbWifiEnabled;
    }
    return NO;
}

static int getWiFiSignalBars(void) {
    if (!isWifiActive()) return 0;

    Class wifiClass = objc_getClass("SBWiFiManager");
    if (wifiClass && [wifiClass respondsToSelector:@selector(sharedInstance)]) {
        id wifiMgr = [wifiClass performSelector:@selector(sharedInstance)];
        if (wifiMgr && [wifiMgr respondsToSelector:@selector(signalStrengthBars)]) {
            int bars = (int)((int (*)(id, SEL))objc_msgSend)(wifiMgr, @selector(signalStrengthBars));
            if (bars > 0) return bars;
        }
    }
    if (g_sbDataValid && g_sbWifiEnabled && g_sbWifiBars > 0) {
        return g_sbWifiBars;
    }
    return 3;
}

static BOOL isAirplaneModeActive(void) {
    // 1. Kiểm tra live RadiosPreferences (Apple preferences system daemon)
    Class rpClass = objc_getClass("RadiosPreferences");
    if (rpClass) {
        id rp = [[rpClass alloc] init];
        if (rp && [rp respondsToSelector:@selector(airplaneMode)]) {
            BOOL inPlane = ((BOOL (*)(id, SEL))objc_msgSend)(rp, @selector(airplaneMode));
            return inPlane;
        }
    }

    // 2. Kiểm tra live SBTelephonyManager
    Class teleClass = objc_getClass("SBTelephonyManager");
    if (teleClass && [teleClass respondsToSelector:@selector(sharedTelephonyManager)]) {
        id teleMgr = [teleClass performSelector:@selector(sharedTelephonyManager)];
        if (teleMgr && [teleMgr respondsToSelector:@selector(isInAirplaneMode)]) {
            BOOL inPlane = ((BOOL (*)(id, SEL))objc_msgSend)(teleMgr, @selector(isInAirplaneMode));
            return inPlane;
        }
    }

    Class apClass = objc_getClass("SBAirplaneModeController");
    if (apClass && [apClass respondsToSelector:@selector(sharedInstance)]) {
        id ap = [apClass performSelector:@selector(sharedInstance)];
        if (ap && [ap respondsToSelector:@selector(isInAirplaneMode)]) {
            BOOL inPlane = ((BOOL (*)(id, SEL))objc_msgSend)(ap, @selector(isInAirplaneMode));
            return inPlane;
        }
    }

    // 3. Fallback vào data model status bar
    if (g_sbDataValid) {
        return g_sbAirplaneEnabled;
    }
    return NO;
}

static BOOL isNoSIMPresent(void) {
    if (isAirplaneModeActive()) return NO;

    Class teleClass = objc_getClass("SBTelephonyManager");
    if (teleClass && [teleClass respondsToSelector:@selector(sharedTelephonyManager)]) {
        id teleMgr = [teleClass performSelector:@selector(sharedTelephonyManager)];
        if (teleMgr) {
            if ([teleMgr respondsToSelector:@selector(hasSIMCard)]) {
                BOOL has = ((BOOL (*)(id, SEL))objc_msgSend)(teleMgr, @selector(hasSIMCard));
                if (!has) return YES;
            }
            if ([teleMgr respondsToSelector:@selector(containsSIM)]) {
                BOOL has = ((BOOL (*)(id, SEL))objc_msgSend)(teleMgr, @selector(containsSIM));
                if (!has) return YES;
            }
            if ([teleMgr respondsToSelector:@selector(needsSIM)]) {
                BOOL needs = ((BOOL (*)(id, SEL))objc_msgSend)(teleMgr, @selector(needsSIM));
                if (needs) return YES;
            }
            if ([teleMgr respondsToSelector:@selector(SIMStatus)]) {
                id simStatus = [teleMgr performSelector:@selector(SIMStatus)];
                if (simStatus) {
                    NSString *statusStr = [NSString stringWithFormat:@"%@", simStatus];
                    if ([statusStr containsString:@"NotInserted"] ||
                        [statusStr containsString:@"Empty"] ||
                        [statusStr containsString:@"NoSIM"] ||
                        [statusStr containsString:@"Missing"]) {
                        return YES;
                    }
                }
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
        id teleMgr = [teleClass performSelector:@selector(sharedTelephonyManager)];
        if (teleMgr && [teleMgr respondsToSelector:@selector(signalStrengthBars)]) {
            int bars = (int)((int (*)(id, SEL))objc_msgSend)(teleMgr, @selector(signalStrengthBars));
            if (bars >= 0) return bars;
        }
    }

    if (g_sbDataValid && g_sbCellularEnabled) {
        return g_sbCellularBars;
    }
    return 0; // Trả về 0 khi mất sóng hoặc không xác định
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

static inline BOOL isAppOrLockScreen(UIView *view) {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleID && ![bundleID isEqualToString:@"com.apple.springboard"]) {
        return YES; // Đang chạy trong tiến trình ứng dụng con (Safari, Youtube, App Store...)
    }

    // 1. Kiểm tra Màn hình khoá (SBLockScreenManager)
    Class lsmClass = objc_getClass("SBLockScreenManager");
    if (lsmClass && [lsmClass respondsToSelector:@selector(sharedInstance)]) {
        id lsm = [lsmClass performSelector:@selector(sharedInstance)];
        if (lsm) {
            if ([lsm respondsToSelector:@selector(isUILocked)]) {
                if (((BOOL (*)(id, SEL))objc_msgSend)(lsm, @selector(isUILocked))) return YES;
            }
            if ([lsm respondsToSelector:@selector(isLockScreenVisible)]) {
                if (((BOOL (*)(id, SEL))objc_msgSend)(lsm, @selector(isLockScreenVisible))) return YES;
            }
        }
    }

    // 2. Kiểm tra cây phân cấp View của status bar
    UIView *v = view;
    while (v) {
        NSString *cn = NSStringFromClass([v class]);
        if ([cn containsString:@"CoverSheet"] || [cn containsString:@"LockScreen"] || [cn containsString:@"CS"]) {
            return YES; // Thuộc Màn hình khoá (CoverSheet / LockScreen)
        }
        if ([cn containsString:@"SBHomeScreen"] || [cn containsString:@"SBIconController"] || [cn containsString:@"SBFolder"]) {
            return NO; // Chắc chắn thuộc Màn hình chính (Home Screen)
        }
        if ([cn containsString:@"SBDeviceApplicationScene"] || [cn containsString:@"SBAppSwitcher"] || [cn containsString:@"SBApplication"]) {
            return YES; // Ứng dụng đang mở đè trong SpringBoard
        }
        v = v.superview;
    }

    // 3. Kiểm tra trạng thái Màn hình chính của SpringBoard (SBIconController)
    Class icClass = objc_getClass("SBIconController");
    if (icClass && [icClass respondsToSelector:@selector(sharedInstance)]) {
        id ic = [icClass performSelector:@selector(sharedInstance)];
        if (ic && [ic respondsToSelector:@selector(isShowingHomeScreen)]) {
            BOOL onHome = ((BOOL (*)(id, SEL))objc_msgSend)(ic, @selector(isShowingHomeScreen));
            if (onHome) return NO; // Đang hiển thị Màn hình chính
            return YES; // Đang ở trong app hoặc switcher
        }
    }

    return NO;
}

static inline BOOL isInsideApp(UIView *view) {
    return isAppOrLockScreen(view);
}

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
@property (nonatomic, strong) CAShapeLayer *airplaneCenterLayer;
@property (nonatomic, strong) CAShapeLayer *chargingBoltLayer;
@property (nonatomic, strong) UIColor *adaptiveTintColor;
@property (nonatomic, strong) UISwipeGestureRecognizer *swipeLeftGesture;
@property (nonatomic, strong) UISwipeGestureRecognizer *swipeRightGesture;

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

static void CompactStatusBarPowerChanged(void *ctx) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_activeStatusView) [g_activeStatusView updateStats];
        if (g_activeCCStatusView) [g_activeCCStatusView updateStats];
    });
}

static void registerIOKitPowerNotification(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        initIOKitSymbols();
        if (g_IOPSNotificationCreateRunLoopSource) {
            CFRunLoopSourceRef src = g_IOPSNotificationCreateRunLoopSource(CompactStatusBarPowerChanged, NULL);
            if (src) {
                CFRunLoopAddSource(CFRunLoopGetMain(), src, kCFRunLoopDefaultMode);
                CFRelease(src);
            }
        }
    });
}

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

        registerIOKitPowerNotification();
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        getNetworkTrafficBytes(&_lastDownloadBytes, &_lastUploadBytes);
        self.lastSampleTime = [NSDate timeIntervalSinceReferenceDate];

        [self updateStats];

        _timer = [NSTimer timerWithTimeInterval:1.0 target:self selector:@selector(updateStats) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (p_dragModeEnabled) {
        // Vùng chạm siêu lớn khi kéo thả: mở rộng 45pt mỗi bên và 35pt trên dưới (112x92pt)
        CGRect touchBounds = CGRectInset(self.bounds, -45.0, -35.0);
        return CGRectContainsPoint(touchBounds, point);
    }
    // Chế độ bình thường: vùng chạm tối thiểu 44x44pt chuẩn Apple HIG
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat padX = (w < 44.0) ? (44.0 - w) / 2.0 : 12.0;
    CGFloat padY = (h < 44.0) ? (44.0 - h) / 2.0 : 12.0;
    CGRect touchBounds = CGRectInset(self.bounds, -padX, -padY);
    return CGRectContainsPoint(touchBounds, point);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.userInteractionEnabled || self.hidden || self.alpha < 0.01) return nil;
    if ([self pointInside:point withEvent:event]) {
        return self;
    }
    return nil;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (p_dragModeEnabled && gestureRecognizer == self.dragPanGesture) {
        return YES; // Ép toàn bộ cử chỉ hệ thống (CoverSheet, Notification Center, Control Center, scroll) phải nhường quyền khi kéo thả
    }
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (p_dragModeEnabled && gestureRecognizer == self.dragPanGesture) {
        return NO;
    }
    return NO;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (p_dragModeEnabled && gestureRecognizer == self.dragPanGesture) {
        return YES;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return YES;
}

- (void)rebuildGaugePaths {
    CGPoint center = CGPointMake(11.0, 11.0);
    CGFloat radius = 9.0;

    if (p_batteryPercentMode == 4) {
        // Top Crown arc: 151.5 to 236.0 (left), 304.0 to 388.5 (right)
        UIBezierPath *crownPath = [UIBezierPath bezierPath];
        [crownPath addArcWithCenter:center radius:radius startAngle:151.5 * M_PI / 180.0 endAngle:236.0 * M_PI / 180.0 clockwise:YES];
        UIBezierPath *sub2 = [UIBezierPath bezierPathWithArcCenter:center radius:radius startAngle:304.0 * M_PI / 180.0 endAngle:388.5 * M_PI / 180.0 clockwise:YES];
        [crownPath appendPath:sub2];

        _trackLayer.path = crownPath.CGPath;
        _progressLayer.path = crownPath.CGPath;
    } else {
        CGFloat startAngle = 151.5 * M_PI / 180.0;
        CGFloat endAngle = 388.5 * M_PI / 180.0;
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
    self.showRAM = p_showRAM;
    [self rebuildGaugePaths];
    CGFloat scale = 1.0;
    if (self.isControlCenter) {
        scale = p_ccIconScale;
    } else if (p_separateAppPosition && isAppOrLockScreen(self)) {
        scale = p_appIconScale;
    } else {
        scale = p_iconScale;
    }
    if (scale < 0.2) scale = 1.0;
    self.transform = CGAffineTransformMakeScale(scale, scale);
    self.alpha = p_iconOpacity;
    if (p_dragModeEnabled) {
        self.layer.borderColor = self.isControlCenter ? [UIColor colorWithRed:1.0 green:0.8 blue:0.2 alpha:1.0].CGColor : [UIColor colorWithRed:0.2 green:0.9 blue:0.4 alpha:1.0].CGColor;
        self.layer.borderWidth = 2.0;
        self.layer.cornerRadius = 8.0;
        self.backgroundColor = self.isControlCenter ? [UIColor colorWithRed:1.0 green:0.8 blue:0.2 alpha:0.35] : [UIColor colorWithRed:0.2 green:0.9 blue:0.4 alpha:0.35];
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
        if (self.swipeLeftGesture) self.swipeLeftGesture.enabled = NO;
        if (self.swipeRightGesture) self.swipeRightGesture.enabled = NO;

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
        self.backgroundColor = [UIColor clearColor];
        if (self.dragPanGesture) {
            self.dragPanGesture.enabled = NO;
        }
        if (self.singleTapGesture) self.singleTapGesture.enabled = YES;
        if (self.doubleTapGesture) self.doubleTapGesture.enabled = YES;
        if (self.longPressGesture) self.longPressGesture.enabled = YES;
        if (self.swipeLeftGesture) self.swipeLeftGesture.enabled = p_swipeGesturesEnabled;
        if (self.swipeRightGesture) self.swipeRightGesture.enabled = p_swipeGesturesEnabled;
    }
}

- (void)handleDragPan:(UIPanGestureRecognizer *)pan {
    UIView *superview = self.superview;
    if (!superview) return;

    if (pan.state == UIGestureRecognizerStateBegan) {
        triggerHaptic(1);
        [UIView animateWithDuration:0.12 animations:^{
            self.transform = CGAffineTransformScale(self.transform, 1.25, 1.25);
            self.alpha = 0.85;
        }];
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
            CGFloat offX = 0.0;
            CGFloat offY = 0.0;
            if (self.isControlCenter) {
                offX = p_ccOffsetX;
                offY = p_ccOffsetY;
            } else if (p_separateAppPosition && isAppOrLockScreen(self)) {
                offX = p_appOffsetX;
                offY = p_appOffsetY;
            } else {
                offX = p_offsetX;
                offY = p_offsetY;
            }
            CGFloat totalW = self.pillContainerView.frame.size.width;
            if (totalW < 22.0) totalW = 22.0;
            self.anchorCenter = CGPointMake(self.center.x - (totalW - 22.0) / 2.0 - offX, self.center.y - offY);
        }
    }

    CGFloat totalW = self.pillContainerView.frame.size.width;
    if (totalW < 22.0) totalW = 22.0;
    CGFloat curX = (self.center.x - (totalW - 22.0) / 2.0) - self.anchorCenter.x;
    CGFloat curY = self.center.y - self.anchorCenter.y;
    BOOL inApp = isAppOrLockScreen(self);
    if (self.isControlCenter) {
        p_ccOffsetX = curX;
        p_ccOffsetY = curY;
    } else if (p_separateAppPosition && inApp) {
        p_appOffsetX = curX;
        p_appOffsetY = curY;
    } else {
        p_offsetX = curX;
        p_offsetY = curY;
    }

    [self updateDragHUDWithX:curX y:curY finished:(pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled)];

    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        [UIView animateWithDuration:0.2 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:0 animations:^{
            CGFloat scale = 1.0;
            if (self.isControlCenter) scale = p_ccIconScale;
            else if (p_separateAppPosition && isAppOrLockScreen(self)) scale = p_appIconScale;
            else scale = p_iconScale;
            if (scale < 0.2) scale = 1.0;
            self.transform = CGAffineTransformMakeScale(scale, scale);
            self.alpha = p_iconOpacity;
        } completion:nil];
        if (self.isControlCenter) {
            savePreferenceNumber(@"ccOffsetX", @(curX));
            savePreferenceNumber(@"ccOffsetY", @(curY));
        } else if (p_separateAppPosition && inApp) {
            savePreferenceNumber(@"appOffsetX", @(curX));
            savePreferenceNumber(@"appOffsetY", @(curY));
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

    BOOL inApp = isAppOrLockScreen(self);
    NSString *area = self.isControlCenter ? @"🎛️ Control Center" : (inApp ? @"📱 Khoá & Ứng dụng" : @"🏠 Màn hình chính");
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

    // Wi-Fi fan: Exact cubic Bezier curves ported from 436-unit Android Duo geometry
    UIBezierPath *tp = [UIBezierPath bezierPath];
    [tp moveToPoint:CGPointMake(11.0, 12.36)];
    [tp addCurveToPoint:CGPointMake(9.89, 13.22) controlPoint1:CGPointMake(10.29, 12.36) controlPoint2:CGPointMake(9.89, 12.82)];
    [tp addCurveToPoint:CGPointMake(10.80, 14.43) controlPoint1:CGPointMake(9.89, 13.57) controlPoint2:CGPointMake(10.44, 14.13)];
    [tp addCurveToPoint:CGPointMake(11.25, 14.43) controlPoint1:CGPointMake(10.95, 14.58) controlPoint2:CGPointMake(11.10, 14.58)];
    [tp addCurveToPoint:CGPointMake(12.16, 13.22) controlPoint1:CGPointMake(11.61, 14.13) controlPoint2:CGPointMake(12.16, 13.57)];
    [tp addCurveToPoint:CGPointMake(11.0, 12.36) controlPoint1:CGPointMake(12.16, 12.82) controlPoint2:CGPointMake(11.71, 12.36)];
    [tp closePath];

    _wifiDotLayer = [CAShapeLayer layer];
    _wifiDotLayer.fillColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
    _wifiDotLayer.path = tp.CGPath;
    [_gaugeContainerView.layer addSublayer:_wifiDotLayer];

    UIBezierPath *w1 = [UIBezierPath bezierPath];
    [w1 moveToPoint:CGPointMake(9.08, 11.66)];
    [w1 addCurveToPoint:CGPointMake(13.02, 11.66) controlPoint1:CGPointMake(10.14, 10.60) controlPoint2:CGPointMake(11.96, 10.60)];

    _wifiWave1Layer = [CAShapeLayer layer];
    _wifiWave1Layer.fillColor = [UIColor clearColor].CGColor;
    _wifiWave1Layer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
    _wifiWave1Layer.lineWidth = 1.15;
    _wifiWave1Layer.lineCap = kCALineCapRound;
    _wifiWave1Layer.path = w1.CGPath;
    [_gaugeContainerView.layer addSublayer:_wifiWave1Layer];

    UIBezierPath *w2 = [UIBezierPath bezierPath];
    [w2 moveToPoint:CGPointMake(7.67, 10.14)];
    [w2 addCurveToPoint:CGPointMake(14.38, 10.14) controlPoint1:CGPointMake(9.39, 8.43) controlPoint2:CGPointMake(12.61, 8.43)];

    _wifiWave2Layer = [CAShapeLayer layer];
    _wifiWave2Layer.fillColor = [UIColor clearColor].CGColor;
    _wifiWave2Layer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
    _wifiWave2Layer.lineWidth = 1.15;
    _wifiWave2Layer.lineCap = kCALineCapRound;
    _wifiWave2Layer.path = w2.CGPath;
    [_gaugeContainerView.layer addSublayer:_wifiWave2Layer];

    // Nose-up vector airplane silhouette in center
    UIBezierPath *apCenter = [UIBezierPath bezierPath];
    [apCenter moveToPoint:CGPointMake(11.0, 6.66)];
    [apCenter addCurveToPoint:CGPointMake(10.39, 7.67) controlPoint1:CGPointMake(10.65, 6.66) controlPoint2:CGPointMake(10.44, 7.06)];
    [apCenter addLineToPoint:CGPointMake(10.19, 9.79)];
    [apCenter addLineToPoint:CGPointMake(7.37, 11.50)];
    [apCenter addCurveToPoint:CGPointMake(6.91, 12.41) controlPoint1:CGPointMake(6.96, 11.76) controlPoint2:CGPointMake(6.81, 12.11)];
    [apCenter addCurveToPoint:CGPointMake(7.82, 12.61) controlPoint1:CGPointMake(7.01, 12.72) controlPoint2:CGPointMake(7.42, 12.77)];
    [apCenter addLineToPoint:CGPointMake(10.19, 11.76)];
    [apCenter addLineToPoint:CGPointMake(10.14, 13.47)];
    [apCenter addLineToPoint:CGPointMake(8.93, 14.43)];
    [apCenter addCurveToPoint:CGPointMake(8.78, 15.14) controlPoint1:CGPointMake(8.68, 14.63) controlPoint2:CGPointMake(8.63, 14.94)];
    [apCenter addCurveToPoint:CGPointMake(9.49, 15.19) controlPoint1:CGPointMake(8.93, 15.34) controlPoint2:CGPointMake(9.23, 15.29)];
    [apCenter addLineToPoint:CGPointMake(11.0, 14.58)];
    [apCenter addLineToPoint:CGPointMake(12.51, 15.19)];
    [apCenter addCurveToPoint:CGPointMake(13.22, 15.14) controlPoint1:CGPointMake(12.77, 15.29) controlPoint2:CGPointMake(13.07, 15.34)];
    [apCenter addCurveToPoint:CGPointMake(13.07, 14.43) controlPoint1:CGPointMake(13.37, 14.94) controlPoint2:CGPointMake(13.32, 14.63)];
    [apCenter addLineToPoint:CGPointMake(11.86, 13.47)];
    [apCenter addLineToPoint:CGPointMake(11.81, 11.76)];
    [apCenter addLineToPoint:CGPointMake(14.18, 12.61)];
    [apCenter addCurveToPoint:CGPointMake(15.09, 12.41) controlPoint1:CGPointMake(14.58, 12.77) controlPoint2:CGPointMake(14.99, 12.72)];
    [apCenter addCurveToPoint:CGPointMake(14.63, 11.50) controlPoint1:CGPointMake(15.19, 12.11) controlPoint2:CGPointMake(15.04, 11.76)];
    [apCenter addLineToPoint:CGPointMake(11.81, 9.79)];
    [apCenter addLineToPoint:CGPointMake(11.61, 7.67)];
    [apCenter addCurveToPoint:CGPointMake(11.0, 6.66) controlPoint1:CGPointMake(11.56, 7.06) controlPoint2:CGPointMake(11.35, 6.66)];
    [apCenter closePath];

    _airplaneCenterLayer = [CAShapeLayer layer];
    _airplaneCenterLayer.path = apCenter.CGPath;
    _airplaneCenterLayer.fillColor = [UIColor whiteColor].CGColor;
    _airplaneCenterLayer.hidden = YES;
    [_gaugeContainerView.layer addSublayer:_airplaneCenterLayer];

    // Charging Bolt Vector Layer
    UIBezierPath *boltPath = [UIBezierPath bezierPath];
    [boltPath moveToPoint:CGPointMake(11.2, 7.2)];
    [boltPath addLineToPoint:CGPointMake(9.4, 11.0)];
    [boltPath addLineToPoint:CGPointMake(10.8, 11.0)];
    [boltPath addLineToPoint:CGPointMake(10.1, 14.8)];
    [boltPath addLineToPoint:CGPointMake(12.6, 10.4)];
    [boltPath addLineToPoint:CGPointMake(11.2, 10.4)];
    [boltPath closePath];

    _chargingBoltLayer = [CAShapeLayer layer];
    _chargingBoltLayer.path = boltPath.CGPath;
    _chargingBoltLayer.fillColor = [UIColor colorWithRed:52/255.0 green:199/255.0 blue:89/255.0 alpha:1.0].CGColor;
    _chargingBoltLayer.hidden = YES;
    [_gaugeContainerView.layer addSublayer:_chargingBoltLayer];

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

    BOOL is5 = p_dotCount5;
    if (is5) {
        CGPoint center = CGPointMake(11.0, 11.0);
        CGFloat radius = 9.0;
        NSArray *angles = @[@(122.0), @(106.0), @(90.0), @(74.0), @(58.0)];
        CGFloat dr = 0.75;
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
    } else {
        // Exact 436-unit Android Duo geometry (cradled arc)
        const CGPoint duoDots[4] = {
            {6.26, 17.61},
            {9.23, 19.12},
            {12.77, 19.12},
            {15.74, 17.61}
        };
        CGFloat dr = 0.91;
        for (int i = 0; i < 4; i++) {
            CGPoint pt = duoDots[i];
            UIBezierPath *dp = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(pt.x - dr, pt.y - dr, dr * 2.0, dr * 2.0)];
            CAShapeLayer *dl = [CAShapeLayer layer];
            dl.path = dp.CGPath;
            dl.fillColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
            [_gaugeContainerView.layer addSublayer:dl];
            [_dotLayers addObject:dl];
        }
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

    self.swipeLeftGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeLeft)];
    self.swipeLeftGesture.direction = UISwipeGestureRecognizerDirectionLeft;
    self.swipeLeftGesture.delegate = self;
    self.swipeLeftGesture.enabled = p_swipeGesturesEnabled;
    [self addGestureRecognizer:self.swipeLeftGesture];

    self.swipeRightGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeRight)];
    self.swipeRightGesture.direction = UISwipeGestureRecognizerDirectionRight;
    self.swipeRightGesture.delegate = self;
    self.swipeRightGesture.enabled = p_swipeGesturesEnabled;
    [self addGestureRecognizer:self.swipeRightGesture];
}

- (void)handleSwipeLeft {
    if (!p_swipeGesturesEnabled || p_dragModeEnabled) return;
    triggerHaptic(1);
    executeAction(1, self); // Khóa màn hình
}

- (void)handleSwipeRight {
    if (!p_swipeGesturesEnabled || p_dragModeEnabled) return;
    triggerHaptic(1);
    [self toggleRAMDisplay]; // Đổi nhanh Pin / RAM
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
    p_showRAM = self.showRAM;
    savePreferenceNumber(@"showRAM", @(self.showRAM));
    [self updateStats];
    if (g_activeStatusView && g_activeStatusView != self) {
        g_activeStatusView.showRAM = self.showRAM;
        [g_activeStatusView updateStats];
    }
    if (g_activeCCStatusView && g_activeCCStatusView != self) {
        g_activeCCStatusView.showRAM = self.showRAM;
        [g_activeCCStatusView updateStats];
    }
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
    // Luôn chủ động trích xuất dữ liệu mới nhất từ _UIStatusBar cha
    UIView *host = self.superview;
    while (host && ![host isKindOfClass:objc_getClass("_UIStatusBar")] && ![host isKindOfClass:objc_getClass("UIStatusBar")]) {
        host = host.superview;
    }
    if (host) {
        updateLiveDataFromStatusBar(host, nil);
    }

    // 0. Cập nhật tỷ lệ phóng to (Scale) thích ứng theo đúng ngữ cảnh hiện tại
    CGFloat targetScale = 1.0;
    if (self.isControlCenter) {
        targetScale = p_ccIconScale;
    } else if (p_separateAppPosition && isAppOrLockScreen(self)) {
        targetScale = p_appIconScale;
    } else {
        targetScale = p_iconScale;
    }
    if (targetScale < 0.2) targetScale = 1.0;
    CGAffineTransform targetTransform = CGAffineTransformMakeScale(targetScale, targetScale);
    if (!CGAffineTransformEqualToTransform(self.transform, targetTransform)) {
        self.transform = targetTransform;
    }

    // 0. Trích xuất Pin tức thời (Priority 1: _UIStatusBarData batteryEntry, Priority 2: IOKit, Priority 3: UIDevice)
    CGFloat bat = 1.0;
    BOOL charging = NO;
    BOOL lowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;

    if (g_sbBatteryCapacity >= 0.0) {
        bat = g_sbBatteryCapacity;
        charging = g_sbBatteryCharging;
        if (g_sbBatterySaverMode) lowPower = YES;
    } else if (getIOKitBattery(&bat, &charging)) {
        // Đọc trực tiếp từ IOKit phần cứng
    } else {
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        float rawLevel = [UIDevice currentDevice].batteryLevel;
        bat = rawLevel < 0 ? 1.0 : (CGFloat)rawLevel;
        UIDeviceBatteryState bState = [UIDevice currentDevice].batteryState;
        charging = (bState == UIDeviceBatteryStateCharging || bState == UIDeviceBatteryStateFull);
    }

    CGFloat ramRatio = getRAMUsedRatio(NULL, NULL);
    int pct = self.showRAM ? (int)(ramRatio * 100) : (int)lroundf(bat * 100.0f);

    // 1. Màu sắc và độ sáng thích ứng (Adaptive Color Extraction)
    UIColor *tintColor = [UIColor whiteColor];
    switch (p_colorMode) {
        case 1: tintColor = [UIColor colorWithWhite:1.0 alpha:0.95]; break; // Đơn sắc trắng
        case 2: tintColor = [UIColor colorWithRed:0.0 green:0.96 blue:1.0 alpha:1.0]; break; // Neon Cyan
        case 3: tintColor = [UIColor colorWithRed:0.75 green:0.33 blue:0.93 alpha:1.0]; break; // Neon Tím
        case 4: tintColor = [UIColor colorWithRed:1.0 green:0.08 blue:0.58 alpha:1.0]; break; // Neon Hồng
        case 5: tintColor = [UIColor colorWithRed:0.22 green:1.0 blue:0.08 alpha:1.0]; break; // Neon Xanh Lá
        case 6: tintColor = [UIColor colorWithRed:1.0 green:0.42 blue:0.21 alpha:1.0]; break; // Neon Cam
        case 7: tintColor = [UIColor colorWithRed:1.0 green:0.84 blue:0.0 alpha:1.0]; break; // Vàng Gold
        case 8: tintColor = [UIColor colorWithRed:1.0 green:0.20 blue:0.40 alpha:1.0]; break; // Đỏ Ruby
        case 9: tintColor = [UIColor colorWithRed:p_customGaugeR green:p_customGaugeG blue:p_customGaugeB alpha:1.0]; break; // Custom RGB
        default: { // Mode 0: Dynamic / Adaptive theo nền màn hình
            tintColor = self.adaptiveTintColor ?: [UIColor whiteColor];
            break;
        }
    }

    CGFloat lum = 1.0;
    CGFloat cr = 1, cg = 1, cb = 1, ca = 1;
    if ([tintColor getRed:&cr green:&cg blue:&cb alpha:&ca]) {
        lum = 0.299f * cr + 0.587f * cg + 0.114f * cb;
    } else {
        CGFloat cw = 1;
        if ([tintColor getWhite:&cw alpha:&ca]) lum = cw;
    }
    BOOL isDark = (lum < 0.5f);

    UIColor *activeColor = tintColor;
    UIColor *inactiveColor = isDark ? [UIColor colorWithWhite:0.0 alpha:0.22] : [UIColor colorWithWhite:1.0 alpha:0.25];

    UIColor *batteryArcColor = activeColor;
    if (self.showRAM) {
        if (ramRatio > 0.85) batteryArcColor = [UIColor colorWithRed:1.0 green:0.25 blue:0.25 alpha:1.0];
        else if (ramRatio > 0.65) batteryArcColor = [UIColor colorWithRed:1.0 green:0.60 blue:0.10 alpha:1.0];
        else batteryArcColor = [UIColor colorWithRed:0.20 green:0.80 blue:1.0 alpha:1.0];
    } else {
        if (charging) {
            batteryArcColor = [UIColor colorWithRed:52/255.0 green:199/255.0 blue:89/255.0 alpha:1.0]; // Apple System Green #34C759
        } else if (lowPower) {
            batteryArcColor = [UIColor colorWithRed:255/255.0 green:204/255.0 blue:0/255.0 alpha:1.0]; // Apple System Yellow #FFCC00
        } else if (pct <= 20) {
            batteryArcColor = [UIColor colorWithRed:255/255.0 green:59/255.0 blue:48/255.0 alpha:1.0]; // Apple System Red #FF3B30
        }
    }

    _trackLayer.strokeColor = inactiveColor.CGColor;
    _progressLayer.strokeColor = batteryArcColor.CGColor;

    // 2. Tiến trình vòng cung Pin (Hỗ trợ Mode 4 Top Crown chính xác theo O.status)
    CGPoint center = CGPointMake(11.0, 11.0);
    CGFloat radius = 9.0;
    CGFloat lvl = self.showRAM ? MIN(MAX(ramRatio, 0.0), 1.0) : MIN(MAX(bat, 0.0), 1.0);

    if (p_batteryPercentMode == 4) {
        CGFloat oStart = 151.5;
        BOOL isFull = (pct >= 100);
        CGFloat leftTopEnd = isFull ? 231.0 : 236.0;
        CGFloat rightTopStart = isFull ? 309.0 : 304.0;
        CGFloat oEnd = 388.5;

        UIBezierPath *crownTrack = [UIBezierPath bezierPath];
        [crownTrack addArcWithCenter:center radius:radius startAngle:oStart * M_PI / 180.0 endAngle:leftTopEnd * M_PI / 180.0 clockwise:YES];
        UIBezierPath *rTrack = [UIBezierPath bezierPathWithArcCenter:center radius:radius startAngle:rightTopStart * M_PI / 180.0 endAngle:oEnd * M_PI / 180.0 clockwise:YES];
        [crownTrack appendPath:rTrack];
        _trackLayer.path = crownTrack.CGPath;

        CGFloat leftSpan = leftTopEnd - oStart;
        CGFloat fillSpan = leftSpan * lvl;

        UIBezierPath *progPath = [UIBezierPath bezierPath];
        if (fillSpan > 0.1) {
            // Cánh trái: tăng đều đặn từ đáy (151.5°) lên đỉnh (236°)
            [progPath addArcWithCenter:center radius:radius startAngle:oStart * M_PI / 180.0 endAngle:(oStart + fillSpan) * M_PI / 180.0 clockwise:YES];
            // Cánh phải: đối xứng hoàn hảo, tăng đều đặn từ đáy (388.5°) lên đỉnh (304°)
            [progPath moveToPoint:CGPointMake(center.x + radius * cos(oEnd * M_PI / 180.0), center.y + radius * sin(oEnd * M_PI / 180.0))];
            [progPath addArcWithCenter:center radius:radius startAngle:oEnd * M_PI / 180.0 endAngle:(oEnd - fillSpan) * M_PI / 180.0 clockwise:NO];
        }
        _progressLayer.path = progPath.CGPath;
        _progressLayer.strokeEnd = 1.0;
    } else {
        CGFloat startAngle = 151.5 * M_PI / 180.0;
        CGFloat endAngle = 388.5 * M_PI / 180.0;
        UIBezierPath *arcPath = [UIBezierPath bezierPathWithArcCenter:center radius:radius startAngle:startAngle endAngle:endAngle clockwise:YES];
        _trackLayer.path = arcPath.CGPath;
        _progressLayer.path = arcPath.CGPath;
        _progressLayer.strokeEnd = lvl;
    }

    // 3. Hiệu ứng Breathing Glow khi đang sạc
    if (charging && p_breathingGlow) {
        if (!self.isBreathing) {
            _progressLayer.shadowColor = batteryArcColor.CGColor;
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

    BOOL hasSpeed = NO;
    if (p_speedThreshold == 1 && (downSpeed > 51200.0 || upSpeed > 51200.0)) hasSpeed = YES;
    else if (p_speedThreshold == 2 && (downSpeed > 102400.0 || upSpeed > 102400.0)) hasSpeed = YES;
    else if (p_speedThreshold == 3) hasSpeed = YES;

    // 5. Hiển thị % pin trên đỉnh vòm (Mode 4: Top Crown)
    if (p_batteryPercentMode == 4) {
        _topPercentLabel.hidden = NO;
        _topPercentLabel.text = [NSString stringWithFormat:@"%d", pct];
        _topPercentLabel.font = [UIFont systemFontOfSize:(pct >= 100 ? 5.5 : 6.4) weight:UIFontWeightBold];
        _topPercentLabel.frame = CGRectMake(0.0, 0.0, 22.0, 8.0);
        _topPercentLabel.textColor = (pct <= 20 && !charging) ? [UIColor colorWithRed:255/255.0 green:59/255.0 blue:48/255.0 alpha:1.0] : activeColor;
    } else {
        _topPercentLabel.hidden = YES;
    }

    // 6. Hiển thị ở tâm Gauge: Quạt Wi-Fi, Máy bay hoặc % Pin
    BOOL wifiOn = isWifiActive();
    int wifiBars = getWiFiSignalBars();
    BOOL isAirplane = isAirplaneModeActive();
    BOOL isNoSim = isNoSIMPresent();

    _chargingBoltLayer.hidden = YES;

    if (p_batteryPercentMode == 1) { // Pin ở tâm
        _wifiDotLayer.hidden = YES;
        _wifiWave1Layer.hidden = YES;
        _wifiWave2Layer.hidden = YES;
        _airplaneCenterLayer.hidden = YES;
        _centerLabel.hidden = NO;
        if (self.showRAM) {
            _centerLabel.text = [NSString stringWithFormat:@"%d", pct];
        } else {
            _centerLabel.text = charging ? [NSString stringWithFormat:@"%d⚡", pct] : [NSString stringWithFormat:@"%d", pct];
        }
        _centerLabel.textColor = batteryArcColor;
    } else if (p_badgeStyle == 2 && hasSpeed) { // Tốc độ mạng ở tâm
        _wifiDotLayer.hidden = YES;
        _wifiWave1Layer.hidden = YES;
        _wifiWave2Layer.hidden = YES;
        _airplaneCenterLayer.hidden = YES;
        _centerLabel.hidden = NO;
        _centerLabel.text = formatSpeedCompact(downSpeed > 0 ? downSpeed : upSpeed);
        _centerLabel.textColor = [UIColor colorWithRed:0.25 green:0.90 blue:0.40 alpha:1.0];
    } else if (isAirplane && !wifiOn) { // Chế độ máy bay (Wi-Fi tắt) -> Hiển thị silhouette máy bay ở tâm
        _wifiDotLayer.hidden = YES;
        _wifiWave1Layer.hidden = YES;
        _wifiWave2Layer.hidden = YES;
        _centerLabel.hidden = YES;
        _airplaneCenterLayer.hidden = NO;
        _airplaneCenterLayer.fillColor = activeColor.CGColor;
    } else if (wifiOn) { // Wi-Fi kết nối -> Hiển thị quạt Wi-Fi đa mức sóng
        _airplaneCenterLayer.hidden = YES;
        _centerLabel.hidden = YES;
        _wifiDotLayer.hidden = NO;
        _wifiWave1Layer.hidden = NO;
        _wifiWave2Layer.hidden = NO;

        _wifiDotLayer.fillColor = activeColor.CGColor;
        _wifiWave1Layer.strokeColor = (wifiBars >= 1 ? activeColor : inactiveColor).CGColor;
        _wifiWave2Layer.strokeColor = (wifiBars >= 2 ? activeColor : inactiveColor).CGColor;
    } else { // Không có Wi-Fi (Sử dụng mạng di động hoặc ngoại tuyến)
        _wifiDotLayer.hidden = YES;
        _wifiWave1Layer.hidden = YES;
        _wifiWave2Layer.hidden = YES;
        _airplaneCenterLayer.hidden = YES;

        if (isAirplane) {
            _centerLabel.hidden = YES;
            _airplaneCenterLayer.hidden = NO;
            _airplaneCenterLayer.fillColor = activeColor.CGColor;
        } else if (isNoSim) {
            // Không có SIM: Tâm Gauge tinh gọn, khe đáy hiển thị icon thẻ SIM gạch chéo
            _centerLabel.hidden = YES;
        } else {
            int cBars = getCellularSignalBars();
            if (cBars <= 0) {
                // Mất sóng hoàn toàn (No Service): Hiện SOS
                _centerLabel.hidden = NO;
                _centerLabel.text = @"SOS";
                _centerLabel.textColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.35 alpha:0.95];
            } else if (charging && p_batteryPercentMode != 4 && p_chargingBoltEnabled) {
                // Đang cắm sạc: Hiện tia sét sạc ở tâm
                _centerLabel.hidden = YES;
                _chargingBoltLayer.hidden = NO;
                _chargingBoltLayer.fillColor = batteryArcColor.CGColor;
            } else {
                // Đang dùng mạng di động bình thường:
                // Tâm Gauge hoàn toàn TRỐNG và TINH GỌN (chuẩn thiết kế iPhone Duo / DuoBar gốc).
                // Sóng di động đã được hiển thị bằng 4 chấm ở đáy; Loại mạng (4G/5G/LTE) hiển thị ở thanh Pill.
                _centerLabel.hidden = YES;
            }
        }
    }

    // 7. Nhãn % Pin ở mép trái (Mode 3)
    if (p_batteryPercentMode == 3) {
        _sidePercentLabel.hidden = NO;
        _sidePercentLabel.text = [NSString stringWithFormat:@"%d%%", pct];
        _sidePercentLabel.textColor = batteryArcColor;
    } else {
        _sidePercentLabel.hidden = YES;
    }

    // 8. Chấm sóng di động, Chế độ máy bay & Không có SIM
    if (isAirplane) {
        if (wifiOn) {
            if (_airplaneView.image) {
                _airplaneView.hidden = NO;
                _airplaneView.tintColor = activeColor;
                if (_airplaneVectorLayer) _airplaneVectorLayer.hidden = YES;
            } else if (_airplaneVectorLayer) {
                _airplaneVectorLayer.hidden = NO;
                _airplaneVectorLayer.strokeColor = activeColor.CGColor;
                _airplaneView.hidden = YES;
            }
        } else {
            _airplaneView.hidden = YES;
            if (_airplaneVectorLayer) _airplaneVectorLayer.hidden = YES;
        }
        _noSimCardLayer.hidden = YES;
        _noSimSlashLayer.hidden = YES;
        for (CAShapeLayer *dl in _dotLayers) dl.hidden = YES;
    } else if (isNoSim) {
        _airplaneView.hidden = YES;
        if (_airplaneVectorLayer) _airplaneVectorLayer.hidden = YES;
        _noSimCardLayer.hidden = NO;
        _noSimCardLayer.strokeColor = activeColor.CGColor;
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
            dot.fillColor = isLit ? activeColor.CGColor : inactiveColor.CGColor;
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
            _batteryPercentLabel.textColor = batteryArcColor;
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
            if (p_colorMode == 0) {
                _ssidLabel.textColor = isDark ? [UIColor colorWithWhite:0.1 alpha:0.9] : [UIColor colorWithWhite:0.92 alpha:1.0];
            }
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

        CGRect targetExtraFrame = CGRectMake(22.0, 0.0, extraW, 22.0);
        CGRect targetPillFrame = CGRectMake(0.0, 0.0, totalW, 22.0);
        CGRect targetBounds = CGRectMake(0.0, 0.0, totalW, 22.0);

        // Hiệu ứng co giãn đàn hồi mượt mà (Spring animation)
        if (!CGSizeEqualToSize(self.bounds.size, targetBounds.size)) {
            if (p_springAnimations) {
                [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.4 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
                    self->_extraInfoContainer.frame = targetExtraFrame;
                    self->_pillContainerView.frame = targetPillFrame;
                    self.bounds = targetBounds;
                } completion:nil];
            } else {
                self->_extraInfoContainer.frame = targetExtraFrame;
                self->_pillContainerView.frame = targetPillFrame;
                self.bounds = targetBounds;
            }
        } else {
            _extraInfoContainer.frame = targetExtraFrame;
            _pillContainerView.frame = targetPillFrame;
            self.bounds = targetBounds;
        }

        if (p_badgeStyle == 0) { // Capsule Kính Mờ
            _blurEffectView.hidden = NO;
            _pillContainerView.layer.cornerRadius = 11.0;
            _pillContainerView.layer.borderWidth = 0.5;
            UIColor *bCol = (p_colorMode == 9) ?
                [UIColor colorWithRed:p_customGaugeR green:p_customGaugeG blue:p_customGaugeB alpha:p_customBorderAlpha] :
                (isDark ? [UIColor colorWithWhite:0.0 alpha:0.18] : [UIColor colorWithWhite:1.0 alpha:0.20]);

            // Chế độ OLED Pure Black khi bật Tiết kiệm pin hoặc pin yếu
            if (p_oledBlackMode && (lowPower || pct <= 20)) {
                _pillContainerView.layer.borderColor = (lowPower ? [UIColor colorWithRed:1.0 green:0.80 blue:0.0 alpha:0.35] : [UIColor colorWithRed:1.0 green:0.25 blue:0.25 alpha:0.35]).CGColor;
                _pillContainerView.backgroundColor = [UIColor blackColor];
            } else {
                _pillContainerView.layer.borderColor = bCol.CGColor;
                _pillContainerView.backgroundColor = isDark ? [UIColor colorWithWhite:0.9 alpha:0.25] : [UIColor colorWithWhite:0.08 alpha:0.38];
            }
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
            CGFloat offX = 0.0;
            CGFloat offY = 0.0;
            if (self.isControlCenter) {
                offX = p_ccOffsetX;
                offY = p_ccOffsetY;
            } else if (p_separateAppPosition && isAppOrLockScreen(self)) {
                offX = p_appOffsetX;
                offY = p_appOffsetY;
            } else {
                offX = p_offsetX;
                offY = p_offsetY;
            }
            CGFloat totalW = _pillContainerView.frame.size.width;
            if (totalW < 22.0) totalW = 22.0;
            CGPoint targetCenter = CGPointMake(self.anchorCenter.x + offX + (totalW - 22.0) / 2.0, self.anchorCenter.y + offY);
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

    // Bộ lọc chống giật: Bỏ qua khi view chưa vào window hoặc đang trong frame chuyển cảnh bất thường
    if (!stockBattery.window || stockBattery.bounds.size.width < 10.0 || stockBattery.bounds.size.height < 5.0) {
        return;
    }

    CGRect rectInContainer = [stockBattery convertRect:stockBattery.bounds toView:container];
    CGFloat containerW = container.bounds.size.width;

    // Battery view trong thanh trạng thái luôn nằm ở nửa phải màn hình (x > containerW * 0.40) và y ở đỉnh
    if (containerW > 50.0 && (rectInContainer.origin.x < containerW * 0.40 || rectInContainer.origin.y > 80.0 || rectInContainer.origin.y < -20.0)) {
        return;
    }

    // Trích xuất dữ liệu thật từ STUIStatusBar / _UIStatusBar
    UIView *hostBar = container;
    while (hostBar && ![hostBar isKindOfClass:[UIWindow class]]) {
        if ([hostBar respondsToSelector:@selector(currentData)] || [hostBar respondsToSelector:@selector(currentAggregatedData)]) {
            break;
        }
        hostBar = hostBar.superview;
    }
    if (hostBar) {
        updateLiveDataFromStatusBar(hostBar, nil);
    }

    // Tự động nhận diện màu chữ/màu icon thanh trạng thái hệ thống (STUIStatusBar foregroundColor / SignalView activeColor)
    UIColor *extracted = nil;
    if ([container respondsToSelector:@selector(foregroundColor)]) {
        @try { extracted = [container valueForKey:@"foregroundColor"]; } @catch (__unused id e) {}
    }
    if (!extracted) {
        for (UIView *sub in container.subviews) {
            NSString *cn = NSStringFromClass([sub class]);
            if ([cn containsString:@"SignalView"]) {
                @try { UIColor *c = [sub valueForKey:@"activeColor"]; if (c) { extracted = c; break; } } @catch (__unused id e) {}
            }
            if ([sub isKindOfClass:[UILabel class]] && [cn containsString:@"String"]) {
                extracted = ((UILabel *)sub).textColor;
                if (extracted) break;
            }
        }
    }
    if (extracted) {
        custom.adaptiveTintColor = extracted;
    }

    CGPoint centerInContainer = CGPointMake(CGRectGetMidX(rectInContainer), CGRectGetMidY(rectInContainer));
    if (centerInContainer.x > 0 && centerInContainer.y > 0) {
        custom.anchorCenter = centerInContainer;
    }

    // Cập nhật tỷ lệ phóng to (Scale) ngay tức thì theo đúng ngữ cảnh hiện tại
    CGFloat targetScale = 1.0;
    if (isCC) {
        targetScale = p_ccIconScale;
    } else if (p_separateAppPosition && isAppOrLockScreen(custom)) {
        targetScale = p_appIconScale;
    } else {
        targetScale = p_iconScale;
    }
    if (targetScale < 0.2) targetScale = 1.0;
    CGAffineTransform targetTransform = CGAffineTransformMakeScale(targetScale, targetScale);
    if (!CGAffineTransformEqualToTransform(custom.transform, targetTransform)) {
        custom.transform = targetTransform;
    }

    if (p_dragModeEnabled) {
        if (custom.center.x <= 11.0 && custom.center.y <= 11.0 && custom.anchorCenter.x > 0) {
            CGFloat offX = isCC ? p_ccOffsetX : ((p_separateAppPosition && isAppOrLockScreen(custom)) ? p_appOffsetX : p_offsetX);
            CGFloat offY = isCC ? p_ccOffsetY : ((p_separateAppPosition && isAppOrLockScreen(custom)) ? p_appOffsetY : p_offsetY);
            CGFloat totalW = custom.pillContainerView.frame.size.width;
            if (totalW < 22.0) totalW = 22.0;
            custom.center = CGPointMake(custom.anchorCenter.x + offX + (totalW - 22.0) / 2.0, custom.anchorCenter.y + offY);
        }
        return;
    }

    if (custom.dragPanGesture && (custom.dragPanGesture.state == UIGestureRecognizerStateBegan || custom.dragPanGesture.state == UIGestureRecognizerStateChanged)) {
        return;
    }

    CGFloat offX = 0.0;
    CGFloat offY = 0.0;
    if (isCC) {
        offX = p_ccOffsetX;
        offY = p_ccOffsetY;
    } else if (p_separateAppPosition && isAppOrLockScreen(custom)) {
        offX = p_appOffsetX;
        offY = p_appOffsetY;
    } else {
        offX = p_offsetX;
        offY = p_offsetY;
    }
    CGFloat totalW = custom.pillContainerView.frame.size.width;
    if (totalW < 22.0) totalW = 22.0;

    CGPoint targetCenter = CGPointMake(custom.anchorCenter.x + offX + (totalW - 22.0) / 2.0, custom.anchorCenter.y + offY);
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

static void (*orig_uistatusbar_layoutSubviews)(UIView *, SEL) = NULL;
static void hooked_uistatusbar_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_uistatusbar_layoutSubviews) {
        orig_uistatusbar_layoutSubviews(self, _cmd);
    }
    updateLiveDataFromStatusBar(self, nil);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_activeStatusView) [g_activeStatusView updateStats];
        if (g_activeCCStatusView) [g_activeCCStatusView updateStats];
    });
}

static void (*orig_uistatusbar_updateWithData)(UIView *, SEL, id) = NULL;
static void hooked_uistatusbar_updateWithData(UIView *self, SEL _cmd, id data) {
    if (orig_uistatusbar_updateWithData) {
        orig_uistatusbar_updateWithData(self, _cmd, data);
    }
    updateLiveDataFromStatusBar(self, data);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_activeStatusView) [g_activeStatusView updateStats];
        if (g_activeCCStatusView) [g_activeCCStatusView updateStats];
    });
}

static void handleSystemStateChangeNotification(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_activeStatusView) {
            updateLiveDataFromStatusBar(g_activeStatusView.superview, nil);
            [g_activeStatusView updateStats];
        }
        if (g_activeCCStatusView) {
            updateLiveDataFromStatusBar(g_activeCCStatusView.superview, nil);
            [g_activeCCStatusView updateStats];
        }
    });
}

static void handleSystemStateDarwinCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    handleSystemStateChangeNotification();
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
            g_activeStatusView.showRAM = p_showRAM;
            [g_activeStatusView rebuildCellularDots];
            [g_activeStatusView applyPreferences];
            [g_activeStatusView updateStats];
            if (!p_dragModeEnabled && g_activeStatusView.anchorCenter.x > 0) {
                CGFloat offX = (p_separateAppPosition && isAppOrLockScreen(g_activeStatusView)) ? p_appOffsetX : p_offsetX;
                CGFloat offY = (p_separateAppPosition && isAppOrLockScreen(g_activeStatusView)) ? p_appOffsetY : p_offsetY;
                CGFloat totalW = g_activeStatusView.pillContainerView.frame.size.width;
                if (totalW < 22.0) totalW = 22.0;
                g_activeStatusView.center = CGPointMake(g_activeStatusView.anchorCenter.x + offX + (totalW - 22.0) / 2.0, g_activeStatusView.anchorCenter.y + offY);
            }
        }
        if (g_activeCCStatusView) {
            g_activeCCStatusView.showRAM = p_showRAM;
            [g_activeCCStatusView rebuildCellularDots];
            [g_activeCCStatusView applyPreferences];
            [g_activeCCStatusView updateStats];
            if (!p_dragModeEnabled && g_activeCCStatusView.anchorCenter.x > 0) {
                CGFloat totalW = g_activeCCStatusView.pillContainerView.frame.size.width;
                if (totalW < 22.0) totalW = 22.0;
                g_activeCCStatusView.center = CGPointMake(g_activeCCStatusView.anchorCenter.x + p_ccOffsetX + (totalW - 22.0) / 2.0, g_activeCCStatusView.anchorCenter.y + p_ccOffsetY);
            }
        }
    });
}

// MARK: - Hit-Testing Hooks for Status Bar and Window (Drag-and-Drop)
static UIView *(*orig_uistatusbar_hitTest)(UIView *, SEL, CGPoint, UIEvent *) = NULL;
static UIView *hooked_uistatusbar_hitTest(UIView *self, SEL _cmd, CGPoint point, UIEvent *event) {
    if (p_enabled) {
        CompactStatusView *custom = (CompactStatusView *)[self viewWithTag:998811];
        if (custom && !custom.hidden && custom.alpha > 0.05 && custom.userInteractionEnabled) {
            CGPoint ptInCustom = [self convertPoint:point toView:custom];
            if ([custom pointInside:ptInCustom withEvent:event]) {
                return custom;
            }
        }
    }
    return orig_uistatusbar_hitTest ? orig_uistatusbar_hitTest(self, _cmd, point, event) : [self hitTest:point withEvent:event];
}

static BOOL (*orig_uistatusbar_pointInside)(UIView *, SEL, CGPoint, UIEvent *) = NULL;
static BOOL hooked_uistatusbar_pointInside(UIView *self, SEL _cmd, CGPoint point, UIEvent *event) {
    if (p_enabled) {
        CompactStatusView *custom = (CompactStatusView *)[self viewWithTag:998811];
        if (custom && !custom.hidden && custom.alpha > 0.05 && custom.userInteractionEnabled) {
            CGPoint ptInCustom = [self convertPoint:point toView:custom];
            if ([custom pointInside:ptInCustom withEvent:event]) {
                return YES;
            }
        }
    }
    return orig_uistatusbar_pointInside ? orig_uistatusbar_pointInside(self, _cmd, point, event) : [self pointInside:point withEvent:event];
}

static UIView *(*orig_uiwindow_hitTest)(UIWindow *, SEL, CGPoint, UIEvent *) = NULL;
static UIView *hooked_uiwindow_hitTest(UIWindow *self, SEL _cmd, CGPoint point, UIEvent *event) {
    if (p_enabled) {
        CompactStatusView *custom = (self == g_activeCCStatusView.window) ? g_activeCCStatusView :
                                    ((self == g_activeStatusView.window) ? g_activeStatusView : nil);
        if (!custom) {
            UIView *tagView = [self viewWithTag:998811];
            if ([tagView isKindOfClass:[CompactStatusView class]]) {
                custom = (CompactStatusView *)tagView;
            }
        }
        if (custom && !custom.hidden && custom.alpha > 0.05 && custom.userInteractionEnabled) {
            CGPoint ptInCustom = [self convertPoint:point toView:custom];
            if ([custom pointInside:ptInCustom withEvent:event]) {
                return custom;
            }
        }
    }
    return orig_uiwindow_hitTest ? orig_uiwindow_hitTest(self, _cmd, point, event) : [self hitTest:point withEvent:event];
}

static BOOL (*orig_uiwindow_pointInside)(UIWindow *, SEL, CGPoint, UIEvent *) = NULL;
static BOOL hooked_uiwindow_pointInside(UIWindow *self, SEL _cmd, CGPoint point, UIEvent *event) {
    if (p_enabled) {
        CompactStatusView *custom = (self == g_activeCCStatusView.window) ? g_activeCCStatusView :
                                    ((self == g_activeStatusView.window) ? g_activeStatusView : nil);
        if (!custom) {
            UIView *tagView = [self viewWithTag:998811];
            if ([tagView isKindOfClass:[CompactStatusView class]]) {
                custom = (CompactStatusView *)tagView;
            }
        }
        if (custom && !custom.hidden && custom.alpha > 0.05 && custom.userInteractionEnabled) {
            CGPoint ptInCustom = [self convertPoint:point toView:custom];
            if ([custom pointInside:ptInCustom withEvent:event]) {
                return YES;
            }
        }
    }
    return orig_uiwindow_pointInside ? orig_uiwindow_pointInside(self, _cmd, point, event) : [self pointInside:point withEvent:event];
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

    // Đăng ký Darwin notifications cho mọi thay đổi sóng, mạng, máy bay, SIM
    NSArray *darwinStateNotifs = @[
        @"com.apple.radios.airplaneModeChanged",
        @"com.apple.radios.airplane-mode.changed",
        @"kCTAirplaneModeDidChangeNotification",
        @"kCTSIMSupportSIMStatusChangeNotification",
        @"com.apple.telephony.simstatus",
        @"com.apple.wifi.manager.powerStateChanged",
        @"com.apple.wifi.linkChanged",
        @"com.apple.springboard.networkStateChanged",
        @"com.apple.springboard.statusBarStateChanged"
    ];
    for (NSString *dn in darwinStateNotifs) {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)handleSystemStateDarwinCallback,
            (__bridge CFStringRef)dn,
            NULL,
            CFNotificationSuspensionBehaviorCoalesce
        );
    }

    // Đăng ký theo dõi Pin hệ thống với 0 độ trễ (UIDevice battery notifications)
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:UIDeviceBatteryLevelDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
        if (g_activeStatusView) [g_activeStatusView updateStats];
        if (g_activeCCStatusView) [g_activeCCStatusView updateStats];
    }];
    [nc addObserverForName:UIDeviceBatteryStateDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
        if (g_activeStatusView) [g_activeStatusView updateStats];
        if (g_activeCCStatusView) [g_activeCCStatusView updateStats];
    }];

    // Đăng ký SpringBoard NSNotificationCenter cho cập nhật trực tiếp tức thì 0 độ trễ
    NSArray *sbNotifs = @[
        @"SBWiFiManagerLinkDidChangeNotification",
        @"SBWiFiManagerPowerStateDidChangeNotification",
        @"SBTelephonyManagerRegistrationStateChangedNotification",
        @"SBTelephonyManagerDataStatusNotification",
        @"SBTelephonyManagerCarrierBundleChangedNotification",
        @"SBTelephonyManagerAirplaneModeDidChangeNotification",
        @"SBAirplaneModeControllerAirplaneModeDidChangeNotification",
        @"UIApplicationSignificantTimeChangeNotification"
    ];
    for (NSString *sbn in sbNotifs) {
        [nc addObserverForName:sbn object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
            handleSystemStateChangeNotification();
        }];
    }

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

    // 6. Hook Status Bar & Status Bar Window for touch hit-testing and real-time live data sync
    Class sbViewClass = objc_getClass("_UIStatusBar");
    if (sbViewClass) {
        SafeSwizzle(sbViewClass, @selector(hitTest:withEvent:), (IMP)hooked_uistatusbar_hitTest, (IMP *)&orig_uistatusbar_hitTest);
        SafeSwizzle(sbViewClass, @selector(pointInside:withEvent:), (IMP)hooked_uistatusbar_pointInside, (IMP *)&orig_uistatusbar_pointInside);
        SafeSwizzle(sbViewClass, @selector(layoutSubviews), (IMP)hooked_uistatusbar_layoutSubviews, (IMP *)&orig_uistatusbar_layoutSubviews);
        if (class_getInstanceMethod(sbViewClass, @selector(updateWithData:))) {
            SafeSwizzle(sbViewClass, @selector(updateWithData:), (IMP)hooked_uistatusbar_updateWithData, (IMP *)&orig_uistatusbar_updateWithData);
        }
    }

    NSArray *winClasses = @[@"UIWindow", @"UIStatusBarWindow", @"_UIStatusBarWindow", @"SBStatusBarWindow"];
    for (NSString *name in winClasses) {
        Class wc = objc_getClass([name UTF8String]);
        if (wc) {
            SafeSwizzle(wc, @selector(hitTest:withEvent:), (IMP)hooked_uiwindow_hitTest, (IMP *)&orig_uiwindow_hitTest);
            SafeSwizzle(wc, @selector(pointInside:withEvent:), (IMP)hooked_uiwindow_pointInside, (IMP *)&orig_uiwindow_pointInside);
        }
    }

}

