# ===================== bulk-wipe-v1.3.ps1 =====================
<#
Bulk trigger Intune remote actions (Wipe / Retire / Clean Windows / Delete)
by Entra device ObjectId list from CSV.

- Supports Delegated (interactive) and App-only (client credentials) auth
- Pins Microsoft Graph PowerShell SDK to 2.25.0 per CurrentUser
- Adds "Delete" action: removes Intune managedDevice record (no device command)
- Uses custom -WhatIf (dry run) to preview mapping and actions
#>

param(
  [Parameter(Mandatory=$true)]
  [string]$InputCsv,                                 # e.g. .\aad-objectids.csv

  [ValidateSet('Wipe','Retire','CleanWindows','Delete')]
  [string]$Mode = 'Wipe',

  # Auth mode: Delegated (interactive with scopes) or App (client credentials)
  [ValidateSet('Delegated','App')]
  [string]$Auth = 'Delegated',

  # App-only auth params
  [string]$TenantId,
  [string]$ClientId,
  [securestring]$ClientSecret,                       # preferred: secure string
  [string]$ClientSecretPlain,                        # optional: plain text -> will convert

  # Wipe options
  [switch]$KeepEnrollmentData,
  [switch]$KeepUserData,
  [switch]$PersistEsimDataPlan,

  # Dry run
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# ---------------- Graph SDK bootstrap (pin 2.25.0) ----------------
$GraphVersion = '2.25.0'
Get-Module Microsoft.Graph* | Remove-Module -Force -ErrorAction SilentlyContinue

$mods = @(
  'Microsoft.Graph.Authentication',
  'Microsoft.Graph.DeviceManagement',
  'Microsoft.Graph.Identity.DirectoryManagement'
)

# Ensure PSGallery/NuGet available (non-fatal if already set)
try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch {}
if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
  Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
}

foreach($m in $mods){
  if (-not (Get-Module -ListAvailable $m | Where-Object Version -eq $GraphVersion)){
    Install-Module $m -Scope CurrentUser -RequiredVersion $GraphVersion -Force -AllowClobber
  }
  Import-Module $m -RequiredVersion $GraphVersion -Force
}

function Ensure-DelegatedScopes {
  param([string[]]$Scopes)
  $ctx = Get-MgContext
  $missing = @()
  if (-not $ctx -or -not $ctx.Scopes) { $missing = $Scopes } else {
    $missing = $Scopes | Where-Object { $_ -notin $ctx.Scopes }
  }
  if ($missing.Count -gt 0) {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Connect-MgGraph -Scopes $Scopes -NoWelcome | Out-Null
  }
}

# ---------------- Login ----------------
if (Get-MgContext) { Disconnect-MgGraph -ErrorAction SilentlyContinue }

# Minimal required permissions (Delegated only; App uses application permissions granted in Entra)
$delegatedScopes = @('Device.Read.All','DeviceManagementManagedDevices.ReadWrite.All')
if ($Mode -in @('Retire','CleanWindows','Delete')) {
  $delegatedScopes += 'DeviceManagementManagedDevices.PrivilegedOperations.All'
}

switch ($Auth) {
  'Delegated' {
    Ensure-DelegatedScopes -Scopes $delegatedScopes
    "AuthMode: Delegated | Scopes: $((Get-MgContext).Scopes -join ', ')"
  }
  'App' {
    if (-not $TenantId -or -not $ClientId) {
      throw "App auth requires -TenantId and -ClientId."
    }
    if (-not $ClientSecret) {
      if ($ClientSecretPlain) {
        $ClientSecret = ConvertTo-SecureString $ClientSecretPlain -AsPlainText -Force
      } else {
        $ClientSecret = Read-Host "Enter client secret" -AsSecureString
      }
    }
    # NOTE: CleanWindows is NOT supported with App-only auth (no Application permission documented)
    if ($Mode -eq 'CleanWindows') {
      throw "CleanWindows is not supported with App-only authentication. Use -Auth Delegated."
    }
    Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -NoWelcome | Out-Null
    "AuthMode: App (client credentials)"
  }
}

# ---------------- Read CSV (detect column) ----------------
$rowsRaw = Import-Csv -Path $InputCsv
if (-not $rowsRaw) { throw "CSV is empty: $InputCsv" }

$colName = ($rowsRaw | Get-Member -MemberType NoteProperty | ForEach-Object Name |
           Where-Object { $_ -in @('ObjectId','objectId','aadObjectId','AadObjectId') } |
           Select-Object -First 1)
if (-not $colName) {
  # no header -> take the first column
  $colName = ($rowsRaw | Get-Member -MemberType NoteProperty | Select-Object -First 1).Name
}
$rows = $rowsRaw | ForEach-Object { [pscustomobject]@{ ObjectId = $_.$colName } }

# ---------------- Process ----------------
$log  = [System.Collections.Generic.List[object]]::new()

foreach ($r in $rows) {
  $objectId = ($r.ObjectId).Trim()
  if (-not $objectId) { continue }

  try {
    # 1) Entra device: use ObjectId to get device -> read DeviceId (immutable)
    $aad = Get-MgDevice -DeviceId $objectId -ErrorAction Stop
    $aadDeviceId = $aad.DeviceId

    # 2) Intune managed device by azureADDeviceId
    $mds = Get-MgDeviceManagementManagedDevice -Filter "azureADDeviceId eq '$aadDeviceId'" -All
    if (-not $mds) {
      $log.Add([pscustomobject]@{
        ObjectId=$objectId; AzureADDeviceId=$aadDeviceId; ManagedDeviceId=$null; DeviceName=$null; OS=$null; LastSync=$null;
        Mode=$Mode; Result='NotFoundInIntune'
      }) | Out-Null
      continue
    }

    # prefer the most recently synced record
    $md = $mds | Sort-Object lastSyncDateTime -Descending | Select-Object -First 1

    $result = 'Simulated (WhatIf)'
    if (-not $WhatIf) {
      switch ($Mode) {
        'Wipe' {
          $body = @{
            keepEnrollmentData  = $KeepEnrollmentData.IsPresent
            keepUserData        = $KeepUserData.IsPresent
            persistEsimDataPlan = $PersistEsimDataPlan.IsPresent
          }
          Clear-MgDeviceManagementManagedDevice -ManagedDeviceId $md.Id -BodyParameter $body -ErrorAction Stop
          $result = 'Wipe sent (204)'
        }
        'Retire' {
          Invoke-MgRetireDeviceManagementManagedDevice -ManagedDeviceId $md.Id -ErrorAction Stop
          $result = 'Retire sent (204)'
        }
        'CleanWindows' {
          # Delegated only (already blocked in App branch)
          Invoke-MgCleanDeviceManagementManagedDeviceWindowsDevice -ManagedDeviceId $md.Id -ErrorAction Stop
          $result = 'CleanWindows sent (204)'
        }
        'Delete' {
          # Delete Intune managedDevice record (no device-side action)
          Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $md.Id -ErrorAction Stop
          $result = 'Delete sent (204)'
        }
      }
    }

    $log.Add([pscustomobject]@{
      ObjectId        = $objectId
      AzureADDeviceId = $aadDeviceId
      ManagedDeviceId = $md.Id
      DeviceName      = $md.DeviceName
      OS              = $md.OperatingSystem
      LastSync        = $md.LastSyncDateTime
      Mode            = $Mode
      Result          = $result
    }) | Out-Null
  }
  catch {
    $log.Add([pscustomobject]@{
      ObjectId=$objectId; AzureADDeviceId=$null; ManagedDeviceId=$null; DeviceName=$null; OS=$null; LastSync=$null;
      Mode=$Mode; Result=("Error: " + $_.Exception.Message)
    }) | Out-Null
  }
}

# ---------------- Output log ----------------
$ts  = Get-Date -Format "yyyyMMdd-HHmmss"
$out = ".\bulk-wipe-log-$ts.csv"
$log | Export-Csv -NoTypeInformation -Path $out
Write-Host "Done. Log: $out"
# ===================== end of file =====================