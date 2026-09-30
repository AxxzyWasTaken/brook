// Umbrella header: every source file imports this, so the whole app sees every type.
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <Security/Security.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <CommonCrypto/CommonCrypto.h>
#import <objc/message.h>
#include <sqlite3.h>

#include <algorithm>
#include <cmath>
#include <functional>
#include <optional>
#include <vector>

NS_ASSUME_NONNULL_BEGIN

@class BrowserTab, BrowserState, Space, ArchivedTab, BrookWebView;
@class BrowserWindowController, SidebarView, TopBarView, ContentAreaView, CommandBarController;
@class HistoryEntry, SearchEngine;

NS_ASSUME_NONNULL_END

#import "Utilities.h"
#import "Settings.h"
#import "BrowserTab.h"
#import "BrowserState.h"
#import "SiteSettings.h"
#import "SitePermissions.h"
#import "SiteNotifications.h"
#import "ImageMenu.h"
#import "ElementHider.h"
#import "Stores.h"
#import "WebViewFactory.h"
#import "Autoconsent.h"
#import "ContentBlocker.h"
#import "Fire.h"
#import "PasswordStore.h"
#import "PasswordImporter.h"
#import "PasswordAutofill.h"
#import "ExtensionManager.h"
#import "Controls.h"
#import "SidebarCells.h"
#import "ExtensionsBar.h"
#import "SidebarParts.h"
#import "SidebarView.h"
#import "TopBar.h"
#import "CommandBar.h"
#import "ContentAreaView.h"
#import "SiteInfo.h"
#import "HiddenElements.h"
#import "SpaceEditor.h"
#import "ChromeMorph.h"
#import "BrowserWindowController.h"
#import "SettingsControls.h"
#import "PasswordsPane.h"
#import "SettingsWindow.h"
#import "AppDelegate.h"
