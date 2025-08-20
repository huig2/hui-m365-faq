# Error: Reporting latency in Windows 10 and later feature updates report  
*Applies to: Windows 10, Windows 11 feature update readiness reporting in Intune*  

## Scenario / Symptom
When reviewing the **Windows 10 and later feature updates report** in Intune ([link](https://intune.microsoft.com/#view/Microsoft_Intune_Enrollment/WindowsUpdateOrgReport.ReactView)), devices show **delayed or outdated update status**.  

- Latency can exceed the expected timeframe (up to ~52 hours), which is based on Windows diagnostic data upload and processing cycle.  
- Report attributes such as **Scan Time** and **Event Time** may indicate old timestamps, suggesting telemetry hasn’t refreshed.  
- Expectation: near real-time reporting, but in reality some delay is by design.  

---

## Cause
1. **Expected telemetry delay**  
   - Windows devices rely on scheduled diagnostic tasks to upload update/compatibility telemetry:  
     - `\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp`  
     - `\Microsoft\Windows\UpdateOrchestrator\ScheduleScan`  
   - These tasks run every 6 hours. If the device is powered off, asleep, or blocked, the data will not refresh.  

2. **Delta sync ingestion issues**  
   - Intune reporting pipeline ingests telemetry via delta syncs.  
   - If the delta sync fails (e.g., incomplete dataset), UI may not reflect latest info until a **full sync** occurs.  

3. **Telemetry services / configuration gaps**  
   - Required services must be running: **DiagTrack**, **wuauserv**, **Task Scheduler**, and their dependency chain (RPC, DcomLaunch, RpcEptMapper).  
   - Device must be Azure AD authenticated (`dsregcmd /status`).  
   - Telemetry GPO or registry values set to `0` disable uploads (must be ≥1).  

---

## Verification Steps
1. **Check if it’s a reporting delay vs. update failure**  
   - In Intune portal: *Devices → All devices → Device → Hardware → Operating system version*.  
   - If device has not actually installed the feature update, then it’s not reporting latency but a policy/update deployment issue.  

2. **Confirm telemetry freshness**  
   - In the Feature Updates report:  
     - **Scan Time** → last update scan on device.  
     - **Event Time** → when telemetry reached the service.  
   - Compare timestamps against expected ~52h cycle.  

3. **Inspect local telemetry**  
   - Run appraiser manually:  
     ```powershell
     Compattelrunner.exe -m:appraiser.dll -f:DoScheduledTelemetryRun
     ```  
     Allow 3–5 days for telemetry to surface.  
   - Review registry dumps:  
     - `AppraiserUpgradeIndicators_RegDump` [HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\TargetVersionUpgradeExperienceIndicators
     ] → check `DataRelDate` / `DataExpDate` freshness.  
     - `Census_RegDump` [HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Census
     ] → `ReturnCode=0` and `RunCounter` increment indicates success.  

---

## Resolution
- **Validate device readiness**  
  - Ensure required services and tasks are running.  
  - Confirm no GPO/registry sets telemetry to `0`.  
  - Verify device Azure AD authentication.  

- **Trigger manual telemetry refresh**  
  - Run `Compattelrunner.exe` or push via Intune script.  
  - Wait 52h (up to 3–5 days) for data ingestion.  

- **Escalation paths**  
  1. If telemetry is collected but not surfacing in Intune → Verify network endpoints for diagnostic data ([doc](https://learn.microsoft.com/windows/privacy/configure-windows-diagnostic-data-in-your-organization)).  
  2. If telemetry is fresh but report still stale >3–5 days → Open Microsoft support case.  

---

## References
- [Use Windows compatibility reports for updates in Intune](https://learn.microsoft.com/mem/intune/protect/windows-update-for-business-reports)  
- [Troubleshooting Windows Feature Updates in Intune – Community Hub](https://techcommunity.microsoft.com/)  
- [Configure Windows diagnostic data in your organization](https://learn.microsoft.com/windows/privacy/configure-windows-diagnostic-data-in-your-organization)  

---