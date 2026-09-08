#!/usr/bin/env python3
"""Generate MyVPN.xcodeproj for the menu bar app."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJ = ROOT / "MyVPN.xcodeproj"
PROJ.mkdir(parents=True, exist_ok=True)

# Keep IDs stable for existing files; append new ones for product UX sources.
I = {
    "project": "A10000000000000000000001",
    "target": "A10000000000000000000002",
    "sources": "A10000000000000000000003",
    "resources": "A10000000000000000000004",
    "frameworks": "A10000000000000000000005",
    "product": "A10000000000000000000006",
    "group_root": "A10000000000000000000010",
    "group_src": "A10000000000000000000011",
    "group_products": "A10000000000000000000012",
    "ref_app": "A10000000000000000000020",
    "ref_cli": "A10000000000000000000021",
    "ref_status": "A10000000000000000000022",
    "ref_info": "A10000000000000000000023",
    "ref_main": "A10000000000000000000027",
    "ref_assets": "A10000000000000000000028",
    "ref_helper": "A1000000000000000000002B",
    "ref_runtime": "A1000000000000000000002C",
    "ref_login": "A1000000000000000000002D",
    "ref_rules": "A10000000000000000000060",
    "ref_sticky": "A10000000000000000000061",
    "ref_doctor": "A10000000000000000000062",
    "ref_drop": "A10000000000000000000063",
    "ref_settings": "A10000000000000000000064",
    "ref_wgstore": "A10000000000000000000065",
    "ref_conn": "A10000000000000000000066",
    "ref_help": "A10000000000000000000067",
    "ref_update": "A10000000000000000000068",
    "ref_hotkeys": "A10000000000000000000069",
    "ref_autodoctor": "A1000000000000000000006A",
    "bf_app": "A10000000000000000000024",
    "bf_cli": "A10000000000000000000025",
    "bf_status": "A10000000000000000000026",
    "bf_main": "A10000000000000000000029",
    "bf_assets": "A1000000000000000000002A",
    "bf_helper": "A1000000000000000000002E",
    "bf_runtime": "A1000000000000000000002F",
    "bf_login": "A10000000000000000000050",
    "bf_rules": "A10000000000000000000051",
    "bf_sticky": "A10000000000000000000052",
    "bf_doctor": "A10000000000000000000053",
    "bf_drop": "A10000000000000000000054",
    "bf_settings": "A10000000000000000000055",
    "bf_wgstore": "A10000000000000000000056",
    "bf_conn": "A10000000000000000000057",
    "bf_help": "A10000000000000000000058",
    "bf_update": "A10000000000000000000059",
    "bf_hotkeys": "A1000000000000000000005A",
    "bf_autodoctor": "A1000000000000000000005B",
    "build_proj_debug": "A10000000000000000000030",
    "build_proj_release": "A10000000000000000000031",
    "build_tgt_debug": "A10000000000000000000032",
    "build_tgt_release": "A10000000000000000000033",
    "config_list_proj": "A10000000000000000000040",
    "config_list_tgt": "A10000000000000000000041",
}

pbx = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
		{I['bf_app']} /* AppDelegate.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['ref_app']} /* AppDelegate.swift */; }};
		{I['bf_cli']} /* MyVPNCLI.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['ref_cli']} /* MyVPNCLI.swift */; }};
		{I['bf_status']} /* StatusSnapshot.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['ref_status']} /* StatusSnapshot.swift */; }};
		{I['bf_main']} /* main.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['ref_main']} /* main.swift */; }};
		{I['bf_helper']} /* MyVPNHelper.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['ref_helper']} /* MyVPNHelper.swift */; }};
		{I['bf_runtime']} /* RuntimePaths.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['ref_runtime']} /* RuntimePaths.swift */; }};
		{I['bf_login']} /* LoginItemController.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['ref_login']} /* LoginItemController.swift */; }};
		{I['bf_rules']} /* RulesStatus.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['ref_rules']} /* RulesStatus.swift */; }};
		{I['bf_sticky']} /* StickyMenuItemView.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['ref_sticky']} /* StickyMenuItemView.swift */; }};
		{I['bf_doctor']} /* DoctorStatus.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['ref_doctor']} /* DoctorStatus.swift */; }};
		{I['bf_drop']} /* DropLogger.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['ref_drop']} /* DropLogger.swift */; }};
		{I['bf_settings']} /* AppSettings.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['ref_settings']} /* AppSettings.swift */; }};
		{I['bf_wgstore']} /* WireGuardProfileStore.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['ref_wgstore']} /* WireGuardProfileStore.swift */; }};
		{I['bf_conn']} /* ConnectionSettingsWindowController.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['ref_conn']} /* ConnectionSettingsWindowController.swift */; }};
		{I['bf_help']} /* HelpWindowController.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['ref_help']} /* HelpWindowController.swift */; }};
		{I['bf_update']} /* UpdateChecker.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['ref_update']} /* UpdateChecker.swift */; }};
		{I['bf_hotkeys']} /* GlobalHotkeys.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['ref_hotkeys']} /* GlobalHotkeys.swift */; }};
		{I['bf_autodoctor']} /* AutoDoctor.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['ref_autodoctor']} /* AutoDoctor.swift */; }};
		{I['bf_assets']} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {I['ref_assets']} /* Assets.xcassets */; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		{I['product']} /* myVPN.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = myVPN.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['ref_app']} /* AppDelegate.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppDelegate.swift; sourceTree = "<group>"; }};
		{I['ref_cli']} /* MyVPNCLI.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MyVPNCLI.swift; sourceTree = "<group>"; }};
		{I['ref_status']} /* StatusSnapshot.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = StatusSnapshot.swift; sourceTree = "<group>"; }};
		{I['ref_main']} /* main.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = main.swift; sourceTree = "<group>"; }};
		{I['ref_helper']} /* MyVPNHelper.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MyVPNHelper.swift; sourceTree = "<group>"; }};
		{I['ref_runtime']} /* RuntimePaths.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RuntimePaths.swift; sourceTree = "<group>"; }};
		{I['ref_login']} /* LoginItemController.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LoginItemController.swift; sourceTree = "<group>"; }};
		{I['ref_rules']} /* RulesStatus.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RulesStatus.swift; sourceTree = "<group>"; }};
		{I['ref_sticky']} /* StickyMenuItemView.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = StickyMenuItemView.swift; sourceTree = "<group>"; }};
		{I['ref_doctor']} /* DoctorStatus.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DoctorStatus.swift; sourceTree = "<group>"; }};
		{I['ref_drop']} /* DropLogger.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DropLogger.swift; sourceTree = "<group>"; }};
		{I['ref_settings']} /* AppSettings.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppSettings.swift; sourceTree = "<group>"; }};
		{I['ref_wgstore']} /* WireGuardProfileStore.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WireGuardProfileStore.swift; sourceTree = "<group>"; }};
		{I['ref_conn']} /* ConnectionSettingsWindowController.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ConnectionSettingsWindowController.swift; sourceTree = "<group>"; }};
		{I['ref_help']} /* HelpWindowController.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HelpWindowController.swift; sourceTree = "<group>"; }};
		{I['ref_update']} /* UpdateChecker.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UpdateChecker.swift; sourceTree = "<group>"; }};
		{I['ref_hotkeys']} /* GlobalHotkeys.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GlobalHotkeys.swift; sourceTree = "<group>"; }};
		{I['ref_autodoctor']} /* AutoDoctor.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AutoDoctor.swift; sourceTree = "<group>"; }};
		{I['ref_info']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
		{I['ref_assets']} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{I['frameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{I['group_root']} = {{
			isa = PBXGroup;
			children = (
				{I['group_src']} /* MyVPN */,
				{I['group_products']} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{I['group_src']} /* MyVPN */ = {{
			isa = PBXGroup;
			children = (
				{I['ref_main']} /* main.swift */,
				{I['ref_app']} /* AppDelegate.swift */,
				{I['ref_cli']} /* MyVPNCLI.swift */,
				{I['ref_helper']} /* MyVPNHelper.swift */,
				{I['ref_runtime']} /* RuntimePaths.swift */,
				{I['ref_login']} /* LoginItemController.swift */,
				{I['ref_status']} /* StatusSnapshot.swift */,
				{I['ref_rules']} /* RulesStatus.swift */,
				{I['ref_doctor']} /* DoctorStatus.swift */,
				{I['ref_drop']} /* DropLogger.swift */,
				{I['ref_settings']} /* AppSettings.swift */,
				{I['ref_wgstore']} /* WireGuardProfileStore.swift */,
				{I['ref_conn']} /* ConnectionSettingsWindowController.swift */,
				{I['ref_help']} /* HelpWindowController.swift */,
				{I['ref_update']} /* UpdateChecker.swift */,
				{I['ref_hotkeys']} /* GlobalHotkeys.swift */,
				{I['ref_autodoctor']} /* AutoDoctor.swift */,
				{I['ref_sticky']} /* StickyMenuItemView.swift */,
				{I['ref_assets']} /* Assets.xcassets */,
				{I['ref_info']} /* Info.plist */,
			);
			path = MyVPN;
			sourceTree = "<group>";
		}};
		{I['group_products']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{I['product']} /* myVPN.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{I['target']} /* myVPN */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['config_list_tgt']} /* Build configuration list for PBXNativeTarget "myVPN" */;
			buildPhases = (
				{I['sources']} /* Sources */,
				{I['frameworks']} /* Frameworks */,
				{I['resources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = myVPN;
			productName = myVPN;
			productReference = {I['product']} /* myVPN.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{I['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
			}};
			buildConfigurationList = {I['config_list_proj']} /* Build configuration list for PBXProject "MyVPN" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
				ru,
			);
			mainGroup = {I['group_root']};
			productRefGroup = {I['group_products']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{I['target']} /* myVPN */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{I['resources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{I['bf_assets']} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{I['sources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{I['bf_main']} /* main.swift in Sources */,
				{I['bf_app']} /* AppDelegate.swift in Sources */,
				{I['bf_cli']} /* MyVPNCLI.swift in Sources */,
				{I['bf_helper']} /* MyVPNHelper.swift in Sources */,
				{I['bf_runtime']} /* RuntimePaths.swift in Sources */,
				{I['bf_login']} /* LoginItemController.swift in Sources */,
				{I['bf_status']} /* StatusSnapshot.swift in Sources */,
				{I['bf_rules']} /* RulesStatus.swift in Sources */,
				{I['bf_doctor']} /* DoctorStatus.swift in Sources */,
				{I['bf_drop']} /* DropLogger.swift in Sources */,
				{I['bf_settings']} /* AppSettings.swift in Sources */,
				{I['bf_wgstore']} /* WireGuardProfileStore.swift in Sources */,
				{I['bf_conn']} /* ConnectionSettingsWindowController.swift in Sources */,
				{I['bf_help']} /* HelpWindowController.swift in Sources */,
				{I['bf_update']} /* UpdateChecker.swift in Sources */,
				{I['bf_hotkeys']} /* GlobalHotkeys.swift in Sources */,
				{I['bf_autodoctor']} /* AutoDoctor.swift in Sources */,
				{I['bf_sticky']} /* StickyMenuItemView.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{I['build_proj_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				GCC_DYNAMIC_NO_PIC = NO;
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			}};
			name = Debug;
		}};
		{I['build_proj_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
			}};
			name = Release;
		}};
		{I['build_tgt_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = MyVPN/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = local.myvpn.mac;
				PRODUCT_NAME = myVPN;
				SWIFT_VERSION = 5.0;
			}};
			name = Debug;
		}};
		{I['build_tgt_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = MyVPN/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = local.myvpn.mac;
				PRODUCT_NAME = myVPN;
				SWIFT_VERSION = 5.0;
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{I['config_list_proj']} /* Build configuration list for PBXProject "MyVPN" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['build_proj_debug']} /* Debug */,
				{I['build_proj_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{I['config_list_tgt']} /* Build configuration list for PBXNativeTarget "myVPN" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['build_tgt_debug']} /* Debug */,
				{I['build_tgt_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {I['project']} /* Project object */;
}}
"""

(PROJ / "project.pbxproj").write_text(pbx)
print(f"wrote {PROJ / 'project.pbxproj'}")
