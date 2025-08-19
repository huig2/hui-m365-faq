# TPM Attestation Troubleshooting in Windows Autopilot
*Applies to: Windows Autopilot (Pre-provisioning), Windows 10/11, Intune*

## Summary
This article details the Pre-Provisioning Autopilot workflow for firmware-based TPM Attestation and troubleshooting steps. Tools and logs are valid for Windows 11, however not all commands may be valid for Windows 10.

---

## Background
# What is Attestation?
- TPM Attestation is the process where the TPM proves its authenticity.
- Endorsement Key (EK): A unique key burned in at manufacturing. The EK Certificate is obtained from the vendor’s CA.
- Attestation Identity Key (AIK): A new key generated during deployment. The AIK Cert is requested from Microsoft using the EK Cert.
- **Flow:**
1. TPM → contacts vendor EK service, retrieves EK certificate
2. TPM → requests AIK certificate from Microsoft AIK service
3. AIK Cert received → Autopilot “Securing your hardware” step completes
   > Firmware TPMs require online access to vendor EK services the first time attestation is attempted.
   > - Intel: https://ekop.intel.com/ekcertservice
   > - Qualcomm: https://ekcert.spserv.microsoft.com/EKCertificate/GetEKCertificate/v1
   > - AMD: https://ftpm.amd.com/pki/aia'''

---

## Before You Start

1. **Confirm TPM 2.0 status and manufacturer**
   ```powershell
   tpmtool getdeviceinformation

   # Example output:
   TPM Present: True
   TPM Version: 2.0
   TPM Manufacturer ID: AMD
   TPM Manufacturer Version: 3.xx.x.x
   Is Initialized: True
   Ready For Attestation: True

2. **Enable debug logging in Registry**
   ```powershell
   $AutoEnrollmentPath = 'HKLM:\SOFTWARE\Microsoft\Cryptography\AutoEnrollment'
   New-ItemProperty -Path $AutoEnrollmentPath -Name 'Debug' -Value 1 -PropertyType DWORD

3. **Install optional TPMTool commands**
   ```powershell
   tpmtool.exe oc add

---

## Troubleshooting by Flow
1. **Connectivity tests:**
   ```powershell
   Invoke-WebRequest "https://<Manufacturer EK Certificate URL>" -DisableKeepAlive
   Test-NetConnection -Port 443 -ComputerName <Domain>
   Start-Process msedge.exe "https://<Manufacturer EK Certificate URL>"
   ```
2. **Successful EK Certificate Acquisition:**
   ```
   Log Name: Microsoft-Windows-ModernDeployment-Diagnostics-Provider/Autopilot
   Source:   Microsoft-Windows-ModernDeployment-Diagnostics-Provider
   Event ID: 208
   Level:    Information
   Message:  Windows EK certificate is present.
   ```

   Registry location of EK certificate:
   ```
   HKLM:\SYSTEM\CurrentControlSet\Services\TPM\WMI\Endorsement\EKCertStore\Certificates\<Thumbprint>
   ```
   Export EK certificate:
   ```powershell
   TPMDiagnostics GetEkCertFromReg C:\IntuneLogs\EkCertFromReg.crt
   ```

   > [!NOTE]  
   > More TPM info:  
   > - `Get-TPMEndorsementKeyInfo`  
   > - `Tpmdiagnostics ekinfo`  
   > - `Tpmdiagnostics ekchain`  


3. **Final Attestation**
   AIK request validation:
   ```
   certreq -enrollaik -config ""
   ```

   AIK success events:
   ```
   Event ID: 250 - AutopilotManager started AIK certificate acquisition task
   Event ID: 251 - AIK certificate acquisition task returned HRESULT = 0x0
   Event ID: 169 - TPM identity confirmed
   ```
---

## Common Fixes
- Update TPM firmware to the latest release
- Ensure the device has open access to vendor EK services and Microsoft AIK service
- For firmware TPM, leave device connected to the internet for 10–15 minutes before provisioning to allow EK certificate caching

## Reference:
[TPM Attestation: What can possibly go wrong?](https://oofhours.com/2019/07/09/tpm-attestation-what-can-possibly-go-wrong/)



