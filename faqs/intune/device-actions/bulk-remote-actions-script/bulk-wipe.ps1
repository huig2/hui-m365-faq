# ======= 支持 App-only 或 Delegated 两种认证 =======
param(
  [Parameter(Mandatory=$true)]
  [string]$InputCsv,

  [ValidateSet('Wipe','Retire','CleanWindows')]
  [string]$Mode = 'Wipe',

  # 认证方式：Delegated（交互登录）或 App（应用身份）
  [ValidateSet('Delegated','App')]
  [string]$Auth = 'Delegated',

  # 仅当 -Auth App 时需要：
  [string]$TenantId,
  [string]$ClientId,
  [securestring]$ClientSecret,

  [switch]$KeepEnrollmentData,
  [switch]$KeepUserData,
  [switch]$PersistEsimDataPlan,
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# 计算所需权限列表（仅用于 Delegated 登录时申请 scopes；App-only 不用 scopes）
$required = @("Device.Read.All","DeviceManagementManagedDevices.ReadWrite.All")
if ($Mode -in @('Retire','CleanWindows')) {
  $required += "DeviceManagementManagedDevices.PrivilegedOperations.All"
}

# ======= Graph 模块准备（保持你原有固定版本逻辑即可）=======
$GraphVersion = '2.25.0'
Get-Module Microsoft.Graph* | Remove-Module -Force -ErrorAction SilentlyContinue
$mods = 'Microsoft.Graph.Authentication','Microsoft.Graph.DeviceManagement','Microsoft.Graph.Identity.DirectoryManagement'
foreach($m in $mods){
  if (-not (Get-Module -ListAvailable $m | Where-Object Version -eq $GraphVersion)){
    Install-Module $m -Scope CurrentUser -RequiredVersion $GraphVersion -Force -AllowClobber
  }
  Import-Module $m -RequiredVersion $GraphVersion -Force
}

# ======= 登录（根据 -Auth 分支处理）=======
if (Get-MgContext) { Disconnect-MgGraph -ErrorAction SilentlyContinue }

switch ($Auth) {
  'App' {
    if (-not ($TenantId -and $ClientId -and $ClientSecret)) {
      throw "App auth 需要 -TenantId、-ClientId、-ClientSecret（SecureString）"
    }
    # Graph PowerShell 支持用 Client Secret 进行应用登录（-ClientSecretCredential）
    # 见官方文档示例。 
    # https://learn.microsoft.com/powershell/microsoftgraph/authentication-commands?view=graph-powershell-1.0#use-client-secret-credentials
    $cred = [pscredential]::new($ClientId, $ClientSecret)
    Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $cred -NoWelcome | Out-Null

    # CleanWindows 目前仅支持 Delegated，不支持 App-only
    if ($Mode -eq 'CleanWindows') {
      throw "CleanWindows 需要 Delegated 权限（Graph 文档未列出 Application 权限）；请改用 -Auth Delegated。"
    }
  }

  'Delegated' {
    # 交互登录：用 scopes 申请委派权限
    Connect-MgGraph -Scopes $required -NoWelcome | Out-Null
  }
}

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