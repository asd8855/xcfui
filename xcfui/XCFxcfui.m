//
//  XCFxcfui.m
//  XCFxcfui
//
//  Created by Josip Ćavar on 18/05/14.
//  Copyright (c) 2014 Josip Cavar. All rights reserved.
//

#import "XCFxcfui.h"
#import <objc/runtime.h>

static NSString * const IDESourceCodeEditorDidFinishSetup = @"IDESourceCodeEditorDidFinishSetup";

static NSBundle *bundle;

@class IDEWorkspaceDocument;

@interface XCFxcfui()

@property (nonatomic, strong) NSMenuItem *menuItemUnusedImports;

@end

@implementation XCFxcfui

#pragma mark - Object lifecycle

+ (void)pluginDidLoad:(NSBundle *)plugin {
    
    static XCFxcfui *sharedPlugin;
    static dispatch_once_t onceToken;
    NSString *currentApplicationName = [[NSBundle mainBundle] infoDictionary][@"CFBundleName"];
    if ([currentApplicationName isEqual:@"Xcode"]) {
        dispatch_once(&onceToken, ^{
            sharedPlugin = [[self alloc] initWithBundle:plugin];
        });
    }
}

- (id)initWithBundle:(NSBundle *)plugin {
    
    if (self = [super init]) {
        bundle = plugin;
        NSMenuItem *menuItemFile = [[NSApp mainMenu] itemWithTitle:@"File"];
        if (menuItemFile) {
            [menuItemFile.submenu addItem:[NSMenuItem separatorItem]];
            self.menuItemUnusedImports = [[NSMenuItem alloc] initWithTitle:@"Find unused imports" action:@selector(menuItemFindUnusedImportsOnClick:) keyEquivalent:@""];
            [self.menuItemUnusedImports setTarget:self];
            [menuItemFile.submenu addItem:self.menuItemUnusedImports];
            
            BOOL findOn = [[NSUserDefaults standardUserDefaults] boolForKey:@"findOn"];
            if (findOn) {
                self.menuItemUnusedImports.state = NSOnState;
            } else {
                self.menuItemUnusedImports.state = NSOffState;
            }
            
            Class workspaceTabController = NSClassFromString(@"IDEWorkspaceTabController");
            Method buildMethod = class_getInstanceMethod(workspaceTabController, NSSelectorFromString(@"buildActiveRunContext:"));
            
            Method buildReplaceMethod = class_getInstanceMethod(workspaceTabController, NSSelectorFromString(@"buildReplaceActiveRunContext:"));
            
            method_exchangeImplementations(buildMethod, buildReplaceMethod);
        }
    }
    return self;
}

- (void)dealloc {

    [[NSNotificationCenter defaultCenter] removeObserver:self name:IDESourceCodeEditorDidFinishSetup object:nil];
}

#pragma mark - Action methods

- (void)menuItemFindUnusedImportsOnClick:(NSMenuItem *)menuItem {
    
    if (menuItem.state == NSOnState) {
        menuItem.state = NSOffState;
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"findOn"];
    } else {
        menuItem.state = NSOnState;
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"findOn"];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (IDEWorkspaceDocument *)currentWorkspaceDocument {
    
    NSWindowController *currentWindowController = [[NSApp mainWindow] windowController];
    NSLog(@"controller %@", [currentWindowController description]);
    id document = [currentWindowController document];
    if (currentWindowController && [document isKindOfClass:NSClassFromString(@"IDEWorkspaceDocument")]) {
        return (IDEWorkspaceDocument *)document;
    }
    return nil;
}

@end

@implementation NSObject (XCFAdditions)

- (void)buildReplaceActiveRunContext:(id)arg {
    
    NSLog(@"tu sam");
    BOOL findOn = [[NSUserDefaults standardUserDefaults] boolForKey:@"findOn"];
    if (findOn) {
        [self turnOnFind];
    } else {
        [self turnOffFind];
    }
    
    // we just added new build phase and we need some time to save project
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self buildReplaceActiveRunContext:arg];
    });
}

- (void)turnOnFind {
    
    NSOperationQueue *backgroundQueue = [[NSOperationQueue alloc] init];
    backgroundQueue.maxConcurrentOperationCount = 1;
    [backgroundQueue addOperationWithBlock:^{
        
        NSString *filePath = [XCFxcfui currentWorkspaceDocument].workspace.representingFilePath.fileURL.path;
        NSString *projectDirectory = [filePath stringByDeletingLastPathComponent];
        // Add build phase
        NSTask *addPhaseTask = [[NSTask alloc] init];
        addPhaseTask.launchPath = @"/usr/bin/ruby";
        NSString *addScriptPath = [bundle pathForResource:@"add_phase" ofType:@"rb"];
        NSString *fuiScriptPath = [bundle pathForResource:@"fui_script" ofType:@"sh"];
        addPhaseTask.arguments = @[addScriptPath, filePath, fuiScriptPath, projectDirectory];
        [addPhaseTask launch];
        [addPhaseTask waitUntilExit];
    }];
}

- (void)turnOffFind {
    
    NSOperationQueue *backgroundQueue = [[NSOperationQueue alloc] init];
    backgroundQueue.maxConcurrentOperationCount = 1;
    [backgroundQueue addOperationWithBlock:^{
        // Remove build phase
        NSString *filePath = [XCFxcfui currentWorkspaceDocument].workspace.representingFilePath.fileURL.path;
        NSString *projectDirectory = [filePath stringByDeletingLastPathComponent];
        NSTask *removePhaseTask = [[NSTask alloc] init];
        removePhaseTask.launchPath = @"/usr/bin/ruby";
        NSString *removeScriptPath = [bundle pathForResource:@"remove_phase" ofType:@"rb"];
        removePhaseTask.arguments = @[removeScriptPath, filePath, projectDirectory];
        [removePhaseTask launch];
        [removePhaseTask waitUntilExit];
    }];
}

@end
