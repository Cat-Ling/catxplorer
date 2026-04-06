TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
PACKAGE_FORMAT = ipa

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = CatExplorer

CatExplorer_FILES = main.m CatExplorerAppDelegate.m CatExplorerRootViewController.m
CatExplorer_RESOURCES_DIRS = Resources
CatExplorer_FRAMEWORKS = UIKit CoreGraphics WebKit Network
CatExplorer_CFLAGS = -fobjc-arc -I$(PWD) -Wno-unused-function -Wno-unused-variable -Wno-incompatible-pointer-types -Wno-format -Wno-error=deprecated-declarations

include $(THEOS_MAKE_PATH)/application.mk
