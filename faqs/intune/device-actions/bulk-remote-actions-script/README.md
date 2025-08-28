# bulk-wipe.ps1

Bulk trigger **Microsoft Intune** remote actions (**Wipe / Retire / Clean Windows**) for a list of **Entra ID (Azure AD) device Object IDs**.

> ⚠️ **Danger zone**  
> `Wipe` and `CleanWindows` can factory-reset devices and permanently remove user data. Always start with `-WhatIf` and verify your list.

---

## What it does

1. Reads a CSV of Entra device **`ObjectId`** values.  
2. Resolves each `ObjectId` → Entra **`DeviceId`** (immutable GUID).  
3. Finds the Intune **managedDevice** via `azureADDeviceId eq '{DeviceId}'` (if multiple, picks the **latest `lastSyncDateTime`**).  
4. Sends the requested remote action (**Wipe / Retire / Clean Windows**).  
5. Writes a result log: `bulk-wipe-log-YYYYMMDD-HHMMSS.csv`.

> The script pins and loads **Microsoft Graph PowerShell SDK v2.25.0** and pre-requests **all required delegated scopes**, so even your first `-WhatIf` will ask for the same permissions as a real run.

---

### Graph modules (auto-handled by the script)

- `Microsoft.Graph.Authentication` **2.25.0**  
- `Microsoft.Graph.DeviceManagement` **2.25.0**  
- `Microsoft.Graph.Identity.DirectoryManagement` **2.25.0**

### Delegated scopes (auto-requested on login)

- `Device.Read.All`  
- `DeviceManagementManagedDevices.ReadWrite.All`  
- `DeviceManagementManagedDevices.PrivilegedOperations.All`

> During the first prompt, an admin can tick **“Consent on behalf of your organization”** to avoid future prompts.

### Intune RBAC

Your Intune role must allow the corresponding **Remote tasks** and cover the **device scope** (scope tags / device groups), e.g.:
- **Wipe** — *Managed devices → Remote tasks → Wipe*  
- **Retire** — *Managed devices → Remote tasks → Retire*  
- **Clean Windows** — matching remote action permission (and Graph `…PrivilegedOperations.All`)

---

## CSV format

**Recommended (header `ObjectId`)**
