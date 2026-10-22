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

static NSMenu *menu(NSString *name, NSArray *items) {
    NSMenu *result = [[NSMenu alloc] initWithTitle:name];
    result.autoenablesItems = NO;
    for (NSDictionary *item in items) {
        if ([item[@"separator"] boolValue]) { [result addItem:NSMenuItem.separatorItem]; continue; }
        NSString *label = item[@"label"] ?: @"";
        NSMenuItem *entry = [[NSMenuItem alloc] initWithTitle:label action:NULL keyEquivalent:@""];
        if (item[@"items"]) {
            entry.submenu = menu(label, item[@"items"]);
        } else {
            entry.target = target;
            entry.action = @selector(invoke:);
            entry.tag = [item[@"id"] integerValue];
            entry.enabled = item[@"enabled"] == nil || [item[@"enabled"] boolValue];
            NSDictionary *key = item[@"key"];
            if ([key isKindOfClass:NSDictionary.class]) {
                NSString *name = [key[@"key"] lowercaseString] ?: @"";
                unichar special = 0;
                if ([name hasPrefix:@"f"] && name.length > 1) {
                    NSInteger number = [[name substringFromIndex:1] integerValue];
                    if (number >= 1 && number <= 20) special = NSF1FunctionKey + number - 1;
                }
                NSDictionary *named = @{@"up": @(NSUpArrowFunctionKey), @"down": @(NSDownArrowFunctionKey),
                    @"left": @(NSLeftArrowFunctionKey), @"right": @(NSRightArrowFunctionKey),
                    @"home": @(NSHomeFunctionKey), @"end": @(NSEndFunctionKey),
                    @"pageup": @(NSPageUpFunctionKey), @"pagedown": @(NSPageDownFunctionKey),
                    @"delete": @(NSDeleteFunctionKey), @"backspace": @127, @"enter": @13, @"tab": @9, @"escape": @27, @"space": @32};
                if (named[name]) special = [named[name] unsignedShortValue];
                entry.keyEquivalent = special ? [NSString stringWithCharacters:&special length:1] : name;
                NSEventModifierFlags flags = 0;
                if ([key[@"meta"] boolValue]) flags |= NSEventModifierFlagCommand;
                if ([key[@"ctrl"] boolValue]) flags |= NSEventModifierFlagControl;
                if ([key[@"alt"] boolValue]) flags |= NSEventModifierFlagOption;
                if ([key[@"shift"] boolValue]) flags |= NSEventModifierFlagShift;
                entry.keyEquivalentModifierMask = flags;
            }
        }
        [result addItem:entry];
    }
    return result;
}

bool ashui_menu_install(const unsigned char *json) {
    if (!json || !NSThread.isMainThread) return false;
    NSData *data = [[NSString stringWithUTF8String:(const char *)json] dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *spec = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![spec isKindOfClass:NSDictionary.class]) return false;
    if (!target) {
        target = [AshuiMenuTarget new];
        target.actions = [NSMutableArray new];
        previous = NSApp.mainMenu;
    }
    NSMenu *bar = [NSMenu new];
    NSString *name = spec[@"name"] ?: @"Application";
    NSMenu *app = [NSMenu new];
    [app addItemWithTitle:[@"About " stringByAppendingString:name] action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [app addItem:NSMenuItem.separatorItem];
    [app addItemWithTitle:[@"Hide " stringByAppendingString:name] action:@selector(hide:) keyEquivalent:@"h"];
    NSMenuItem *others = [app addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    others.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [app addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [app addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [app addItemWithTitle:[@"Quit " stringByAppendingString:name] action:@selector(invoke:) keyEquivalent:@"q"];
    quit.target = target; quit.tag = [spec[@"quit"] integerValue];
    NSMenuItem *heading = [bar addItemWithTitle:name action:NULL keyEquivalent:@""];
    heading.submenu = app;
    for (NSDictionary *group in spec[@"menus"]) {
        NSMenuItem *title = [bar addItemWithTitle:group[@"label"] action:NULL keyEquivalent:@""];
        title.submenu = menu(group[@"label"], group[@"items"]);
    }
    NSApp.mainMenu = bar;
    return true;
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
}
