#import <AppKit/AppKit.h>
#include <assert.h>
extern bool ashui_menu_install(const unsigned char *);
extern int ashui_menu_poll(void);
extern void ashui_menu_clear(void);
static int wakes;
bool __hl_window_wake(void) { wakes++; return true; }
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSMenu *previous = NSApp.mainMenu;
        const char *spec = "{\"name\":\"Ashui\",\"quit\":99,\"menus\":[{\"label\":\"File\",\"items\":[{\"label\":\"New Window\",\"id\":42,\"enabled\":true,\"key\":{\"key\":\"n\",\"meta\":true,\"shift\":true}},{\"separator\":true},{\"label\":\"Disabled\",\"id\":43,\"enabled\":false,\"key\":null},{\"label\":\"Run\",\"id\":44,\"key\":{\"key\":\"f5\"}}]}]}";
        assert(ashui_menu_install((const unsigned char *)spec));
        NSMenu *file = [NSApp.mainMenu itemWithTitle:@"File"].submenu;
        assert(file.numberOfItems == 4);
        NSMenuItem *item = [file itemAtIndex:0];
        assert([item.title isEqual:@"New Window"] && [item.keyEquivalent isEqual:@"n"]);
        assert(item.keyEquivalentModifierMask == (NSEventModifierFlagCommand | NSEventModifierFlagShift));
        assert(![file itemAtIndex:2].enabled);
        assert([file itemAtIndex:3].keyEquivalent.length == 1 && [[file itemAtIndex:3].keyEquivalent characterAtIndex:0] == NSF5FunctionKey);
        assert([NSApp sendAction:item.action to:item.target from:item]);
        assert(ashui_menu_poll() == 42 && ashui_menu_poll() == 0 && wakes == 1);
        NSMenu *bar = NSApp.mainMenu;
        for (int i = 0; i < 200; i++) assert(ashui_menu_install((const unsigned char *)spec));
        assert(NSApp.mainMenu == bar && [bar itemWithTitle:@"File"].submenu == file && [file itemAtIndex:0] == item);
        NSMutableDictionary *updated = [NSJSONSerialization JSONObjectWithData:[[NSString stringWithUTF8String:spec] dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:nil];
        NSMutableArray *items = updated[@"menus"][0][@"items"];
        items[0][@"label"] = @"Open Project";
        items[0][@"id"] = @77;
        items[0][@"key"] = @{@"key":@"o", @"ctrl":@YES};
        items[2][@"enabled"] = @YES;
        items[3][@"key"] = NSNull.null;
        [items addObject:@{@"label":@"Recent", @"items":@[@{@"label":@"One", @"id":@78}]}];
        NSData *encoded = [NSJSONSerialization dataWithJSONObject:updated options:0 error:nil];
        NSString *payload = [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
        assert(ashui_menu_install((const unsigned char *)payload.UTF8String));
        assert(NSApp.mainMenu == bar && [file itemAtIndex:0] == item && [item.title isEqual:@"Open Project"]);
        assert(item.tag == 77 && [item.keyEquivalent isEqual:@"o"] && item.keyEquivalentModifierMask == NSEventModifierFlagControl);
        assert([file itemAtIndex:2].enabled && [file itemAtIndex:3].keyEquivalent.length == 0);
        assert(file.numberOfItems == 5 && [file itemAtIndex:4].submenu.numberOfItems == 1);
        assert([NSApp sendAction:item.action to:item.target from:item]);
        assert(ashui_menu_poll() == 77 && ashui_menu_poll() == 0 && wakes == 2);
        assert(ashui_menu_install((const unsigned char *)spec));
        assert(NSApp.mainMenu == bar && file.numberOfItems == 4 && [file itemAtIndex:0] == item);
        ashui_menu_clear();
        assert(NSApp.mainMenu == previous && ashui_menu_poll() == 0);
        puts("native menu: PASS");
    }
}
