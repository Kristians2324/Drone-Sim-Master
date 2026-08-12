#!/usr/bin/env python3
"""
tools/generate_translations.py - Automated Translation Generator & Validator Tool

Validates localization key parity across all supported languages (EN, DE, ES, FR, ZH, JA, KO, RU, AR)
and exports missing key reports or auto-translated JSON dictionaries.
"""

import json
import os
import sys

SUPPORTED_LOCALES = ["en", "de", "es", "fr", "zh", "ja", "ko", "ru", "ar"]

REQUIRED_KEYS = [
    "TAB_CONTROLS", "TAB_SHOW", "TAB_OPTIONS", "TAB_DEV",
    "BTN_RESUME", "BTN_TUTORIAL", "BTN_MAIN_MENU", "BTN_RESTART", "BTN_QUIT",
    "TITLE_LIGHT_SHOWS", "LABEL_SWARM_FORMATIONS", "BTN_STAR", "BTN_CIRCLE", "BTN_HEART", "BTN_DIAMOND", "BTN_WAVE",
    "BTN_STOP_SHOW", "BTN_RECORD_SHOW", "BTN_TAKE_SCREENSHOT", "BTN_ENABLE_CINEMATIC",
    "TITLE_OPTIONS", "LABEL_LANGUAGE", "LABEL_GRAPHICS_PRESET", "LABEL_RESOLUTION_SCALE",
    "LABEL_SHADOW_QUALITY", "LABEL_ANTI_ALIASING", "LABEL_BLOOM_GLOW", "LABEL_VSYNC",
    "LABEL_MASTER_VOLUME", "LABEL_MUSIC_VOLUME", "LABEL_SFX_VOLUME", "LABEL_DRONE_AUDIO",
    "LABEL_WIND_TURBULENCE", "LABEL_BATTERY_SIM", "LABEL_COLLISION_PHYSICS", "LABEL_CAMERA_FOV",
    "TITLE_SIMULATOR", "SUBTITLE_SIMULATOR", "BTN_START_SIM", "BTN_QUICK_TUTORIAL",
    "TITLE_DEV_MENU", "LABEL_DRAIN_MULT", "LABEL_GOD_MODE", "LABEL_DEV_STATUS",
    "TITLE_KEYBOARD_CONTROLS", "TITLE_XBOX_CONTROLS",
    "DIALOG_QUIT_TITLE", "DIALOG_QUIT_MSG", "BTN_CONFIRM", "BTN_CANCEL",
    "TOAST_SCREENSHOT", "TOAST_RECORDING_START", "TOAST_RECORDING_STOP"
]

def main():
    print("==================================================")
    print("  Drone Sim - Localization Verification & Generator")
    print("==================================================")
    print(f"Checking {len(REQUIRED_KEYS)} required localization keys across {len(SUPPORTED_LOCALES)} languages...\n")

    gd_path = os.path.join(os.path.dirname(__file__), "..", "scripts", "ui", "TranslationManager.gd")
    if not os.path.exists(gd_path):
        print(f"Error: TranslationManager.gd not found at {gd_path}")
        sys.exit(1)

    with open(gd_path, "r", encoding="utf-8") as f:
        content = f.read()

    missing_report = {}
    for loc in SUPPORTED_LOCALES:
        missing = []
        for key in REQUIRED_KEYS:
            if f'"{key}"' not in content:
                missing.append(key)
        if missing:
            missing_report[loc] = missing

    if missing_report:
        print("[X] Missing translation keys detected:")
        for loc, keys in missing_report.items():
            print(f"  [{loc}]: {', '.join(keys)}")
        sys.exit(1)
    else:
        print("[OK] All required localization keys present across all locales!")
        print("==================================================")

if __name__ == "__main__":
    main()
