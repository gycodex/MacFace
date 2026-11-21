#import "status_menu.h"
#import "settings_keys.h"
#import <os/log.h>

@interface MacFaceStatusMenu () <NSMenuDelegate>
@end

@implementation MacFaceStatusMenu {
    NSStatusItem *_item;
    NSString *_status;
    NSArray<NSMenuItem *> *_modes;
}

- (instancetype)init {
    if ((self = [super init])) {
        _status = @"正在初始化…";
        _item = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
        _item.button.image = [NSImage imageWithSystemSymbolName:@"person.crop.circle.badge.checkmark"
                                      accessibilityDescription:@"MacFace"];
        [_item.button.image setTemplate:YES];
        _item.button.toolTip = @"MacFace";

        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"MacFace"];
        menu.delegate = self;
        menu.autoenablesItems = NO;

        NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:@"打开 MacFace 设置…"
                                                        action:@selector(openSettings:)
                                                 keyEquivalent:@""];
        settings.target = self;
        [menu addItem:settings];

        NSMenuItem *status = [[NSMenuItem alloc] initWithTitle:_status action:nil keyEquivalent:@""];
        status.enabled = NO;
        status.tag = 1;
        [menu addItem:status];
        [menu addItem:[NSMenuItem separatorItem]];

        NSMutableArray<NSMenuItem *> *modes = [NSMutableArray array];
        NSArray<NSString *> *titles = @[@"看一眼", @"仅用密码"];
        NSArray<NSString *> *values = @[MacFaceModeGlance, MacFaceModePassword];
        for (NSUInteger index = 0; index < titles.count; ++index) {
            NSMenuItem *mode = [[NSMenuItem alloc] initWithTitle:titles[index]
                                                        action:@selector(selectMode:)
                                                 keyEquivalent:@""];
            mode.target = self;
            mode.representedObject = values[index];
            [modes addObject:mode];
            [menu addItem:mode];
        }
        _modes = [modes copy];
        _item.menu = menu;
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self
            selector:@selector(refreshVisibility:) name:MacFaceMenuBarIconChanged object:nil];
        [self refreshVisibility:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
}

- (void)refreshVisibility:(NSNotification *)notification {
    (void)notification;
    CFPreferencesAppSynchronize((__bridge CFStringRef)MacFaceSettingsDomain);
    NSUserDefaults *settings = [[NSUserDefaults alloc] initWithSuiteName:MacFaceSettingsDomain];
    NSNumber *saved = [settings objectForKey:MacFaceMenuBarIconKey];
    BOOL visible = !saved || [saved boolValue];
    if (_item.visible != visible) {
        _item.visible = visible;
        os_log(OS_LOG_DEFAULT, "MacFace: menu bar icon visible=%d", _item.visible);
    }
}

- (void)setStatusMessage:(NSString *)message {
    _status = [message copy];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu itemWithTag:1].title = _status;
    NSString *selection = MacFaceUnlockMode();
    for (NSMenuItem *mode in _modes) {
        mode.state = [selection isEqualToString:mode.representedObject]
            ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void)openSettings:(NSMenuItem *)sender {
    (void)sender;
    NSURL *settings = [NSURL fileURLWithPath:@"/Applications/MacFace.app" isDirectory:YES];
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = YES;
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:settings
                                          configuration:configuration
                                      completionHandler:nil];
}

- (void)selectMode:(NSMenuItem *)sender {
    NSUserDefaults *settings = [[NSUserDefaults alloc] initWithSuiteName:MacFaceSettingsDomain];
    [settings setObject:sender.representedObject forKey:MacFaceModeKey];
}
@end
