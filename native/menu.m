#import <AppKit/AppKit.h>
#include <dlfcn.h>

@interface AshuiMenuTarget : NSObject
@property NSMutableArray<NSNumber *> *actions;
- (void)invoke:(NSMenuItem *)sender;
@end
@implementation AshuiMenuTarget
- (void)invoke:(NSMenuItem *)sender {
    [self.actions addObject:@(sender.tag)];
    bool (*wake)(void) = (bool (*)(void))dlsym(RTLD_DEFAULT, "__hl_window_wake");
    if (wake) wake();
}
@end
static AshuiMenuTarget *target;
static NSMenu *previous;

static NSMenu *installed;
static NSMenuItem *quitItem;
static NSString *applicationName;

static void syncMenu(NSMenu *result, NSArray *items, NSUInteger start) {
    result.autoenablesItems = NO;
    NSUInteger index = start;
    for (NSDictionary *item in items) {
        BOOL separator = [item[@"separator"] boolValue];
        NSMenuItem *entry = index < result.numberOfItems ? [result itemAtIndex:index] : nil;
        if (!entry || entry.isSeparatorItem != separator) {
            if (entry) [result removeItemAtIndex:index];
            entry = separator ? NSMenuItem.separatorItem : [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
            [result insertItem:entry atIndex:index];
        }
        index++;
        if (separator) continue;
        NSString *label = item[@"label"] ?: @"";
        if (![entry.title isEqualToString:label]) entry.title = label;
        if (item[@"items"]) {
            if (!entry.submenu) entry.submenu = [[NSMenu alloc] initWithTitle:label];
            entry.target = nil;
            entry.action = NULL;
            syncMenu(entry.submenu, item[@"items"], 0);
            continue;
        }
        entry.submenu = nil;
        entry.target = target;
        entry.action = @selector(invoke:);
        entry.tag = [item[@"id"] integerValue];
        entry.enabled = item[@"enabled"] == nil || [item[@"enabled"] boolValue];
        NSDictionary *key = item[@"key"];
        NSString *equivalent = @"";
        NSEventModifierFlags flags = 0;
        if ([key isKindOfClass:NSDictionary.class]) {
            NSString *name = [key[@"key"] lowercaseString] ?: @"";
            unichar special = 0;
            if ([name hasPrefix:@"f"] && name.length > 1) {
                NSInteger number = [[name substringFromIndex:1] integerValue];
                if (number >= 1 && number <= 20) special = NSF1FunctionKey + number - 1;
            }
            static NSDictionary *named;
            if (!named) named = @{@"up": @(NSUpArrowFunctionKey), @"down": @(NSDownArrowFunctionKey),
                @"left": @(NSLeftArrowFunctionKey), @"right": @(NSRightArrowFunctionKey),
                @"home": @(NSHomeFunctionKey), @"end": @(NSEndFunctionKey),
                @"pageup": @(NSPageUpFunctionKey), @"pagedown": @(NSPageDownFunctionKey),
                @"delete": @(NSDeleteFunctionKey), @"backspace": @127, @"enter": @13, @"tab": @9, @"escape": @27, @"space": @32};
            if (named[name]) special = [named[name] unsignedShortValue];
            equivalent = special ? [NSString stringWithCharacters:&special length:1] : name;
            if ([key[@"meta"] boolValue]) flags |= NSEventModifierFlagCommand;
            if ([key[@"ctrl"] boolValue]) flags |= NSEventModifierFlagControl;
            if ([key[@"alt"] boolValue]) flags |= NSEventModifierFlagOption;
            if ([key[@"shift"] boolValue]) flags |= NSEventModifierFlagShift;
        }
        if (![entry.keyEquivalent isEqualToString:equivalent]) entry.keyEquivalent = equivalent;
        if (entry.keyEquivalentModifierMask != flags) entry.keyEquivalentModifierMask = flags;
    }
    while (result.numberOfItems > index) [result removeItemAtIndex:result.numberOfItems - 1];
}

bool ashui_menu_install(const unsigned char *json) {
    @autoreleasepool {
        if (!json || !NSThread.isMainThread) return false;
        NSData *data = [[NSString stringWithUTF8String:(const char *)json] dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *spec = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![spec isKindOfClass:NSDictionary.class]) return false;
        if (!target) {
            target = [AshuiMenuTarget new];
            target.actions = [NSMutableArray new];
            previous = NSApp.mainMenu;
        }
        NSString *name = spec[@"name"] ?: @"Application";
        if (!installed) {
            installed = [NSMenu new];
            NSMenu *app = [NSMenu new];
            [app addItemWithTitle:@"" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
            [app addItem:NSMenuItem.separatorItem];
            [app addItemWithTitle:@"" action:@selector(hide:) keyEquivalent:@"h"];
            NSMenuItem *others = [app addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
            others.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
            [app addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
            [app addItem:NSMenuItem.separatorItem];
            quitItem = [app addItemWithTitle:@"" action:@selector(invoke:) keyEquivalent:@"q"];
            quitItem.target = target;
            NSMenuItem *heading = [installed addItemWithTitle:name action:NULL keyEquivalent:@""];
            heading.submenu = app;
        }
        if (![applicationName isEqualToString:name]) {
            applicationName = name;
            NSMenuItem *heading = [installed itemAtIndex:0];
            heading.title = name;
            [heading.submenu itemAtIndex:0].title = [@"About " stringByAppendingString:name];
            [heading.submenu itemAtIndex:2].title = [@"Hide " stringByAppendingString:name];
            quitItem.title = [@"Quit " stringByAppendingString:name];
        }
        quitItem.tag = [spec[@"quit"] integerValue];
        syncMenu(installed, spec[@"menus"], 1);
        if (NSApp.mainMenu != installed) NSApp.mainMenu = installed;
        return true;
    }
}
int ashui_menu_poll(void) {
    if (!target.actions.count) return 0;
    int action = target.actions.firstObject.intValue;
    [target.actions removeObjectAtIndex:0];
    return action;
}
void ashui_menu_clear(void) {
    if (target) NSApp.mainMenu = previous;
    previous = nil;
    target = nil;
    installed = nil;
    quitItem = nil;
    applicationName = nil;
}

static NSMutableDictionary<NSNumber *, NSOpenPanel *> *dialogs;
static NSMutableDictionary<NSNumber *, NSString *> *dialogResults;
static NSString *lastDialogResult;

static void wakeDialog(void) {
    bool (*wake)(void) = (bool (*)(void))dlsym(RTLD_DEFAULT, "__hl_window_wake");
    if (wake) wake();
}
bool ashui_dialog_open(const unsigned char *json) {
    if (!json || !NSThread.isMainThread) return false;
    NSData *data = [[NSString stringWithUTF8String:(const char *)json] dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *spec = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![spec isKindOfClass:NSDictionary.class]) return false;
    NSView *view = (__bridge NSView *)(void *)(uintptr_t)[spec[@"view"] longLongValue];
    NSWindow *window = view.window;
    if (!window || window.attachedSheet) return false;
    if (!dialogs) { dialogs = [NSMutableDictionary new]; dialogResults = [NSMutableDictionary new]; }
    NSNumber *identifier = spec[@"id"];
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    BOOL folder = [spec[@"folder"] boolValue];
    panel.canChooseDirectories = folder;
    panel.canChooseFiles = !folder;
    panel.canCreateDirectories = folder;
    panel.allowsMultipleSelection = NO;
    panel.resolvesAliases = YES;
    panel.title = spec[@"title"] ?: @"Open";
    panel.message = panel.title;
    NSString *directory = spec[@"directory"];
    if ([directory isKindOfClass:NSString.class] && directory.length) panel.directoryURL = [NSURL fileURLWithPath:directory isDirectory:YES];
    NSArray *extensions = spec[@"extensions"];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (!folder && [extensions isKindOfClass:NSArray.class] && extensions.count) panel.allowedFileTypes = extensions;
#pragma clang diagnostic pop
    dialogs[identifier] = panel;
    [window makeKeyAndOrderFront:nil];
    [panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        if (dialogs[identifier]) {
            dialogResults[identifier] = response == NSModalResponseOK ? (panel.URL.path ?: @"") : @"";
            [dialogs removeObjectForKey:identifier];
            wakeDialog();
        }
    }];
    return true;
}
int ashui_dialog_poll(void) { return dialogResults.allKeys.firstObject.intValue; }
const unsigned char *ashui_dialog_take(int identifier) {
    lastDialogResult = dialogResults[@(identifier)];
    [dialogResults removeObjectForKey:@(identifier)];
    return (const unsigned char *)lastDialogResult.UTF8String;
}
void ashui_dialog_cancel(int identifier) {
    NSOpenPanel *panel = dialogs[@(identifier)];
    [dialogs removeObjectForKey:@(identifier)];
    [dialogResults removeObjectForKey:@(identifier)];
    if (panel.sheetParent) [panel.sheetParent endSheet:panel returnCode:NSModalResponseCancel];
    [panel orderOut:nil];
}
