---
name: antigravity-account-switcher
description: View saved Google Antigravity account profiles and switch active accounts remotely without manual browser re-login.
---

# Antigravity Account Switcher Skill

Use this skill when the user asks to list, view, or switch between Google Antigravity accounts (e.g., when hitting model quotas or rate limits).

## Actions

### 1. List Available Accounts
When the user asks which accounts are available or which account is active:
Run:
```bash
switch-acc list
```
Format the resulting table clearly in your response, highlighting the `[ACTIVE]` account and its email.

### 2. Switch Account (Remote / In-Chat)
When the user requests to switch to a specific account profile (e.g., "switch to acc1"):
1. Confirm the profile exists by running `switch-acc list`.
2. Execute the switch with `--detached`:
   ```bash
   switch-acc switch <profile_name> --detached
   ```
3. Inform the user of the target account email, that the Keychain token was swapped, and that Antigravity is restarting in 2 seconds (the remote session will briefly reconnect automatically).
