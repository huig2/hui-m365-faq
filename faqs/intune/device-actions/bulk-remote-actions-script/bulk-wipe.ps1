# ============== bulk-wipe.ps1 (no CmdletBinding; 使用自带 -WhatIf) ==============
param(
  [Parameter(Mandatory=$true)]
  [string]$InputCsv,                              # 例如 .\aad-objectids.csv

  [ValidateSet('Wipe','Retire','CleanWindows')]
  [string]$Mode = 'Wipe',

  [switch]$KeepEnrollmentData,                    # 仅 Wipe 用
  [switch]$KeepUserData,                          # 仅 Wipe 用
  [switch]$PersistEsimDataPlan,                   # 仅 Wipe 用
  [switch]$WhatIf                                 # 测试：不真正下发命令
)

$ErrorActionPreference='Stop'

# ---- 统一固定 Graph SDK 版本，避免依赖不一致 ----
$GraphVersion = '2.25.0'
Get-Module Microsoft.Graph* | Remove-Module -Force -ErrorAction SilentlyContinue
$mods = 'Microsoft.Graph.Authentication','Microsoft.Graph.DeviceManagement','Microsoft.Graph.Identity.DirectoryManagement'
foreach($m in $mods){
  if (-not (Get-Module -ListAvailable $m | Where-Object Version -eq $GraphVersion)){
    try { Set-PSRepository PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch {}
    if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
      Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    }
    Install-Module $m -Scope CurrentUser -RequiredVersion $GraphVersion -Force -AllowClobber
  }
  Import-Module $m -RequiredVersion $GraphVersion -Force
}

# ---- 定义：确保当前会话拿到所需 Graph Scopes（不足则断开重登）----
function Ensure-GraphScopes {
  param([string[]]$Scopes)
  $ctx = Get-MgContext
  $missing = @()
  if (-not $ctx -or -not $ctx.Scopes) { $missing = $Scopes }
  else { $missing = $Scopes | Where-Object { $_ -notin $ctx.Scopes } }
  if ($missing.Count -gt 0) {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Connect-MgGraph -Scopes $Scopes | Out-Null
  }
}

# ---- 预取高权限（即便 -WhatIf 也会同意完整权限，避免实操 403）----
$required = @(
  "Device.Read.All",
  "DeviceManagementManagedDevices.ReadWrite.All",
  "DeviceManagementManagedDevices.PrivilegedOperations.All"
)
Ensure-GraphScopes -Scopes $required
"Current scopes: $((Get-MgContext).Scopes -join ', ')"

# 读取 CSV（智能识别列名：ObjectId / aadObjectId / 第一列）
$rowsRaw = Import-Csv -Path $InputCsv
if (-not $rowsRaw) { throw "CSV 为空：$InputCsv" }
$colName = ($rowsRaw | Get-Member -MemberType NoteProperty | ForEach-Object Name |
           Where-Object { $_ -in @('ObjectId','objectId','aadObjectId','AadObjectId') } |
           Select-Object -First 1)
if (-not $colName) { $colName = ($rowsRaw | Get-Member -MemberType NoteProperty | Select-Object -First 1).Name }
$rows = $rowsRaw | ForEach-Object { [pscustomobject]@{ ObjectId = $_.$colName } }

$log  = [System.Collections.Generic.List[object]]::new()

foreach ($r in $rows) {
  $objectId = ($r.ObjectId).Trim()
  if (-not $objectId) { continue }

  try {
    # 1) AAD 设备对象 => 取 DeviceId（即 Intune 的 azureADDeviceId）
    $aad = Get-MgDevice -DeviceId $objectId -ErrorAction Stop
    $aadDeviceId = $aad.DeviceId

    # 2) 用 azureADDeviceId 反查 Intune 托管设备
    $mds = Get-MgDeviceManagementManagedDevice -Filter "azureADDeviceId eq '$aadDeviceId'" -All
    if (-not $mds) {
      $log.Add([pscustomobject]@{
        ObjectId=$objectId; AzureADDeviceId=$aadDeviceId; ManagedDeviceId=$null; DeviceName=$null; OS=$null; LastSync=$null;
        Mode=$Mode; Result='NotFoundInIntune'
      }) | Out-Null
      continue
    }
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
          # 需要 DeviceManagementManagedDevices.PrivilegedOperations.All
          Invoke-MgCleanDeviceManagementManagedDeviceWindowsDevice -ManagedDeviceId $md.Id -ErrorAction Stop
          $result = 'CleanWindows sent (204)'
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

$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$out = ".\bulk-wipe-log-$ts.csv"
$log | Export-Csv -NoTypeInformation -Path $out
Write-Host "完成，日志：$out"
# ================= end =================
