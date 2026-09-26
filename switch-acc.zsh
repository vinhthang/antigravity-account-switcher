#!/usr/bin/env zsh
_switch_acc_extract_email() {
  local token="$1"
  python3 -c '
import sys, json, base64
try:
    raw = sys.stdin.read().strip()
    if raw.startswith("go-keyring-base64:"):
        raw = raw[len("go-keyring-base64:"):]
    data = json.loads(base64.b64decode(raw).decode("utf-8"))
    id_token = data.get("id_token", "")
    parts = id_token.split(".")
    if len(parts) > 1:
        p = parts[1] + "=" * ((4 - len(parts[1]) % 4) % 4)
        claims = json.loads(base64.urlsafe_b64decode(p).decode("utf-8"))
        print(claims.get("email", "-"))
    else:
        print("-")
except Exception:
    print("-")
' <<< "$token"
}

switch-acc() {
  local KEYCHAIN_SERVICE="gemini"
  local KEYCHAIN_ACCOUNT="antigravity"
  local APP_NAME="Antigravity"
  local PROFILES_DIR="$HOME/.gemini/antigravity/profiles"

  # Ensure profile storage directory exists with strict permissions
  mkdir -p "$PROFILES_DIR"
  chmod 700 "$PROFILES_DIR"

  local cmd="${1:-}"

  case "$cmd" in
    save)
      local name="${2:-}"
      if [[ -z "$name" ]]; then
        echo "Usage: switch-acc save <profile_name>"
        return 1
      fi

      local token
      token=$(/usr/bin/security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null)
      if [[ -z "$token" ]]; then
        echo "[ERROR] No active Antigravity credential found in macOS Keychain."
        echo "Please log into Antigravity once via browser before saving."
        return 1
      fi

      local profile_file="$PROFILES_DIR/${name}.token"
      print -r -- "$token" > "$profile_file"
      chmod 600 "$profile_file"

      local email
      email=$(_switch_acc_extract_email "$token")
      if [[ -n "$email" && "$email" != "-" ]]; then
        print -r -- "$email" > "$PROFILES_DIR/${name}.email"
      fi

      date '+%Y-%m-%d %H:%M:%S' > "$PROFILES_DIR/${name}.last_switched"

      local token_hash
      token_hash=$(echo -n "$token" | shasum -a 256 | awk '{print substr($1,1,12)}')
      echo "[OK] Profile '$name' saved successfully ($email, Hash: $token_hash)."
      ;;

    list)
      local active_token active_email="" active_hash=""
      active_token=$(/usr/bin/security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null)
      if [[ -n "$active_token" ]]; then
        active_hash=$(echo -n "$active_token" | shasum -a 256 | awk '{print substr($1,1,12)}')
        active_email=$(_switch_acc_extract_email "$active_token")
      fi

      setopt local_options null_glob
      local token_files=("$PROFILES_DIR"/*.token)
      if [[ ${#token_files[@]} -eq 0 ]]; then
        echo "No profiles saved yet. Use: switch-acc save <name>"
        return 0
      fi

      echo "Saved Antigravity Profiles:"
      echo "--------------------------------------------------------------------------------------------------------------------------------"
      printf "%-10s %-16s %-32s %-16s %-22s %-22s\n" "STATUS" "PROFILE NAME" "EMAIL" "TOKEN HASH" "DATE ADDED" "LAST SWITCHED"
      echo "--------------------------------------------------------------------------------------------------------------------------------"

      local pname ptoken phash prof_status added_date last_switched_file last_switched email_file email
      for f in "${token_files[@]}"; do
        pname="${f:t:r}"
        ptoken=$(<"$f")
        phash=$(echo -n "$ptoken" | shasum -a 256 | awk '{print substr($1,1,12)}')

        email_file="$PROFILES_DIR/${pname}.email"
        if [[ -f "$email_file" ]]; then
          email=$(<"$email_file")
        else
          email=$(_switch_acc_extract_email "$ptoken")
          [[ -n "$email" && "$email" != "-" ]] && print -r -- "$email" > "$email_file"
        fi

        prof_status=" "
        if [[ "$active_hash" == "$phash" ]] || [[ -n "$active_email" && "$active_email" != "-" && "$active_email" == "$email" ]]; then
          prof_status="[ACTIVE]"
          # If the active token in Keychain has been refreshed, sync the new token to the profile file
          if [[ "$active_hash" != "$phash" && -n "$active_token" ]]; then
            print -r -- "$active_token" > "$f"
            phash="$active_hash"
          fi
        fi

        added_date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$f" 2>/dev/null || echo "Unknown")
        last_switched_file="$PROFILES_DIR/${pname}.last_switched"
        if [[ -f "$last_switched_file" ]]; then
          last_switched=$(<"$last_switched_file")
        else
          last_switched="$added_date"
        fi
        printf "%-10s %-16s %-32s %-16s %-22s %-22s\n" "$prof_status" "$pname" "$email" "$phash" "$added_date" "$last_switched"
      done
      echo "--------------------------------------------------------------------------------------------------------------------------------"
      ;;

    switch)
      local name="${2:-}"
      local restart_mode="${3:-}"
      if [[ -z "$name" ]]; then
        echo "Usage: switch-acc switch <profile_name> [--no-restart|--detached]"
        return 1
      fi

      local profile_file="$PROFILES_DIR/${name}.token"
      if [[ ! -f "$profile_file" ]]; then
        echo "[ERROR] Profile '$name' does not exist."
        setopt local_options null_glob
        local available=("${PROFILES_DIR}"/*.token)
        echo "Available profiles: ${available[@]:t:r}"
        return 1
      fi

      local token
      token=$(<"$profile_file")
      if [[ -z "$token" ]]; then
        echo "[ERROR] Profile '$name' contains an empty token."
        return 1
      fi

      echo "Injecting profile '$name' into macOS Keychain..."
      /usr/bin/security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w "$token"
      echo "[OK] Keychain successfully updated to profile '$name'."
      date '+%Y-%m-%d %H:%M:%S' > "$PROFILES_DIR/${name}.last_switched"

      if [[ "$restart_mode" == "--no-restart" ]]; then
        echo "Notice: --no-restart specified. Restart Antigravity manually to apply."
      elif [[ "$restart_mode" == "--detached" || "$restart_mode" == "--detached-restart" ]]; then
        echo "[OK] Detached restart scheduled in 2 seconds. Antigravity will reconnect automatically."
        nohup zsh -c 'sleep 2 && if pgrep -f "/Applications/Antigravity.app" >/dev/null 2>&1; then osascript -e "tell application \"Antigravity\" to quit" 2>/dev/null; sleep 2; pkill -f "/Applications/Antigravity.app" 2>/dev/null; sleep 1; fi; open -a "Antigravity"' >/dev/null 2>&1 &
      else
        if pgrep -f "/Applications/Antigravity.app" >/dev/null 2>&1; then
          echo "Quitting $APP_NAME..."
          osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null
          local i=0
          while pgrep -f "/Applications/Antigravity.app" >/dev/null 2>&1 && [[ $i -lt 10 ]]; do
            sleep 0.5
            ((i++))
          done
          if pgrep -f "/Applications/Antigravity.app" >/dev/null 2>&1; then
            echo "Force terminating remaining helper processes..."
            pkill -f "/Applications/Antigravity.app" 2>/dev/null
            sleep 1
          fi
        fi
        echo "Launching $APP_NAME with updated profile..."
        open -a "$APP_NAME"
        echo "[OK] Antigravity restarted under profile '$name'."
      fi
      ;;

    delete|rm)
      local name="${2:-}"
      if [[ -z "$name" ]]; then
        echo "Usage: switch-acc delete <profile_name>"
        return 1
      fi
      local profile_file="$PROFILES_DIR/${name}.token"
      if [[ -f "$profile_file" ]]; then
        rm -f "$profile_file" "$PROFILES_DIR/${name}.last_switched" "$PROFILES_DIR/${name}.email"
        echo "[OK] Profile '$name' deleted."
      else
        echo "[ERROR] Profile '$name' not found."
        return 1
      fi
      ;;

    help|--help|-h|"")
      echo "Antigravity Account Profile Switcher (Zsh)"
      echo ""
      echo "Commands:"
      echo "  switch-acc save <name>                               Snapshot current active login to <name>"
      echo "  switch-acc list                                      List all saved profiles and active state"
      echo "  switch-acc switch <name> [--no-restart|--detached]   Swap token in Keychain & restart Antigravity"
      echo "  switch-acc delete <name>                             Delete a saved profile"
      echo "  switch-acc help                                      Show this help message"
      ;;

    *)
      echo "Unknown command: $cmd"
      echo "Run 'switch-acc help' for usage."
      return 1
      ;;
  esac
}

# Zsh Autocompletion for switch-acc
_switch_acc_completion() {
  local -a subcommands
  subcommands=(
    'save:Snapshot current active login to a profile'
    'list:List all saved profiles'
    'switch:Switch active profile and restart Antigravity'
    'delete:Delete a saved profile'
    'help:Show help message'
  )

  if (( CURRENT == 2 )); then
    _describe 'command' subcommands
  elif (( CURRENT == 3 )); then
    case "$words[2]" in
      switch|delete|rm)
        local profiles_dir="$HOME/.gemini/antigravity/profiles"
        if [[ -d "$profiles_dir" ]]; then
          local -a profs
          profs=(${profiles_dir}/*.token(N:t:r))
          _describe 'profile' profs
        fi
        ;;
      save)
        _message 'profile name'
        ;;
    esac
  elif (( CURRENT == 4 )); then
    if [[ "$words[2]" == "switch" ]]; then
      local -a opts
      opts=(
        '--no-restart:Update Keychain without closing the app'
        '--detached:Non-blocking delayed restart for remote sessions'
      )
      _describe 'option' opts
    fi
  fi
}

# Register completion if compdef is available
if (( $+functions[compdef] )); then
  compdef _switch_acc_completion switch-acc
fi

# Allow execution as a standalone script if called directly
if [[ "${ZSH_EVAL_CONTEXT:-}" == "toplevel" ]]; then
  switch-acc "$@"
fi
