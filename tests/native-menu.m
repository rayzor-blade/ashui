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
        ashui_menu_clear();
        assert(NSApp.mainMenu == previous && ashui_menu_poll() == 0);
        puts("native menu: PASS");
    }
}
