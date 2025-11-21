# Standalone AppDynamics Licensing API Test Script

## Overview

`test_all_controllers_standalone.sh` is a **fully portable** test script for the AppDynamics Licensing API v1. It works on **Linux, macOS, and Windows** (Git Bash/WSL) with **no AWS dependencies**.

---

## ✅ Features

- **Cross-Platform**: Works on Linux, macOS, Windows (Git Bash/WSL)
- **No Dependencies**: No AWS CLI, jq, or special tools required (only curl + python/python3)
- **Interactive**: Prompts for all credentials - no hardcoding needed
- **Comprehensive**: Tests all controllers and both API endpoints
- **Color-Coded Output**: Easy-to-read results with visual indicators

---

## 🚀 Quick Start

### On Linux/macOS:

```bash
bash test_all_controllers_standalone.sh
```

### On Windows (Git Bash):

```bash
bash test_all_controllers_standalone.sh
```

### On Windows (WSL - Ubuntu/Debian):

```bash
bash test_all_controllers_standalone.sh
```

---

## 📋 What You'll Need

The script will prompt you for:

1. **Controller URLs** (comma-separated)
   - Example: `pepsi-test.saas.appdynamics.com,pepsico-nonprod.saas.appdynamics.com`

2. **Account Names** (comma-separated, same order as controllers)
   - Example: `pepsi-test,pepsico-nonprod`

3. **Account IDs** (comma-separated, same order as controllers)
   - Example: `193,259`

4. **OAuth Client IDs** (comma-separated, same order as controllers)
   - Example: `your-client-id-1,your-client-id-2`

5. **OAuth Client Secrets** (comma-separated, same order as controllers)
   - Input is hidden for security
   - Example: `secret1,secret2`

---

## 📖 Example Session

```bash
$ bash test_all_controllers_standalone.sh

======================================================================
  AppDynamics Licensing API v1 - Standalone Test
  Cross-Platform (Linux/macOS/Windows Git Bash/WSL)
======================================================================

This script will test the AppDynamics Licensing API v1 endpoints
for all configured controllers.

You will be prompted to enter your credentials.

Press ENTER to continue or Ctrl+C to exit...

======================================================================
  Enter AppDynamics Credentials
======================================================================

Enter comma-separated values for multiple controllers.
Example: controller1.com,controller2.com,controller3.com

Enter Controller URLs (comma-separated):
pepsi-test.saas.appdynamics.com,pepsico-nonprod.saas.appdynamics.com

Enter Account Names (comma-separated, same order as controllers):
pepsi-test,pepsico-nonprod

Enter Account IDs (comma-separated, same order as controllers):
193,259

Enter OAuth Client IDs (comma-separated, same order as controllers):
my-client-id-1,my-client-id-2

Enter OAuth Client Secrets (comma-separated, same order as controllers):
(Input will be hidden)
[user types secrets]

✅ Credentials entered

======================================================================
  Validating Configuration
======================================================================

✅ Found 2 controllers to test

  1. pepsi-test.saas.appdynamics.com
     Account: pepsi-test
     Account ID: 193
     Client ID: my-client-id-1...

  2. pepsico-nonprod.saas.appdynamics.com
     Account: pepsico-nonprod
     Account ID: 259
     Client ID: my-client-id-2...

Press ENTER to start testing...

[Tests run...]
```

---

## 🔍 What Gets Tested

For each controller, the script tests:

### Test 1: Account-Level Usage API
- **Endpoint**: `/controller/licensing/v1/usage/account/{accountId}`
- **Purpose**: Verify account-level license usage data access
- **Required Permission**: `READ LICENSE_USAGE`

### Test 2: Grouped Usage by Application API
- **Endpoint**: `/controller/licensing/v1/account/{accountId}/grouped-usage/application/by-id`
- **Purpose**: Verify per-application license usage data access
- **Required Permission**: `READ ACCOUNT_LICENSE`

---

## ✅ Expected Results

### If Permissions Are Granted:
```
======================================================================
  OVERALL SUMMARY - ALL CONTROLLERS
======================================================================

Controller 1: pepsi-test.saas.appdynamics.com
  Account-Level API: PASS
  Grouped Usage API: PASS

🎉 ALL CONTROLLERS PASSED ALL TESTS!
```

### If Permissions Are Missing (403):
```
======================================================================
  OVERALL SUMMARY - ALL CONTROLLERS
======================================================================

Controller 1: pepsi-test.saas.appdynamics.com
  Account-Level API: FAIL_PERMISSION
  Grouped Usage API: FAIL_PERMISSION

❌ PERMISSION ISSUES DETECTED

Required Permissions:
  - READ LICENSE_USAGE
  - READ ACCOUNT_LICENSE

How to Fix:
  1. Log into each AppDynamics Controller UI
  2. Navigate to: Settings → Administration → API Clients
  3. For each OAuth client, assign 'License Admin' role
  4. Save and wait 1-2 minutes for permissions to propagate
  5. Re-run this test script
```

---

## 🖥️ Platform-Specific Notes

### Linux
- **Requirements**: bash, curl, python3 (or python)
- **Tested on**: Ubuntu 20.04+, RHEL 8+, Debian 11+
- Run with: `bash test_all_controllers_standalone.sh`

### macOS
- **Requirements**: bash (built-in), curl (built-in), python3 (built-in on macOS 10.15+)
- Run with: `bash test_all_controllers_standalone.sh`

### Windows (Git Bash)
- **Requirements**: Git for Windows (includes bash, curl)
- **Download**: https://git-scm.com/download/win
- **Python**: Install Python from python.org if not present
- Run in **Git Bash terminal** (not CMD or PowerShell)

### Windows (WSL)
- **Requirements**: WSL 2 with Ubuntu/Debian
- **Setup**: `wsl --install` (Windows 10/11)
- Run with: `bash test_all_controllers_standalone.sh`

---

## 🔧 Troubleshooting

### Error: "curl: command not found"
**Solution**: Install curl
- Linux: `sudo apt-get install curl` (Debian/Ubuntu) or `sudo yum install curl` (RHEL)
- macOS: curl is built-in
- Windows: Install Git for Windows or WSL

### Error: "python: command not found"
**Solution**: The script tries python3, then python, then falls back to basic parsing
- Linux: `sudo apt-get install python3`
- macOS: python3 is built-in on 10.15+
- Windows: Download from python.org or use WSL

### Error: "Mismatched credential counts"
**Solution**: Ensure all comma-separated lists have the same number of entries
- 3 controllers = 3 accounts = 3 account IDs = 3 client IDs = 3 secrets

### Error: "OAuth failed"
**Solution**: Check your client ID and secret are correct
- Format: `client_id@account_name`
- The script automatically formats this for you

---

## 📤 Sharing This Script

To share with colleagues:

1. **Copy the script**:
   ```bash
   cp test_all_controllers_standalone.sh /path/to/share/
   ```

2. **Or send via email** - it's a single self-contained file

3. **Instructions for recipient**:
   - Save the script to any location
   - Make executable: `chmod +x test_all_controllers_standalone.sh`
   - Run: `bash test_all_controllers_standalone.sh`
   - Enter credentials when prompted

---

## 🔐 Security Notes

- **Client secrets are hidden** during input (using `read -rs`)
- **No credentials are logged** or saved to disk
- **No network calls** except to AppDynamics controllers
- Script can be reviewed before running (it's plain bash)

---

## 📚 Related Documentation

- [AppDynamics License API Research](../../docs/APPDYNAMICS_LICENSE_API_RESEARCH.md)
- [Manual Test Guide](../../docs/LICENSING_API_MANUAL_TEST_GUIDE.md)
- [Deployment Guide](../../docs/DEPLOYMENT_GUIDE.md)

---

## 🐛 Known Limitations

- **No jq required**: Script uses python for JSON parsing (more portable)
- **Date calculations**: Falls back to simple dates if python not available
- **Windows CMD/PowerShell**: Not supported - use Git Bash or WSL instead

---

## ✨ Example Output

```
======================================================================
TESTING CONTROLLER 1/2
======================================================================

Controller:  pepsi-test.saas.appdynamics.com
Account:     pepsi-test
Account ID:  193

Step 1: Getting OAuth token...
✅ OAuth token obtained

Step 2: Testing Account-Level Usage API...
  Endpoint: /controller/licensing/v1/usage/account/193
  Status: 200
  Result: ✅ SUCCESS
  Response preview:
  {
    "accountId": 193,
    "packages": [...]
  }

Step 3: Fetching application IDs...
  Result: ✅ Found 128 applications

Step 4: Testing Grouped Usage API...
  Endpoint: /controller/licensing/v1/account/193/grouped-usage/application/by-id
  Status: 200
  Result: ✅ SUCCESS
  Response preview:
  [
    {
      "applicationId": 2260713,
      "applicationName": "My App",
      "vCPUTotal": 24
    }
  ]

Controller 1 Summary:
  Account-Level API: PASS
  Grouped Usage API: PASS
```

---

**Created:** 2025-11-20
**Version:** 1.0
**Maintainer:** Analytics Platform Team
