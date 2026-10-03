#!/usr/bin/env python3
"""
Generates a complete, valid Xcode project.pbxproj for SuperHearing.
"""

import hashlib
import os

def gen_id(name: str) -> str:
    h = hashlib.md5(name.encode("utf-8")).hexdigest()[:24].upper()
    return h

def main():
    # Targets & Configs
    proj_id = gen_id("Project_SuperHearing")
    main_group_id = gen_id("Group_Main")
    products_group_id = gen_id("Group_Products")

    # App Target IDs
    app_target_id = gen_id("Target_SuperHearing_App")
    app_sources_id = gen_id("BuildPhase_App_Sources")
    app_frameworks_id = gen_id("BuildPhase_App_Frameworks")
    app_resources_id = gen_id("BuildPhase_App_Resources")
    app_product_id = gen_id("Product_SuperHearing_App")

    # Tests Target IDs
    tests_target_id = gen_id("Target_SuperHearingTests")
    tests_sources_id = gen_id("BuildPhase_Tests_Sources")
    tests_frameworks_id = gen_id("BuildPhase_Tests_Frameworks")
    tests_resources_id = gen_id("BuildPhase_Tests_Resources")
    tests_product_id = gen_id("Product_SuperHearingTests")

    # UITests Target IDs
    uitests_target_id = gen_id("Target_SuperHearingUITests")
    uitests_sources_id = gen_id("BuildPhase_UITests_Sources")
    uitests_frameworks_id = gen_id("BuildPhase_UITests_Frameworks")
    uitests_resources_id = gen_id("BuildPhase_UITests_Resources")
    uitests_product_id = gen_id("Product_SuperHearingUITests")
    # Source files list: (subfolder, filename, target)
    source_files = [
        ("SuperHearing/App", "SuperHearingApp.swift", "app"),
        ("SuperHearing/App", "AppDelegate.swift", "app"),
        ("SuperHearing/Views", "MainTabView.swift", "app"),
        ("SuperHearing/Views", "RecordingView.swift", "app"),
        ("SuperHearing/Views", "FileListView.swift", "app"),
        ("SuperHearing/Views", "ProcessingView.swift", "app"),
        ("SuperHearing/Views", "SeparationView.swift", "app"),
        ("SuperHearing/Views", "StemMixerView.swift", "app"),
        ("SuperHearing/Views", "SettingsView.swift", "app"),
        ("SuperHearing/ViewModels", "RecordingViewModel.swift", "app"),
        ("SuperHearing/ViewModels", "FileListViewModel.swift", "app"),
        ("SuperHearing/ViewModels", "ProcessingViewModel.swift", "app"),
        ("SuperHearing/ViewModels", "SeparationViewModel.swift", "app"),
        ("SuperHearing/ViewModels", "StemMixerViewModel.swift", "app"),
        ("SuperHearing/ViewModels", "SettingsViewModel.swift", "app"),
        ("SuperHearing/Models", "Stem.swift", "app"),
        ("SuperHearing/Models", "AudioFile.swift", "app"),
        ("SuperHearing/Models", "SeparatedAudio.swift", "app"),
        ("SuperHearing/Services", "RecordingService.swift", "app"),
        ("SuperHearing/Services", "NoiseReductionService.swift", "app"),
        ("SuperHearing/Services", "EnhancementService.swift", "app"),
        ("SuperHearing/Services", "SeparationService.swift", "app"),
        ("SuperHearing/Services", "PlaybackService.swift", "app"),
        ("SuperHearing/Utilities", "AudioBuffer.swift", "app"),
        ("SuperHearing/Utilities", "STFT.swift", "app"),
        ("SuperHearing/Utilities", "AGC.swift", "app"),
        ("SuperHearing/Utilities", "Extensions.swift", "app"),
        ("SuperHearingTests", "SuperHearingTests.swift", "tests"),
        ("SuperHearingUITests", "SuperHearingUITests.swift", "uitests"),
    ]

    resource_files = [
        ("SuperHearing/Resources", "Assets.xcassets", "folder.assetcatalog"),
        ("SuperHearing/Resources", "Info.plist", "text.plist.xml"),
        ("SuperHearing/Resources", "SuperHearing.entitlements", "text.plist.entitlements"),
        ("SuperHearing/Resources", "ExportOptions.plist", "text.plist.xml"),
    ]

    # Map file_path -> (file_ref_id, build_file_id)
    file_map = {}
    for folder, fname, tgt in source_files:
        path = f"{folder}/{fname}"
        file_map[path] = (gen_id(f"FileRef_{path}"), gen_id(f"BuildFile_{path}"), tgt)

    res_map = {}
    for folder, fname, ftype in resource_files:
        path = f"{folder}/{fname}"
        res_map[path] = (gen_id(f"FileRef_{path}"), gen_id(f"BuildFile_{path}"), ftype)

    out = []
    out.append("// !$*UTF8*$!")
    out.append("{")
    out.append("\tarchiveVersion = 1;")
    out.append("\tclasses = {")
    out.append("\t};")
    out.append("\tobjectVersion = 56;")
    out.append("\tobjects = {")
    out.append("")

    # --- PBXBuildFile Section ---
    out.append("/* Begin PBXBuildFile section */")
    for path, (f_ref, b_ref, tgt) in file_map.items():
        fname = os.path.basename(path)
        out.append(f"\t\t{b_ref} /* {fname} in Sources */ = {{isa = PBXBuildFile; fileRef = {f_ref} /* {fname} */; }};")

    # Resource build files (Assets.xcassets only for compile, others stay in group)
    assets_path = "SuperHearing/Resources/Assets.xcassets"
    a_ref, a_bref, _ = res_map[assets_path]
    out.append(f"\t\t{a_bref} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {a_ref} /* Assets.xcassets */; }};")

    out.append("/* End PBXBuildFile section */")
    out.append("")

    # --- PBXFileReference Section ---
    out.append("/* Begin PBXFileReference section */")
    out.append(f"\t\t{app_product_id} /* SuperHearing.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SuperHearing.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    out.append(f"\t\t{tests_product_id} /* SuperHearingTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = SuperHearingTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
    out.append(f"\t\t{uitests_product_id} /* SuperHearingUITests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = SuperHearingUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")

    for path, (f_ref, b_ref, tgt) in file_map.items():
        fname = os.path.basename(path)
        out.append(f"\t\t{f_ref} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {fname}; sourceTree = \"<group>\"; }};")

    for path, (f_ref, b_ref, ftype) in res_map.items():
        fname = os.path.basename(path)
        out.append(f"\t\t{f_ref} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = {fname}; sourceTree = \"<group>\"; }};")

    out.append("/* End PBXFileReference section */")
    out.append("")

    # --- PBXFrameworksBuildPhase Section ---
    out.append("/* Begin PBXFrameworksBuildPhase section */")
    out.append(f"\t\t{app_frameworks_id} /* Frameworks */ = {{")
    out.append("\t\t\tisa = PBXFrameworksBuildPhase;")
    out.append("\t\t\tbuildActionMask = 2147483647;")
    out.append("\t\t\tfiles = (")
    out.append("\t\t\t);")
    out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    out.append("\t\t};")

    out.append(f"\t\t{tests_frameworks_id} /* Frameworks */ = {{")
    out.append("\t\t\tisa = PBXFrameworksBuildPhase;")
    out.append("\t\t\tbuildActionMask = 2147483647;")
    out.append("\t\t\tfiles = (")
    out.append("\t\t\t);")
    out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    out.append("\t\t};")

    out.append(f"\t\t{uitests_frameworks_id} /* Frameworks */ = {{")
    out.append("\t\t\tisa = PBXFrameworksBuildPhase;")
    out.append("\t\t\tbuildActionMask = 2147483647;")
    out.append("\t\t\tfiles = (")
    out.append("\t\t\t);")
    out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    out.append("\t\t};")
    out.append("/* End PBXFrameworksBuildPhase section */")
    out.append("")

    # --- Groups ---
    groups = {
        "App": ("SuperHearing/App", [p for p in file_map if p.startswith("SuperHearing/App/")]),
        "Views": ("SuperHearing/Views", [p for p in file_map if p.startswith("SuperHearing/Views/")]),
        "ViewModels": ("SuperHearing/ViewModels", [p for p in file_map if p.startswith("SuperHearing/ViewModels/")]),
        "Models": ("SuperHearing/Models", [p for p in file_map if p.startswith("SuperHearing/Models/")]),
        "Services": ("SuperHearing/Services", [p for p in file_map if p.startswith("SuperHearing/Services/")]),
        "Utilities": ("SuperHearing/Utilities", [p for p in file_map if p.startswith("SuperHearing/Utilities/")]),
        "Resources": ("SuperHearing/Resources", list(res_map.keys())),
        "SuperHearing": ("SuperHearing", ["App", "Views", "ViewModels", "Models", "Services", "Utilities", "Resources"]),
        "SuperHearingTests": ("SuperHearingTests", [p for p in file_map if p.startswith("SuperHearingTests/")]),
        "SuperHearingUITests": ("SuperHearingUITests", [p for p in file_map if p.startswith("SuperHearingUITests/")]),
        "Products": ("Products", [app_product_id, tests_product_id, uitests_product_id]),
    }

    group_ids = {g: gen_id(f"Group_{g}") for g in groups}
    group_ids["Products"] = products_group_id

    out.append("/* Begin PBXGroup section */")
    for gname, (gpath, children) in groups.items():
        gid = group_ids[gname]
        out.append(f"\t\t{gid} /* {gname} */ = {{")
        out.append("\t\t\tisa = PBXGroup;")
        out.append("\t\t\tchildren = (")
        for c in children:
            if c in group_ids:
                out.append(f"\t\t\t\t{group_ids[c]} /* {c} */,")
            elif c in file_map:
                f_ref, _, _ = file_map[c]
                fname = os.path.basename(c)
                out.append(f"\t\t\t\t{f_ref} /* {fname} */,")
            elif c in res_map:
                f_ref, _, _ = res_map[c]
                fname = os.path.basename(c)
                out.append(f"\t\t\t\t{f_ref} /* {fname} */,")
            else:
                out.append(f"\t\t\t\t{c},")
        out.append("\t\t\t);")
        out.append(f"\t\t\tpath = {os.path.basename(gpath)};")
        out.append("\t\t\tsourceTree = \"<group>\";")
        out.append("\t\t};")

    # Main root group
    out.append(f"\t\t{main_group_id} = {{")
    out.append("\t\t\tisa = PBXGroup;")
    out.append("\t\t\tchildren = (")
    out.append(f"\t\t\t\t{group_ids['SuperHearing']} /* SuperHearing */,")
    out.append(f"\t\t\t\t{group_ids['SuperHearingTests']} /* SuperHearingTests */,")
    out.append(f"\t\t\t\t{group_ids['SuperHearingUITests']} /* SuperHearingUITests */,")
    out.append(f"\t\t\t\t{products_group_id} /* Products */,")
    out.append("\t\t\t);")
    out.append("\t\t\tsourceTree = \"<group>\";")
    out.append("\t\t};")
    out.append("/* End PBXGroup section */")
    out.append("")

    # --- PBXNativeTarget Section ---
    app_config_list_id = gen_id("ConfigList_App")
    tests_config_list_id = gen_id("ConfigList_Tests")
    uitests_config_list_id = gen_id("ConfigList_UITests")
    proj_config_list_id = gen_id("ConfigList_Proj")

    out.append("/* Begin PBXNativeTarget section */")
    # App
    out.append(f"\t\t{app_target_id} /* SuperHearing */ = {{")
    out.append("\t\t\tisa = PBXNativeTarget;")
    out.append(f"\t\t\tbuildConfigurationList = {app_config_list_id} /* Build configuration list for PBXNativeTarget \"SuperHearing\" */;")
    out.append("\t\t\tbuildPhases = (")
    out.append(f"\t\t\t\t{app_sources_id} /* Sources */,")
    out.append(f"\t\t\t\t{app_frameworks_id} /* Frameworks */,")
    out.append(f"\t\t\t\t{app_resources_id} /* Resources */,")
    out.append("\t\t\t);")
    out.append("\t\t\tbuildRules = (")
    out.append("\t\t\t);")
    out.append("\t\t\tdependencies = (")
    out.append("\t\t\t);")
    out.append("\t\t\tname = SuperHearing;")
    out.append("\t\t\tpackageProductDependencies = (")
    out.append("\t\t\t);")
    out.append(f"\t\t\tproductName = SuperHearing;")
    out.append(f"\t\t\tproductReference = {app_product_id} /* SuperHearing.app */;")
    out.append("\t\t\tproductType = \"com.apple.product-type.application\";")
    out.append("\t\t};")

    # Tests
    out.append(f"\t\t{tests_target_id} /* SuperHearingTests */ = {{")
    out.append("\t\t\tisa = PBXNativeTarget;")
    out.append(f"\t\t\tbuildConfigurationList = {tests_config_list_id} /* Build configuration list for PBXNativeTarget \"SuperHearingTests\" */;")
    out.append("\t\t\tbuildPhases = (")
    out.append(f"\t\t\t\t{tests_sources_id} /* Sources */,")
    out.append(f"\t\t\t\t{tests_frameworks_id} /* Frameworks */,")
    out.append(f"\t\t\t\t{tests_resources_id} /* Resources */,")
    out.append("\t\t\t);")
    out.append("\t\t\tbuildRules = (")
    out.append("\t\t\t);")
    out.append("\t\t\tdependencies = (")
    out.append("\t\t\t);")
    out.append("\t\t\tname = SuperHearingTests;")
    out.append("\t\t\tproductName = SuperHearingTests;")
    out.append(f"\t\t\tproductReference = {tests_product_id} /* SuperHearingTests.xctest */;")
    out.append("\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";")
    out.append("\t\t};")

    # UITests
    out.append(f"\t\t{uitests_target_id} /* SuperHearingUITests */ = {{")
    out.append("\t\t\tisa = PBXNativeTarget;")
    out.append(f"\t\t\tbuildConfigurationList = {uitests_config_list_id} /* Build configuration list for PBXNativeTarget \"SuperHearingUITests\" */;")
    out.append("\t\t\tbuildPhases = (")
    out.append(f"\t\t\t\t{uitests_sources_id} /* Sources */,")
    out.append(f"\t\t\t\t{uitests_frameworks_id} /* Frameworks */,")
    out.append(f"\t\t\t\t{uitests_resources_id} /* Resources */,")
    out.append("\t\t\t);")
    out.append("\t\t\tbuildRules = (")
    out.append("\t\t\t);")
    out.append("\t\t\tdependencies = (")
    out.append("\t\t\t);")
    out.append("\t\t\tname = SuperHearingUITests;")
    out.append("\t\t\tproductName = SuperHearingUITests;")
    out.append(f"\t\t\tproductReference = {uitests_product_id} /* SuperHearingUITests.xctest */;")
    out.append("\t\t\tproductType = \"com.apple.product-type.bundle.ui-testing\";")
    out.append("\t\t};")
    out.append("/* End PBXNativeTarget section */")
    out.append("")

    # --- PBXProject Section ---
    out.append("/* Begin PBXProject section */")
    out.append(f"\t\t{proj_id} /* Project object */ = {{")
    out.append("\t\t\tisa = PBXProject;")
    out.append("\t\t\tattributes = {")
    out.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    out.append("\t\t\t\tLastUpgradeCheck = 1540;")
    out.append("\t\t\t\tTargetAttributes = {")
    out.append(f"\t\t\t\t\t{app_target_id} = {{")
    out.append("\t\t\t\t\t\tCreatedOnToolsVersion = 15.4;")
    out.append("\t\t\t\t\t};")
    out.append(f"\t\t\t\t\t{tests_target_id} = {{")
    out.append("\t\t\t\t\t\tCreatedOnToolsVersion = 15.4;")
    out.append(f"\t\t\t\t\t\tTestTargetID = {app_target_id};")
    out.append("\t\t\t\t\t};")
    out.append(f"\t\t\t\t\t{uitests_target_id} = {{")
    out.append("\t\t\t\t\t\tCreatedOnToolsVersion = 15.4;")
    out.append(f"\t\t\t\t\t\tTestTargetID = {app_target_id};")
    out.append("\t\t\t\t\t};")
    out.append("\t\t\t\t};")
    out.append("\t\t\t};")
    out.append(f"\t\t\tbuildConfigurationList = {proj_config_list_id} /* Build configuration list for PBXProject \"SuperHearing\" */;")
    out.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    out.append("\t\t\tdevelopmentRegion = en;")
    out.append("\t\t\thasScannedForEncodings = 0;")
    out.append("\t\t\tknownRegions = (")
    out.append("\t\t\t\ten,")
    out.append("\t\t\t\tBase,")
    out.append("\t\t\t);")
    out.append(f"\t\t\tmainGroup = {main_group_id};")
    out.append("\t\t\tpackageReferences = (")
    out.append("\t\t\t);")
    out.append(f"\t\t\tproductRefGroup = {products_group_id} /* Products */;")
    out.append("\t\t\tprojectDirPath = \"\";")
    out.append("\t\t\tprojectRoot = \"\";")
    out.append("\t\t\ttargets = (")
    out.append(f"\t\t\t\t{app_target_id} /* SuperHearing */,")
    out.append(f"\t\t\t\t{tests_target_id} /* SuperHearingTests */,")
    out.append(f"\t\t\t\t{uitests_target_id} /* SuperHearingUITests */,")
    out.append("\t\t\t);")
    out.append("\t\t};")
    out.append("/* End PBXProject section */")
    out.append("")

    # --- PBXResourcesBuildPhase Section ---
    out.append("/* Begin PBXResourcesBuildPhase section */")
    out.append(f"\t\t{app_resources_id} /* Resources */ = {{")
    out.append("\t\t\tisa = PBXResourcesBuildPhase;")
    out.append("\t\t\tbuildActionMask = 2147483647;")
    out.append("\t\t\tfiles = (")
    out.append(f"\t\t\t\t{a_bref} /* Assets.xcassets in Resources */,")
    out.append("\t\t\t);")
    out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    out.append("\t\t};")

    out.append(f"\t\t{tests_resources_id} /* Resources */ = {{")
    out.append("\t\t\tisa = PBXResourcesBuildPhase;")
    out.append("\t\t\tbuildActionMask = 2147483647;")
    out.append("\t\t\tfiles = (")
    out.append("\t\t\t);")
    out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    out.append("\t\t};")

    out.append(f"\t\t{uitests_resources_id} /* Resources */ = {{")
    out.append("\t\t\tisa = PBXResourcesBuildPhase;")
    out.append("\t\t\tbuildActionMask = 2147483647;")
    out.append("\t\t\tfiles = (")
    out.append("\t\t\t);")
    out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    out.append("\t\t};")
    out.append("/* End PBXResourcesBuildPhase section */")
    out.append("")

    # --- PBXSourcesBuildPhase Section ---
    out.append("/* Begin PBXSourcesBuildPhase section */")
    # App Sources
    out.append(f"\t\t{app_sources_id} /* Sources */ = {{")
    out.append("\t\t\tisa = PBXSourcesBuildPhase;")
    out.append("\t\t\tbuildActionMask = 2147483647;")
    out.append("\t\t\tfiles = (")
    for path, (f_ref, b_ref, tgt) in file_map.items():
        if tgt == "app":
            fname = os.path.basename(path)
            out.append(f"\t\t\t\t{b_ref} /* {fname} in Sources */,")
    out.append("\t\t\t);")
    out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    out.append("\t\t};")

    # Tests Sources
    out.append(f"\t\t{tests_sources_id} /* Sources */ = {{")
    out.append("\t\t\tisa = PBXSourcesBuildPhase;")
    out.append("\t\t\tbuildActionMask = 2147483647;")
    out.append("\t\t\tfiles = (")
    for path, (f_ref, b_ref, tgt) in file_map.items():
        if tgt == "tests":
            fname = os.path.basename(path)
            out.append(f"\t\t\t\t{b_ref} /* {fname} in Sources */,")
    out.append("\t\t\t);")
    out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    out.append("\t\t};")

    # UITests Sources
    out.append(f"\t\t{uitests_sources_id} /* Sources */ = {{")
    out.append("\t\t\tisa = PBXSourcesBuildPhase;")
    out.append("\t\t\tbuildActionMask = 2147483647;")
    out.append("\t\t\tfiles = (")
    for path, (f_ref, b_ref, tgt) in file_map.items():
        if tgt == "uitests":
            fname = os.path.basename(path)
            out.append(f"\t\t\t\t{b_ref} /* {fname} in Sources */,")
    out.append("\t\t\t);")
    out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    out.append("\t\t};")
    out.append("/* End PBXSourcesBuildPhase section */")
    out.append("")

    # --- XCBuildConfiguration Section ---
    cfg_proj_debug = gen_id("Cfg_Proj_Debug")
    cfg_proj_release = gen_id("Cfg_Proj_Release")
    cfg_app_debug = gen_id("Cfg_App_Debug")
    cfg_app_release = gen_id("Cfg_App_Release")
    cfg_tests_debug = gen_id("Cfg_Tests_Debug")
    cfg_tests_release = gen_id("Cfg_Tests_Release")
    cfg_uitests_debug = gen_id("Cfg_UITests_Debug")
    cfg_uitests_release = gen_id("Cfg_UITests_Release")

    out.append("/* Begin XCBuildConfiguration section */")
    # Proj Debug
    out.append(f"\t\t{cfg_proj_debug} /* Debug */ = {{")
    out.append("\t\t\tisa = XCBuildConfiguration;")
    out.append("\t\t\tbuildSettings = {")
    out.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    out.append("\t\t\t\tCLANG_ANALYZER_NONNULL = YES;")
    out.append("\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";")
    out.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    out.append("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    out.append("\t\t\t\tCOPY_PHASE_STRIP = NO;")
    out.append("\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;")
    out.append("\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
    out.append("\t\t\t\tENABLE_TESTABILITY = YES;")
    out.append("\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;")
    out.append("\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;")
    out.append("\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (")
    out.append("\t\t\t\t\t\"DEBUG=1\",")
    out.append("\t\t\t\t\t\"$(inherited)\",")
    out.append("\t\t\t\t);")
    out.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
    out.append("\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;")
    out.append("\t\t\t\tONLY_ACTIVE_ARCH = YES;")
    out.append("\t\t\t\tSDKROOT = iphoneos;")
    out.append("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
    out.append("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
    out.append("\t\t\t\tSWIFT_VERSION = 5.9;")
    out.append("\t\t\t};")
    out.append("\t\t\tname = Debug;")
    out.append("\t\t};")

    # Proj Release
    out.append(f"\t\t{cfg_proj_release} /* Release */ = {{")
    out.append("\t\t\tisa = XCBuildConfiguration;")
    out.append("\t\t\tbuildSettings = {")
    out.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    out.append("\t\t\t\tCLANG_ANALYZER_NONNULL = YES;")
    out.append("\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";")
    out.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    out.append("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    out.append("\t\t\t\tCOPY_PHASE_STRIP = NO;")
    out.append("\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";")
    out.append("\t\t\t\tENABLE_NS_ASSERTIONS = NO;")
    out.append("\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
    out.append("\t\t\t\tGCC_OPTIMIZATION_LEVEL = s;")
    out.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
    out.append("\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;")
    out.append("\t\t\t\tSDKROOT = iphoneos;")
    out.append("\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
    out.append("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";")
    out.append("\t\t\t\tSWIFT_VERSION = 5.9;")
    out.append("\t\t\t\tVALIDATE_PRODUCT = YES;")
    out.append("\t\t\t};")
    out.append("\t\t\tname = Release;")
    out.append("\t\t};")

    # App Debug
    out.append(f"\t\t{cfg_app_debug} /* Debug */ = {{")
    out.append("\t\t\tisa = XCBuildConfiguration;")
    out.append("\t\t\tbuildSettings = {")
    out.append("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    out.append("\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
    out.append("\t\t\t\tCODE_SIGN_ENTITLEMENTS = SuperHearing/Resources/SuperHearing.entitlements;")
    out.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    out.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    out.append("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
    out.append("\t\t\t\tINFOPLIST_FILE = SuperHearing/Resources/Info.plist;")
    out.append("\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = SuperHearing;")
    out.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
    out.append("\t\t\t\t\t\"$(inherited)\",")
    out.append("\t\t\t\t\t\"@executable_path/Frameworks\",")
    out.append("\t\t\t\t);")
    out.append("\t\t\t\tMARKETING_VERSION = 1.0.0;")
    out.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.superhearing.app;")
    out.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    out.append("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    out.append("\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";")
    out.append("\t\t\t};")
    out.append("\t\t\tname = Debug;")
    out.append("\t\t};")

    # App Release
    out.append(f"\t\t{cfg_app_release} /* Release */ = {{")
    out.append("\t\t\tisa = XCBuildConfiguration;")
    out.append("\t\t\tbuildSettings = {")
    out.append("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    out.append("\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
    out.append("\t\t\t\tCODE_SIGN_ENTITLEMENTS = SuperHearing/Resources/SuperHearing.entitlements;")
    out.append("\t\t\t\tCODE_SIGN_STYLE = Manual;")
    out.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    out.append("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
    out.append("\t\t\t\tINFOPLIST_FILE = SuperHearing/Resources/Info.plist;")
    out.append("\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = SuperHearing;")
    out.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
    out.append("\t\t\t\t\t\"$(inherited)\",")
    out.append("\t\t\t\t\t\"@executable_path/Frameworks\",")
    out.append("\t\t\t\t);")
    out.append("\t\t\t\tMARKETING_VERSION = 1.0.0;")
    out.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.superhearing.app;")
    out.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    out.append("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    out.append("\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";")
    out.append("\t\t\t};")
    out.append("\t\t\tname = Release;")
    out.append("\t\t};")

    # Tests Debug
    out.append(f"\t\t{cfg_tests_debug} /* Debug */ = {{")
    out.append("\t\t\tisa = XCBuildConfiguration;")
    out.append("\t\t\tbuildSettings = {")
    out.append("\t\t\t\tBUNDLE_LOADER = \"$(TEST_HOST)\";")
    out.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.superhearing.appTests;")
    out.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    out.append("\t\t\t\tTEST_HOST = \"$(BUILT_PRODUCTS_DIR)/SuperHearing.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SuperHearing\";")
    out.append("\t\t\t};")
    out.append("\t\t\tname = Debug;")
    out.append("\t\t};")

    # Tests Release
    out.append(f"\t\t{cfg_tests_release} /* Release */ = {{")
    out.append("\t\t\tisa = XCBuildConfiguration;")
    out.append("\t\t\tbuildSettings = {")
    out.append("\t\t\t\tBUNDLE_LOADER = \"$(TEST_HOST)\";")
    out.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.superhearing.appTests;")
    out.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    out.append("\t\t\t\tTEST_HOST = \"$(BUILT_PRODUCTS_DIR)/SuperHearing.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SuperHearing\";")
    out.append("\t\t\t};")
    out.append("\t\t\tname = Release;")
    out.append("\t\t};")

    # UITests Debug
    out.append(f"\t\t{cfg_uitests_debug} /* Debug */ = {{")
    out.append("\t\t\tisa = XCBuildConfiguration;")
    out.append("\t\t\tbuildSettings = {")
    out.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.superhearing.appUITests;")
    out.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    out.append("\t\t\t\tTEST_TARGET_NAME = SuperHearing;")
    out.append("\t\t\t};")
    out.append("\t\t\tname = Debug;")
    out.append("\t\t};")

    # UITests Release
    out.append(f"\t\t{cfg_uitests_release} /* Release */ = {{")
    out.append("\t\t\tisa = XCBuildConfiguration;")
    out.append("\t\t\tbuildSettings = {")
    out.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.superhearing.appUITests;")
    out.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    out.append("\t\t\t\tTEST_TARGET_NAME = SuperHearing;")
    out.append("\t\t\t};")
    out.append("\t\t\tname = Release;")
    out.append("\t\t};")
    out.append("/* End XCBuildConfiguration section */")
    out.append("")

    # --- XCConfigurationList Section ---
    out.append("/* Begin XCConfigurationList section */")
    out.append(f"\t\t{proj_config_list_id} /* Build configuration list for PBXProject \"SuperHearing\" */ = {{")
    out.append("\t\t\tisa = XCConfigurationList;")
    out.append("\t\t\tbuildConfigurations = (")
    out.append(f"\t\t\t\t{cfg_proj_debug} /* Debug */,")
    out.append(f"\t\t\t\t{cfg_proj_release} /* Release */,")
    out.append("\t\t\t);")
    out.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    out.append("\t\t\tdefaultConfigurationName = Release;")
    out.append("\t\t};")

    out.append(f"\t\t{app_config_list_id} /* Build configuration list for PBXNativeTarget \"SuperHearing\" */ = {{")
    out.append("\t\t\tisa = XCConfigurationList;")
    out.append("\t\t\tbuildConfigurations = (")
    out.append(f"\t\t\t\t{cfg_app_debug} /* Debug */,")
    out.append(f"\t\t\t\t{cfg_app_release} /* Release */,")
    out.append("\t\t\t);")
    out.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    out.append("\t\t\tdefaultConfigurationName = Release;")
    out.append("\t\t};")

    out.append(f"\t\t{tests_config_list_id} /* Build configuration list for PBXNativeTarget \"SuperHearingTests\" */ = {{")
    out.append("\t\t\tisa = XCConfigurationList;")
    out.append("\t\t\tbuildConfigurations = (")
    out.append(f"\t\t\t\t{cfg_tests_debug} /* Debug */,")
    out.append(f"\t\t\t\t{cfg_tests_release} /* Release */,")
    out.append("\t\t\t);")
    out.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    out.append("\t\t\tdefaultConfigurationName = Release;")
    out.append("\t\t};")

    out.append(f"\t\t{uitests_config_list_id} /* Build configuration list for PBXNativeTarget \"SuperHearingUITests\" */ = {{")
    out.append("\t\t\tisa = XCConfigurationList;")
    out.append("\t\t\tbuildConfigurations = (")
    out.append(f"\t\t\t\t{cfg_uitests_debug} /* Debug */,")
    out.append(f"\t\t\t\t{cfg_uitests_release} /* Release */,")
    out.append("\t\t\t);")
    out.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    out.append("\t\t\tdefaultConfigurationName = Release;")
    out.append("\t\t};")
    out.append("/* End XCConfigurationList section */")
    out.append("")

    out.append("\t};")
    out.append(f"\trootObject = {proj_id} /* Project object */;")
    out.append("}")
    out.append("")

    target_path = "SuperHearing.xcodeproj/project.pbxproj"
    with open(target_path, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print(f"Generated {target_path} successfully.")

if __name__ == "__main__":
    main()
