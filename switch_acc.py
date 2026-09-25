#!/usr/bin/env python3
"""
Antigravity Multi-Account Profile Switcher (macOS)
Manages and swaps Google Antigravity authentication profiles via macOS Keychain.
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path

KEYCHAIN_SERVICE = "gemini"
KEYCHAIN_ACCOUNT = "antigravity"
APP_NAME = "Antigravity"
PROFILES_DIR = Path.home() / ".gemini" / "antigravity" / "profiles"
METADATA_FILE = PROFILES_DIR / "profiles.json"


def ensure_profile_dir():
    PROFILES_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(PROFILES_DIR, 0o700)
    if not METADATA_FILE.exists():
        METADATA_FILE.write_text(json.dumps({}, indent=2))
        os.chmod(METADATA_FILE, 0o600)


def get_active_token():
    cmd = [
        "/usr/bin/security",
        "find-generic-password",
        "-s",
        KEYCHAIN_SERVICE,
        "-a",
        KEYCHAIN_ACCOUNT,
        "-w",
    ]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        token = res.stdout.strip()
        if not token:
            return None
        return token
    except subprocess.CalledProcessError:
        return None


def write_token_to_keychain(token: str):
    cmd = [
        "/usr/bin/security",
        "add-generic-password",
        "-U",
        "-s",
        KEYCHAIN_SERVICE,
        "-a",
        KEYCHAIN_ACCOUNT,
        "-w",
        token,
    ]
    subprocess.run(cmd, check=True, capture_output=True)


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()[:12]


def cmd_save(name: str):
    ensure_profile_dir()
    token = get_active_token()
    if not token:
        print("[ERROR] No active Antigravity credential found in macOS Keychain.")
        print("Please log into Antigravity once via browser before saving.")
        sys.exit(1)

    profile_file = PROFILES_DIR / f"{name}.token"
    profile_file.write_text(token)
    os.chmod(profile_file, 0o600)

    try:
        meta = json.loads(METADATA_FILE.read_text())
    except Exception:
        meta = {}

    meta[name] = {
        "saved_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "token_hash": token_hash(token),
    }
    METADATA_FILE.write_text(json.dumps(meta, indent=2))

    print(f"[OK] Profile '{name}' saved successfully (Hash: {token_hash(token)}).")


def cmd_list():
    ensure_profile_dir()
    active_token = get_active_token()
    active_hash = token_hash(active_token) if active_token else None

    token_files = list(PROFILES_DIR.glob("*.token"))
    if not token_files:
        print("No profiles saved yet. Use: switch-acc save <name>")
        return

    print("Saved Antigravity Profiles:")
    print("-" * 55)
    print(f"{'STATUS':<10} {'PROFILE NAME':<20} {'SAVED AT':<20}")
    print("-" * 55)

    try:
        meta = json.loads(METADATA_FILE.read_text())
    except Exception:
        meta = {}

    for f in sorted(token_files):
        pname = f.stem
        token = f.read_text().strip()
        phash = token_hash(token)
        is_active = (active_hash == phash)
        status = "[ACTIVE]" if is_active else " "
        saved_at = meta.get(pname, {}).get("saved_at", "Unknown")
        print(f"{status:<10} {pname:<20} {saved_at:<20}")
    print("-" * 55)


def is_app_running() -> bool:
    res = subprocess.run(["pgrep", "-f", "/Applications/Antigravity.app"], capture_output=True)
    return res.returncode == 0


def restart_app():
    if is_app_running():
        print(f"Quitting {APP_NAME}...")
        subprocess.run(["osascript", "-e", f'tell application "{APP_NAME}" to quit'], capture_output=True)
        # Wait up to 5 seconds for clean exit
        for _ in range(10):
            time.sleep(0.5)
            if not is_app_running():
                break
        else:
            print("Force terminating remaining helper processes...")
            subprocess.run(["pkill", "-f", "/Applications/Antigravity.app"], capture_output=True)
            time.sleep(1)

    print(f"Launching {APP_NAME} with updated profile...")
    subprocess.run(["open", "-a", APP_NAME], check=True)


def cmd_switch(name: str, no_restart: bool):
    ensure_profile_dir()
    profile_file = PROFILES_DIR / f"{name}.token"
    if not profile_file.exists():
        print(f"[ERROR] Profile '{name}' does not exist.")
        print(f"Available profiles: {[p.stem for p in PROFILES_DIR.glob('*.token')]}")
        sys.exit(1)

    token = profile_file.read_text().strip()
    if not token:
        print(f"[ERROR] Profile '{name}' contains an empty token.")
        sys.exit(1)

    print(f"Injecting profile '{name}' into macOS Keychain...")
    write_token_to_keychain(token)
    print(f"[OK] Keychain successfully updated to profile '{name}'.")

    if no_restart:
        print("Notice: --no-restart specified. Restart Antigravity manually to apply.")
    else:
        restart_app()
        print(f"[OK] Antigravity restarted under profile '{name}'.")


def cmd_delete(name: str):
    ensure_profile_dir()
    profile_file = PROFILES_DIR / f"{name}.token"
    if not profile_file.exists():
        print(f"[ERROR] Profile '{name}' not found.")
        return

    profile_file.unlink()
    try:
        meta = json.loads(METADATA_FILE.read_text())
        if name in meta:
            del meta[name]
            METADATA_FILE.write_text(json.dumps(meta, indent=2))
    except Exception:
        pass
    print(f"[OK] Profile '{name}' removed.")


def main():
    if sys.platform != "darwin":
        print("[ERROR] This switcher is designed specifically for macOS Keychain.")
        sys.exit(1)

    parser = argparse.ArgumentParser(description="Antigravity Account Profile Switcher")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # save
    save_parser = subparsers.add_parser("save", help="Snapshot current active login to a profile")
    save_parser.add_argument("name", help="Profile name (e.g. pro1, work, personal)")

    # list
    subparsers.add_parser("list", help="List all saved profiles")

    # switch
    switch_parser = subparsers.add_parser("switch", help="Switch active profile and restart Antigravity")
    switch_parser.add_argument("name", help="Profile name to switch to")
    switch_parser.add_argument(
        "--no-restart",
        action="store_true",
        help="Update Keychain only without restarting the Antigravity application",
    )

    # delete
    del_parser = subparsers.add_parser("delete", help="Delete a saved profile")
    del_parser.add_argument("name", help="Profile name to delete")

    args = parser.parse_args()

    if args.command == "save":
        cmd_save(args.name)
    elif args.command == "list":
        cmd_list()
    elif args.command == "switch":
        cmd_switch(args.name, args.no_restart)
    elif args.command == "delete":
        cmd_delete(args.name)


if __name__ == "__main__":
    main()
