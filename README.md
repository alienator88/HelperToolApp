# HelperToolApp

HelperToolApp is a demo macOS application that works alongside a privileged helper tool to perform tasks requiring elevated privileges using `SMAppService` instead of `SMJobBless`.

![image](https://github.com/user-attachments/assets/1cff250f-447e-432a-afab-46d41291ca35)

## Features
- Installs and registers privileged helper tool as a launch daemon.
- Handles privileged operations securely using XPC.
- Uses the newer `SMAppService` framework for safe and Apple-approved privilege escalation.
- Executes shell commands via root user

## Usage
The helper tool is automatically installed when the main app registers it. The user must enable it in **System Settings > Login Items** on first registration.
This is a limitation introduced by Apple to better line up with their security practices, SMAppService can't ask for password prompt to approve on daemon install unfortunately so developers have to direct users to the Settings for approval now on the initial registration.

The main app interacts with the helper tool via `XPC` to perform privileged tasks via the runCommand function which in turn executes bash shell commands as root.

## Debugging
If the helper tool fails to install:
1. Ensure the app is **signed with a Developer ID Certificate** (for Release scheme).
2. Check if the helper tool is included inside the app bundle at `/Contents/Library/HelperTools`
3. Check if the plist file is included inside the app bundle at `/Contents/Library/LaunchDaemons`
4. Run this command to check macOS system logs:
   ```sh
   log stream --style compact --predicate 'subsystem == "com.apple.libxpc.SMAppService"'
   ```

## Code Signing
Check helper tool code sign with:
`codesign -dv --verbose=4 /path/to/YourApp.app/Contents/Library/HelperTools/HelperTool`  
