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

> When using Delegated Auth, during the first prompt, an admin can tick **"Consent on behalf of your organization"** to avoid future prompts.
>
> Please use `-Auth App` to trigger Application Auth:
>
> ```powershell
> $sec = ConvertTo-SecureString 'Enter client secret' -AsPlainText -Force
>
> .\bulk-wipe.ps1 -InputCsv .\aad-objectids.csv -Mode Retire -Auth App `
>   -TenantId "ceafb87b-bd4a-4aeb-ae30-64206e0cd550" `
>   -ClientId "8ad2fc45-99ec-499e-90ed-ccc97c30a041" `
>   -ClientSecret $sec -WhatIf
> ```

